@description('Short environment name used in resource names.')
param environmentName string = 'azpoc'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('SQL administrator login for PoC deployment.')
param sqlAdministratorLogin string

@secure()
@description('SQL administrator password for PoC deployment. Store securely in CI/CD secrets.')
param sqlAdministratorPassword string

@secure()
@description('Shared secret injected by APIM and validated by the Order API backend.')
param orderApiBackendKey string

@description('Optional Microsoft Entra administrator display name for Azure SQL.')
param sqlEntraAdministratorLogin string = ''

@description('Optional Microsoft Entra administrator object id for Azure SQL.')
param sqlEntraAdministratorObjectId string = ''

var suffix = uniqueString(resourceGroup().id, environmentName)
var namePrefix = '${environmentName}-${suffix}'
var tags = {
  workload: 'azure-order-flow-poc'
  environment: environmentName
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${namePrefix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${namePrefix}'
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-${namePrefix}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.42.0.0/16'
      ]
    }
  }
}

resource appIntegrationSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  name: 'app-integration'
  parent: virtualNetwork
  properties: {
    addressPrefix: '10.42.1.0/24'
    delegations: [
      {
        name: 'web-farm'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
  }
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  name: 'private-endpoints'
  parent: virtualNetwork
  properties: {
    addressPrefix: '10.42.2.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: toLower(replace('st${environmentName}${suffix}', '-', ''))
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  name: 'default'
  parent: storage
}

resource orderPayloads 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: 'order-payloads'
  parent: blobService
  properties: {
    publicAccess: 'None'
  }
}

resource functionStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: toLower(replace('funcst${environmentName}${suffix}', '-', ''))
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: 'sb-${namePrefix}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
}

resource orderQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'orders'
  parent: serviceBus
  properties: {
    lockDuration: 'PT1M'
    maxDeliveryCount: 5
    deadLetteringOnMessageExpiration: true
  }
}

resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: 'egt-${namePrefix}'
  location: location
  tags: tags
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: toLower(replace('acr${environmentName}${suffix}', '-', ''))
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: 'cosmos-${namePrefix}'
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
  }
}

resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  name: 'orders'
  parent: cosmos
  properties: {
    resource: {
      id: 'orders'
    }
  }
}

resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  name: 'order-documents'
  parent: cosmosDb
  properties: {
    resource: {
      id: 'order-documents'
      partitionKey: {
        paths: [
          '/customerId'
        ]
        kind: 'Hash'
      }
    }
  }
}

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: 'sql-${namePrefix}'
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdministratorLogin
    administratorLoginPassword: sqlAdministratorPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
  }
}

resource sqlDb 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  name: 'orders'
  parent: sqlServer
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
}

resource sqlEntraAdministrator 'Microsoft.Sql/servers/administrators@2023-08-01-preview' = if (!empty(sqlEntraAdministratorLogin) && !empty(sqlEntraAdministratorObjectId)) {
  name: 'ActiveDirectory'
  parent: sqlServer
  properties: {
    administratorType: 'ActiveDirectory'
    login: sqlEntraAdministratorLogin
    sid: sqlEntraAdministratorObjectId
    tenantId: tenant().tenantId
  }
}

resource sqlPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink${environment().suffixes.sqlServerHostname}'
  location: 'global'
  tags: tags
}

resource sqlPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: 'vnet-${namePrefix}'
  parent: sqlPrivateDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource sqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-sql-${namePrefix}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'sql-server'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }
}

resource sqlPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  name: 'default'
  parent: sqlPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'sql-server'
        properties: {
          privateDnsZoneId: sqlPrivateDnsZone.id
        }
      }
    ]
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${namePrefix}'
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enabledForTemplateDeployment: true
  }
}

resource sqlConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'Sql--ConnectionString'
  parent: keyVault
  properties: {
    value: 'Server=tcp:${sqlServer.name}${environment().suffixes.sqlServerHostname},1433;Initial Catalog=${sqlDb.name};Authentication=Active Directory Managed Identity;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
  }
}

resource orderApiBackendKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'OrderApi--ApiKey'
  parent: keyVault
  properties: {
    value: orderApiBackendKey
  }
}

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'asp-${namePrefix}'
  location: location
  tags: tags
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  properties: {
    reserved: true
  }
}

resource apiApp 'Microsoft.Web/sites@2023-12-01' = {
  name: 'app-${namePrefix}'
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    virtualNetworkSubnetId: appIntegrationSubnet.id
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'Storage__AccountName'
          value: storage.name
        }
        {
          name: 'Storage__PayloadContainer'
          value: orderPayloads.name
        }
        {
          name: 'ServiceBus__Namespace'
          value: '${serviceBus.name}.servicebus.windows.net'
        }
        {
          name: 'ServiceBus__QueueName'
          value: orderQueue.name
        }
        {
          name: 'Cosmos__Endpoint'
          value: cosmos.properties.documentEndpoint
        }
        {
          name: 'Cosmos__Database'
          value: cosmosDb.name
        }
        {
          name: 'Cosmos__Container'
          value: cosmosContainer.name
        }
        {
          name: 'EventGrid__TopicEndpoint'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'Sql__ConnectionString'
          value: '@Microsoft.KeyVault(SecretUri=${sqlConnectionSecret.properties.secretUriWithVersion})'
        }
        {
          name: 'OrderApi__ApiKey'
          value: '@Microsoft.KeyVault(SecretUri=${orderApiBackendKeySecret.properties.secretUriWithVersion})'
        }
      ]
    }
    httpsOnly: true
  }
}

