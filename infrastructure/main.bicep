@description('The Azure Region to deploy the resources into. Default: resourceGroup().location')
param location string = resourceGroup().location

@description('Switch to enable/disable DiagnosticSettings for the resources. Default: false')
param logsEnabled bool = false

@description('A unique string to add as a suffix to all resources. Default: uniqueString(resourceGroup().id)')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 5)

@description('Log Analytics Workspace name. Default: log-spotifyexport-$<uniqueSuffix>')
param logAnalyticsWorkspaceName string = 'log-spotifyexport-${uniqueSuffix}'

@description('Application Insights name. Default: appi-spotifyexport-$<uniqueSuffix>')
param appInsightsName string = 'appi-spotifyexport-${uniqueSuffix}'

@description('Storage Account name. Default: stspotifyexport$<uniqueSuffix>')
param storageAccountName string = 'stspotifyexport${uniqueSuffix}'

@description('App Service Plan name. Default: asp-spotifyexport-$<uniqueSuffix>')
param appServicePlanName string = 'asp-spotifyexport-${uniqueSuffix}'

@description('Function App name. Default: func-spotifyexport-$<uniqueSuffix>')
param functionAppName string = 'func-spotifyexport-${uniqueSuffix}'

@description('Key Vault name. Default: kv-spotifyexport-$<uniqueSuffix>')
param keyVaultName string = 'kv-spotifyexport-${uniqueSuffix}'

@description('Value of the Spotify-ClientID Key Vault secret')
@secure()
param spotifyClientId string

@description('Value of the Spotify-ClientSecret Key Vault secret')
@secure()
param spotifyClientSecret string

@description('Value of the Spotify-RefreshToken Key Vault secret')
@secure()
param spotifyRefreshToken string

// Link Application Insights instance to Function App
var appiLink = {
  'hidden-link:/subscriptions/${subscription().id}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/sites/${functionAppName}': 'Resource'
}

// Default logging policy for all resources
var defaultLogOrMetric = {
  enabled: logsEnabled
  retentionPolicy: {
    days: logsEnabled ? 7 : 0
    enabled: logsEnabled
  }
}

// Resource Group Lock
resource rgLock 'Microsoft.Authorization/locks@2016-09-01' = {
  scope: resourceGroup()
  name: 'DoNotDelete'
  properties: {
    level: 'CanNotDelete'
    notes: 'This lock prevents the accidental deletion of resources'
  }
}

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
  name: guid(func.id, st.id, storageBlobContributorRole.id)
  scope: st
  properties: {
    roleDefinitionId: storageBlobContributorRole.id
    principalId: func.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Allows Function App Managed Identity to use Key Vault Secrets')
resource funcMIVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(func.id, kv.id, keyVaultSecretsUserRole.id)
  scope: kv
  properties: {
    roleDefinitionId: keyVaultSecretsUserRole.id
    principalId: func.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Log Analytics Workspace
resource log 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource logAnalyticsWorkspaceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'All Logs and Metrics'
  scope: log
  properties: {
    logs: [ union({ categoryGroup: 'allLogs' }, defaultLogOrMetric) ]
    metrics: [ union({ categoryGroup: 'allMetrics' }, defaultLogOrMetric) ]
    workspaceId: log.id
  }
}

// Application Insights
resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
  tags: appiLink
}

// Storage Account
resource st 'Microsoft.Storage/storageAccounts@2022-05-01' = {
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

}

resource stBlob 'Microsoft.Storage/storageAccounts/blobServices@2022-05-01' existing = {
  name: 'default'
  parent: st
}

resource stDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'All Logs and Metrics'
  scope: st
  properties: {
    metrics: [ union({ categoryGroup: 'allMetrics' }, defaultLogOrMetric) ]
    workspaceId: log.id
  }
}

resource stBlobDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'All Logs and Metrics'
  scope: stBlob
  properties: {
    logs: [ union({ categoryGroup: 'allLogs' }, defaultLogOrMetric) ]
    metrics: [ union({ categoryGroup: 'allMetrics' }, defaultLogOrMetric) ]
    workspaceId: log.id
  }
}

// App Service Plan
resource asp 'Microsoft.Web/serverfarms@2022-03-01' = {
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

resource aspDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'All Logs and Metrics'
  scope: asp
  properties: {
    metrics: [ union({ category: 'AllMetrics' }, defaultLogOrMetric) ]
    workspaceId: log.id
  }
}

// Function App
resource func 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    httpsOnly: true
    reserved: true
    serverFarmId: asp.id
    keyVaultReferenceIdentity: 'SystemAssigned'
    siteConfig: {
      linuxFxVersion: 'POWERSHELL|7.2'
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appi.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appi.properties.ConnectionString
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${st.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(st.id, st.apiVersion).keys[0].value}'
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
          name: 'PLAYLIST_TYPE'
          value: 'User'
        }
        {
          name: 'SPOTIFY_CLIENT_ID'
          value: '@Microsoft.KeyVault(VaultName=${kv.name};SecretName=Spotify-ClientID)'
        }
        {
          name: 'SPOTIFY_CLIENT_SECRET'
          value: '@Microsoft.KeyVault(VaultName=${kv.name};SecretName=Spotify-ClientSecret)'
        }
        {
          name: 'SPOTIFY_REFRESH_TOKEN'
          value: '@Microsoft.KeyVault(VaultName=${kv.name};SecretName=Spotify-RefreshToken)'
        }
      ]
      alwaysOn: false
    }
  }
}

resource funcDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'All Logs and Metrics'
  scope: func
  properties: {
    logs: [ union({ categoryGroup: 'allLogs' }, defaultLogOrMetric) ]
    metrics: [ union({ category: 'AllMetrics' }, defaultLogOrMetric) ]
    workspaceId: log.id
  }
}

// Key Vault
resource kv 'Microsoft.KeyVault/vaults@2022-07-01' = {
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
}

resource kvDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'All Logs and Metrics'
  scope: kv
  properties: {
    logs: [ union({ categoryGroup: 'allLogs' }, defaultLogOrMetric) ]
    metrics: [ union({ category: 'AllMetrics' }, defaultLogOrMetric) ]
    workspaceId: log.id
  }
}

// Key Vault secrets
resource kvSecretClientId 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  name: '${kv.name}/Spotify-ClientId'
  properties: {
    value: spotifyClientId
  }
}

resource kvSecretClientSecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  name: '${kv.name}/Spotify-ClientSecret'
  properties: {
    value: spotifyClientSecret
  }
}

resource kvSecretRefreshToken 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  name: '${kv.name}/Spotify-RefreshToken'
  properties: {
    value: spotifyRefreshToken
  }
}
