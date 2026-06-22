param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
}

function Read-RepoFile {
    param([string]$RelativePath)
    Get-Content -Raw -LiteralPath (Join-Path $Root $RelativePath)
}

$bicep = Read-RepoFile 'infra/main.bicep'
$parameters = Read-RepoFile 'infra/main.parameters.json'
$workflow = Read-RepoFile '.github/workflows/azure-poc.yml'
$apiProgram = Read-RepoFile 'src/OrderApi/Program.cs'
$workerProgram = Read-RepoFile 'src/OrderWorker/Program.cs'
$functionCode = Read-RepoFile 'src/OrderFunctions/OrderEventFunction.cs'
$bootstrapSql = Read-RepoFile 'scripts/sql-managed-identity-bootstrap.sql'
$dockerfile = Read-RepoFile 'src/OrderWorker/Dockerfile'
$directoryBuild = Read-RepoFile 'Directory.Build.props'
$dockerignore = Read-RepoFile '.dockerignore'

if ($parameters -match '"sqlAdministratorPassword"\s*:') {
    Add-Failure 'infra/main.parameters.json must not contain sqlAdministratorPassword.'
}

if ($workflow -match '--parameters\s+infra/main\.parameters\.json(?![^\r\n]*sqlAdministratorPassword=)') {
    Add-Failure 'GitHub Actions deployment must pass sqlAdministratorPassword from a protected secret override.'
}

if ($bicep -match "publicNetworkAccess:\s*'Enabled'") {
    Add-Failure 'Azure SQL publicNetworkAccess must not default to Enabled.'
}

if ($bicep -match 'AllowAllWindowsAzureIps') {
    Add-Failure 'Azure SQL must not include the AllowAllWindowsAzureIps firewall rule.'
}

if ($bicep -match 'subscriptionRequired:\s*false') {
    Add-Failure 'APIM Orders API must not disable subscription enforcement.'
}

if ($apiProgram -notmatch 'OrderApiKeyMiddleware') {
    Add-Failure 'Order API must enforce backend API key middleware for direct App Service requests.'
}

if ($bicep -notmatch 'X-Order-Api-Key' -or $bicep -notmatch 'order-api-backend-key') {
    Add-Failure 'APIM must inject the backend API key header through a secret named value.'
}

if ($bicep -match 'AzureWebJobsStorage[\s\S]{0,500}AccountKey=') {
    Add-Failure 'Function AzureWebJobsStorage must not be configured with an account key.'
}

if ($bicep -notmatch 'AzureWebJobsStorage__credential[\s\S]{0,100}managedidentity') {
    Add-Failure 'Function AzureWebJobsStorage must use managed identity configuration.'
}

if ($bootstrapSql -match 'db_ddladmin') {
    Add-Failure 'Runtime App Service SQL bootstrap must not grant db_ddladmin.'
}

if ($apiProgram -match 'EnsureSqlSchemaAsync|CREATE TABLE dbo\.Orders') {
    Add-Failure 'Order API must not run SQL DDL from the request path.'
}

if ($apiProgram -match 'LogInformation\([^\r\n]*CustomerId' -or
    $workerProgram -match '\{Body\}|Message\.Body\.ToString\(\)' -or
    $functionCode -match '\{Payload\}|eventGridEvent\.Data\.ToString\(\)') {
    Add-Failure 'Application logs must not include customer identifiers, message bodies, or Event Grid payloads.'
}

if ($workflow -match 'ubuntu-latest') {
    Add-Failure 'GitHub Actions must use an explicit runner image instead of ubuntu-latest.'
}

if ($workflow -notmatch 'GITHUB_REF"\s*=\s*"refs/heads/master"') {
    Add-Failure 'Production deployment workflow must reject non-master branch runs.'
}

$actionUses = [regex]::Matches($workflow, '(?m)^\s*uses:\s+([^@\s]+)@([^\s]+)\s*$')
foreach ($actionUse in $actionUses) {
    $actionRef = $actionUse.Groups[2].Value
    if ($actionRef -notmatch '^[a-f0-9]{40}$') {
        Add-Failure "GitHub Actions reference '$($actionUse.Groups[1].Value)@$actionRef' must be pinned to a 40-character commit SHA."
    }
}

if ($workflow -notmatch '--locked-mode' -or
    $directoryBuild -notmatch '<NuGetAudit>true</NuGetAudit>' -or
    $directoryBuild -notmatch 'NU1902;NU1903;NU1904') {
    Add-Failure 'CI must use locked restore and fail on moderate-or-higher NuGet vulnerability audit findings.'
}

