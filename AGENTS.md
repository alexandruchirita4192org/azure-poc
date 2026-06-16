# AGENTS.md

## Global Instructions

- For Docker on Windows, use the free Docker Engine from the WSL2 environment instead of Docker Desktop, which is not free for enterprise environments.
- For Agents, use `C:\Users\[user]\.codex\agents`.
- For Skills, use `C:\Users\[user]\.codex\skills`.
- To determine `[user]`, run `whoami` and use the username portion without the domain prefix.

## Project Overview

- This repo is an Azure Order Flow proof of concept for managed-identity-first order intake and processing.
- The workload is a thin vertical slice across App Service, API Management, Azure SQL, Cosmos DB, Storage Blob, Service Bus, Event Grid, Azure Functions, Container Apps, Key Vault, Application Insights, ACR, and GitHub Actions.
- The primary flow is: client -> API Management -> `OrderApi` -> SQL/Cosmos/Blob + Service Bus + Event Grid -> `OrderWorker` and `OrderFunctions`.
- Treat this as a breadth-of-integration PoC, not production-ready domain logic.

## Repository Map

- `src/OrderApi/`: ASP.NET Core minimal API on .NET 10. `POST /orders` validates `X-Order-Api-Key`, writes SQL/Cosmos/Blob, sends Service Bus, publishes Event Grid, and emits Azure Monitor telemetry.
- `src/OrderFunctions/`: .NET 10 isolated Azure Functions app. `OrderEventFunction` handles Event Grid `OrderCreated` events and logs event metadata.
- `src/OrderWorker/`: .NET 10 worker service for Container Apps. Consumes Service Bus messages and logs processing metadata. The worker image is built from `src/OrderWorker/Dockerfile`.
- `infra/`: Bicep deployment. `main.bicep` provisions Azure resources, managed identities, RBAC assignments, app settings, APIM policy, and deployment outputs. `main.parameters.json` contains non-secret defaults.
- `scripts/`: Operational scripts. `deploy.sh` runs Azure CLI deployment; `validate-security.ps1` checks security invariants; `sql-managed-identity-bootstrap.sql` bootstraps SQL data-plane schema and permissions.
- `.github/workflows/azure-poc.yml`: Manual production deployment workflow using Azure OIDC, locked .NET restore, vulnerability checks, Bicep validation/deployment, app publishing, worker image build/scan/sign/verify, and Container Apps digest deployment.
- `docs/`: ADR, runbook, and test plan. Consult docs when changing architecture, deployment, operations, or test expectations.

## Build And Validation

- Use .NET 10. The GitHub workflow currently pins `DOTNET_VERSION` to `10.0.x`.
- Restore with locked packages:
  - `dotnet restore src/OrderApi/OrderApi.csproj --locked-mode`
  - `dotnet restore src/OrderFunctions/OrderFunctions.csproj --locked-mode`
  - `dotnet restore src/OrderWorker/OrderWorker.csproj --locked-mode`
- Build each project directly:
  - `dotnet build src/OrderApi/OrderApi.csproj`
  - `dotnet build src/OrderFunctions/OrderFunctions.csproj`
  - `dotnet build src/OrderWorker/OrderWorker.csproj`
- Run security validation after infra, workflow, Docker, or security-sensitive changes:
  - `pwsh ./scripts/validate-security.ps1`
- `Directory.Build.props` enables NuGet lock files, NuGet audit, and treats moderate-or-higher package vulnerabilities as errors.

## Deployment Notes

- Local deployment uses `scripts/deploy.sh` with `SQL_ADMINISTRATOR_PASSWORD` and `ORDER_API_BACKEND_KEY` set in the environment.
- GitHub Actions deployment requires `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `SQL_ADMINISTRATOR_PASSWORD`, and `ORDER_API_BACKEND_KEY`.
- The production workflow is intentionally restricted to `refs/heads/master`.
- Azure SQL managed identity bootstrap is a separate data-plane step; do not move SQL DDL into the API request path.

## Security Invariants

- Keep secrets out of `infra/main.parameters.json`; pass secret values through protected environment variables or GitHub secrets.
- Preserve managed identity as the default access pattern for Azure services wherever supported.
- Keep APIM subscription enforcement and backend key injection for `POST /orders`; direct App Service requests without the backend key must fail.
- Do not log customer identifiers, message bodies, or Event Grid payloads.
- Keep GitHub Actions pinned to explicit action commit SHAs and explicit runner images.
- Keep worker Docker base images digest-pinned.
- Keep `.dockerignore` deny-all with only required worker build context allowlisted; do not copy the whole repository in the Dockerfile.
- Keep worker image build provenance/SBOM, HIGH/CRITICAL Trivy gate, failed-scan ACR digest deletion, Sigstore signing, signature verification, and immutable digest deployment.
