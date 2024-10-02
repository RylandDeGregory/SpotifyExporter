@description('The Azure Region to deploy the resources into. Default: resourceGroup().location')
param location string = resourceGroup().location

@description('Switch to enable/disable DiagnosticSettings for the resources. Default: false')
param logsEnabled bool = false

@description('Switch to enable/disable provisioning and exporting to a Cosmos DB NoSQL Account. Default: false')
param cosmosEnabled bool = false

@description('Switch to enable/disable exporting CSVs to Azure Blob Storage. Default: true')
param storageExportEnabled bool = true

@description('A unique string to add as a suffix to all resources. Default: substring(uniqueString(resourceGroup().id), 0, 5)')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 5)

@description('Log Analytics Workspace name. Default: log-spotifyexp-$<uniqueSuffix>')
param logAnalyticsWorkspaceName string = 'log-spotifyexp-${uniqueSuffix}'

@description('Application Insights name. Default: appi-spotifyexp-$<uniqueSuffix>')
param appInsightsName string = 'appi-spotifyexp-${uniqueSuffix}'

@description('Storage Account name. Default: stspotifyexp$<uniqueSuffix>')
param storageAccountName string = 'stspotifyexp${replace(uniqueSuffix, '-', '')}'

@description('App Service Plan name. Default: asp-spotifyexp-$<uniqueSuffix>')
param appServicePlanName string = 'asp-spotifyexp-${uniqueSuffix}'

@description('Function App name. Default: func-spotifyexp-$<uniqueSuffix>')
param functionAppName string = 'func-spotifyexp-${uniqueSuffix}'

@description('Cosmos DB Account name. Default: cosno-spotifyexp-$<uniqueSuffix>')
param cosmosAccountName string = 'cosno-spotifyexp-${uniqueSuffix}'

@description('Key Vault name. Default: kv-spotifyexp-$<uniqueSuffix>')
param keyVaultName string = 'kv-spotifyexp-${uniqueSuffix}'

@description('Value of the Spotify-ClientID Key Vault secret')
@secure()
param spotifyClientId string

@description('Value of the Spotify-ClientSecret Key Vault secret')
@secure()
param spotifyClientSecret string

@description('Value of the Spotify-RefreshToken Key Vault secret')
@secure()
param spotifyRefreshToken string


// Default Cosmos DB containers
var cosmosContainerNames = [
  'Following'
  'Library'
  'Playlist'
  'RecentlyPlayed'
]


// RBAC Role definitions
@description('Built-in Storage Blob Data Contributor role. See https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-blob-data-contributor')
resource storageBlobContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
}

@description('Built-in Key Vault Secrets User role. See https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#key-vault-secrets-user')
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '4633458b-17de-408a-b874-0445c86b69e6'
}

// RBAC Role assignments
@description('Allows Function App Managed Identity to write to Storage Account')
resource funcMIBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, storageAccount.id, storageBlobContributorRole.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobContributorRole.id
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Allows Function App Managed Identity to use Key Vault Secrets')
resource funcMIVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, keyVault.id, keyVaultSecretsUserRole.id)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRole.id
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Resource Group Lock
resource rgLock 'Microsoft.Authorization/locks@2020-05-01' = {
  scope: resourceGroup()
  name: 'DoNotDelete'
  properties: {
    level: 'CanNotDelete'
    notes: 'This lock prevents the accidental deletion of resources'
  }
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource logAnalyticsWorkspaceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: logAnalyticsWorkspace
  properties: {
    logs: [{
      categoryGroup: 'allLogs'
      enabled: true
    }]
    metrics: [{
      category: 'allMetrics'
      enabled: true
    }]
    workspaceId: logAnalyticsWorkspace.id
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
  // Link Application Insights instance to Function App
  tags: {
    'hidden-link:${resourceId('Microsoft.Web/sites', functionAppName)}': 'Resource'
  }
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    allowBlobPublicAccess: false
  }

  resource blobService 'blobServices' existing = {
    name: 'default'
  }
}

resource blobServiceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: storageAccount::blobService
  properties: {
    logs: [{
      categoryGroup: 'allLogs'
      enabled: true
    }]
    metrics: [{
      category: 'Transaction'
      enabled: true
    }]
    workspaceId: logAnalyticsWorkspace.id
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  properties: {
    reserved: true
  }
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
}