resource containerEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${namePrefix}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

resource worker 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-worker-${namePrefix}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: []
    }
    template: {
      containers: [
        {
          name: 'order-worker'
          image: 'mcr.microsoft.com/dotnet/runtime:10.0'
          env: [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
            {
              name: 'ServiceBus__Namespace'
              value: '${serviceBus.name}.servicebus.windows.net'
            }
            {
              name: 'ServiceBus__QueueName'
              value: orderQueue.name
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 3
      }
    }
  }
}

resource functionPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'funcplan-${namePrefix}'
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: 'func-${namePrefix}'
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionPlan.id
    httpsOnly: true
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: 'https://${functionStorage.name}.blob.${environment().suffixes.storage}'
        }
        {
          name: 'AzureWebJobsStorage__queueServiceUri'
          value: 'https://${functionStorage.name}.queue.${environment().suffixes.storage}'
        }
        {
          name: 'AzureWebJobsStorage__tableServiceUri'
          value: 'https://${functionStorage.name}.table.${environment().suffixes.storage}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
      ]
    }
  }
}

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: 'apim-${namePrefix}'
  location: location
  tags: tags
  sku: {
    name: 'Consumption'
    capacity: 0
  }
  properties: {
    publisherEmail: 'azure-poc@example.com'
    publisherName: 'Azure PoC'
  }
}

resource orderApiBackendKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  name: 'order-api-backend-key'
  parent: apim
  properties: {
    displayName: 'order-api-backend-key'
    secret: true
    value: orderApiBackendKey
  }
}

resource ordersApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  name: 'orders-api'
  parent: apim
  properties: {
    displayName: 'Orders API'
    path: 'orders'
    protocols: [
      'https'
    ]
    serviceUrl: 'https://${apiApp.properties.defaultHostName}/orders'
    subscriptionRequired: true
  }
}

resource ordersPost 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  name: 'create-order'
  parent: ordersApi
  properties: {
    displayName: 'Create order'
    method: 'POST'
    urlTemplate: '/'
    responses: [
      {
        statusCode: 202
        description: 'Accepted'
      }
    ]
  }
}

resource ordersApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  name: 'policy'
  parent: ordersApi
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <rate-limit calls="60" renewal-period="60" />
    <set-header name="X-Order-Api-Key" exists-action="override">
      <value>{{order-api-backend-key}}</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
  dependsOn: [
    orderApiBackendKeyNamedValue
  ]
}

var keyVaultSecretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var storageBlobDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var storageBlobDataOwnerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
var storageQueueDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
var storageTableDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
var serviceBusDataSenderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39')
var serviceBusDataReceiverRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0')
var eventGridDataSenderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'd5a91429-5739-47e2-a06b-3470a27159e7')
var cosmosDataContributorRoleId = '${cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource apiBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(orderPayloads.id, apiApp.id, 'blob')
  scope: orderPayloads
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleId
    principalId: apiApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource apiServiceBusSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(orderQueue.id, apiApp.id, 'sender')
  scope: orderQueue
  properties: {
    roleDefinitionId: serviceBusDataSenderRoleId
    principalId: apiApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerServiceBusReceiverRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(orderQueue.id, worker.id, 'receiver')
  scope: orderQueue
  properties: {
    roleDefinitionId: serviceBusDataReceiverRoleId
    principalId: worker.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource apiEventGridSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopic.id, apiApp.id, 'sender')
  scope: eventGridTopic
  properties: {
    roleDefinitionId: eventGridDataSenderRoleId
    principalId: apiApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource apiKeyVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sqlConnectionSecret.id, apiApp.id, 'secrets')
  scope: sqlConnectionSecret
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleId
    principalId: apiApp.identity.principalId
    principalType: 'ServicePrincipal'
  }

}

resource apiOrderApiKeyVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(orderApiBackendKeySecret.id, apiApp.id, 'secrets')
  scope: orderApiBackendKeySecret
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleId
    principalId: apiApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionStorageBlobOwnerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionStorage.id, functionApp.id, 'blob-owner')
  scope: functionStorage
  properties: {
    roleDefinitionId: storageBlobDataOwnerRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionStorageQueueContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionStorage.id, functionApp.id, 'queue-contributor')
  scope: functionStorage
  properties: {
    roleDefinitionId: storageQueueDataContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionStorageTableContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionStorage.id, functionApp.id, 'table-contributor')
  scope: functionStorage
  properties: {
    roleDefinitionId: storageTableDataContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerAcrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, worker.id, 'acr-pull')
  scope: acr
  properties: {
    roleDefinitionId: acrPullRoleId
    principalId: worker.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource apiCosmosRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  name: guid(cosmos.id, apiApp.id, 'cosmos-data-contributor')
  parent: cosmos
  properties: {
    roleDefinitionId: cosmosDataContributorRoleId
    principalId: apiApp.identity.principalId
    scope: '/dbs/${cosmosDb.name}/colls/${cosmosContainer.name}'
  }
}

output apiManagementGatewayUrl string = apim.properties.gatewayUrl
output appServiceName string = apiApp.name
output functionAppName string = functionApp.name
output containerAppName string = worker.name
output containerRegistryName string = acr.name
output containerRegistryLoginServer string = acr.properties.loginServer
output eventGridTopicId string = eventGridTopic.id
output applicationInsightsName string = appInsights.name