$dockerStageAliases = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$dockerFromLines = [regex]::Matches($dockerfile, '(?m)^\s*FROM\s+(\S+)(?:\s+AS\s+([A-Za-z0-9_.-]+))?')
foreach ($dockerFromLine in $dockerFromLines) {
    $imageRef = $dockerFromLine.Groups[1].Value
    if (-not $dockerStageAliases.Contains($imageRef) -and $imageRef -notmatch '@sha256:[a-f0-9]{64}$') {
        Add-Failure "Docker base image '$imageRef' must be pinned by digest."
    }
    if ($dockerFromLine.Groups[2].Success) {
        $dockerStageAliases.Add($dockerFromLine.Groups[2].Value) | Out-Null
    }
}

if ($dockerfile -match 'COPY\s+\.\s+\.') {
    Add-Failure 'Dockerfile must not copy the entire repository into the worker build context.'
}

if (-not (Test-Path -LiteralPath (Join-Path $Root '.dockerignore'))) {
    Add-Failure 'Repository must include .dockerignore for the worker image build context.'
}

if ($dockerignore -notmatch '(?m)^\*$' -or
    $dockerignore -notmatch '(?m)^!Directory\.Build\.props$' -or
    $dockerignore -notmatch '(?m)^!src/OrderWorker/\*\*$' -or
    $dockerignore -match '(?m)^!(docs|infra|scripts|\.github)/') {
    Add-Failure 'Docker build context must use a deny-all allowlist limited to Directory.Build.props and src/OrderWorker.'
}

$requiredDockerignoreDenyPatterns = @(
    'src/OrderWorker/appsettings\*\.json',
    'src/OrderWorker/\*\*/appsettings\*\.json',
    'src/OrderWorker/\.env\*',
    'src/OrderWorker/\*\*/\.env\*',
    'src/OrderWorker/\*\.pfx',
    'src/OrderWorker/\*\*/\*\.pfx',
    'src/OrderWorker/\*\.pem',
    'src/OrderWorker/\*\*/\*\.pem',
    'src/OrderWorker/\*\.key',
    'src/OrderWorker/\*\*/\*\.key',
    'src/OrderWorker/secrets\.\*',
    'src/OrderWorker/\*\*/secrets\.\*'
)
foreach ($requiredDockerignoreDenyPattern in $requiredDockerignoreDenyPatterns) {
    if ($dockerignore -notmatch "(?m)^$requiredDockerignoreDenyPattern$") {
        Add-Failure "Docker build context must deny '$($requiredDockerignoreDenyPattern -replace '\\', '')'."
    }
}

if ($workflow -notmatch '--sbom=true' -or
    $workflow -notmatch '--provenance=true' -or
    $workflow -notmatch '--metadata-file' -or
    $workflow -notmatch 'containerimage\.digest') {
    Add-Failure 'Worker image build must emit SBOM and provenance metadata.'
}

if ($workflow -notmatch 'trivy-action' -or
    $workflow -notmatch 'severity:\s*HIGH,CRITICAL' -or
    $workflow -notmatch "exit-code:\s*'1'") {
    Add-Failure 'Worker image must have a HIGH/CRITICAL vulnerability scan gate before deployment.'
}

if ($workflow -notmatch 'az acr repository delete' -or
    $workflow -notmatch '--image "order-worker@\$\{\{ steps\.worker_image\.outputs\.digest \}\}"') {
    Add-Failure 'Worker image digest must be deleted from ACR when the vulnerability scan fails.'
}

if ($workflow -notmatch 'cosign-installer' -or
    $workflow -notmatch 'cosign sign --yes' -or
    $workflow -notmatch 'cosign verify') {
    Add-Failure 'Worker image must be signed and signature-verified before deployment.'
}

if ($workflow -match '--certificate-identity-regexp' -or
    $workflow -notmatch '--certificate-identity "https://github\.com/\$\{\{ github\.repository \}\}/\.github/workflows/azure-poc\.yml@refs/heads/master"') {
    Add-Failure 'Cosign verification must pin the signing workflow identity to refs/heads/master.'
}

if ($workflow -notmatch 'digest_image' -or
    $workflow -notmatch '--image "\$\{\{ steps\.worker_image\.outputs\.digest_image \}\}"') {
    Add-Failure 'Container Apps deployment must use the immutable worker image digest output.'
}

if ($failures.Count -gt 0) {
    Write-Error ("Security validation failed:`n - " + ($failures -join "`n - "))
}

Write-Host 'Security validation passed.'