resource aspDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: appServicePlan
  properties: {
    metrics: [{
      category: 'AllMetrics'
      enabled: true
    }]
    workspaceId: logAnalyticsWorkspace.id
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    httpsOnly: true
    reserved: true
    serverFarmId: appServicePlan.id
    keyVaultReferenceIdentity: 'SystemAssigned'
    siteConfig: {
      linuxFxVersion: 'POWERSHELL|7.4'
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'AzureWebJobsStorage'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=StorageAccount-ConnectionString)'
        }
        {
          name: 'COSMOS_CONNECTION_STRING'
          value: cosmosEnabled ? '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=CosmosDB-ConnectionString)' : 'null'
        }
        {
          name: 'COSMOS_ENABLED'
          value: '${cosmosEnabled}'
        }
        {
          name: 'STORAGE_ENABLED'
          value: '${storageExportEnabled}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: 'https://github.com/RylandDeGregory/SpotifyExporter/blob/master/src.zip?raw=true'
        }
        {
          name: 'PLAYLIST_TYPE'
          value: 'User'
        }
        {
          name: 'SPOTIFY_CLIENT_ID'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=Spotify-ClientID)'
        }
        {
          name: 'SPOTIFY_CLIENT_SECRET'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=Spotify-ClientSecret)'
        }
        {
          name: 'SPOTIFY_REFRESH_TOKEN'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=Spotify-RefreshToken)'
        }
      ]
      alwaysOn: false
    }
  }
}

resource funcDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: functionApp
  properties: {
    logs: [{
      categoryGroup: 'allLogs'
      enabled: true
    }]
    metrics: [{
      category: 'AllMetrics'
      enabled: true
    }]
    workspaceId: logAnalyticsWorkspace.id
  }
}

// Cosmos DB (NoSQL API)
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = if (cosmosEnabled) {
  name: toLower(cosmosAccountName)
  location: location
  properties: {
    enableFreeTier: true
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
      }
    ]
  }

  resource cosmosDatabase 'sqlDatabases' = {
    name: 'cosmos-spotifyexport'
    properties: {
      resource: {
        id: 'cosmos-spotifyexport'
      }
      options: {
        throughput: 1000
      }
    }

    resource cosmosContainers 'containers' = [for containerName in cosmosContainerNames: {
      name: containerName
      properties: {
        resource: {
          id: containerName
          partitionKey: {
            paths: [
              '/id'
            ]
            kind: 'Hash'
          }
          indexingPolicy: {
            indexingMode: 'consistent'
            automatic: true
            includedPaths: [
              {
                path: '/*'
              }
            ]
            excludedPaths: [
              {
                path: '/_etag/?'
              }
            ]
          }
        }
      }
    }]
  }
}

resource cosmosDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (cosmosEnabled && logsEnabled) {
  name: 'All Logs and Metrics'
  scope: cosmosAccount
  properties: {
    logs: [{
      categoryGroup: 'allLogs'
      enabled: true
    }]
    metrics: [{
      category: 'AllMetrics'
      enabled: true
    }]
    workspaceId: logAnalyticsWorkspace.id
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    publicNetworkAccess: 'Enabled'
    softDeleteRetentionInDays: 30
    tenantId: tenant().tenantId
  }

  resource kvSecretClientId 'secrets' = {
    name: 'Spotify-ClientId'
    properties: {
      value: spotifyClientId
    }
  }
  resource kvSecretClientSecret 'secrets' = {
    name: 'Spotify-ClientSecret'
    properties: {
      value: spotifyClientSecret
    }
  }
  resource kvSecretRefreshToken 'secrets' = {
    name: 'Spotify-RefreshToken'
    properties: {
      value: spotifyRefreshToken
    }
  }
  resource kvSecretCosmosCS 'secrets' = if (cosmosEnabled) {
    name: 'CosmosDB-ConnectionString'
    properties: {
      value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
    }
  }
  resource kvSecretStorageCS 'secrets' = {
    name: 'StorageAccount-ConnectionString'
    properties: {
      value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    }
  }
}

resource kvDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: keyVault
  properties: {
    logs: [{
      categoryGroup: 'allLogs'
      enabled: true
    }]
    metrics: [{
      category: 'AllMetrics'
      enabled: true
    }]
    workspaceId: logAnalyticsWorkspace.id
  }
}
