// ============================================================================
// SpotifyExporter
// Azure Functions on Azure Container Apps, deployed as a container image from
// GitHub Container Registry. All data access is identity-based.
// ============================================================================

@description('Application Insights name. Default: appi-spotifyexp-$<uniqueSuffix>')
param appInsightsName string = 'appi-spotifyexp-${uniqueSuffix}'

@description('Container Apps Environment name. Default: cae-spotifyexp-$<uniqueSuffix>')
param containerAppEnvName string = 'cae-spotifyexp-${uniqueSuffix}'

@description('Container image published to GitHub Container Registry.')
param containerImage string = 'ghcr.io/rylanddegregory/spotifyexporter:latest'

@description('Cosmos DB Account name. Default: cosno-spotifyexp-$<uniqueSuffix>')
param cosmosAccountName string = 'cosno-spotifyexp-${uniqueSuffix}'

@description('Switch to enable/disable provisioning and exporting to a Cosmos DB NoSQL Account. Default: false')
param cosmosEnabled bool = false

@description('Function App name. Default: func-spotifyexp-$<uniqueSuffix>')
param functionAppName string = 'func-spotifyexp-${uniqueSuffix}'

@description('Key Vault name. Default: kv-spotifyexp-$<uniqueSuffix>')
param keyVaultName string = 'kv-spotifyexp-${uniqueSuffix}'

@description('Switch to enable/disable provisioning of Key Vault Secrets. Default: true')
param keyVaultSecretsEnabled bool = true

@description('The Azure Region to deploy the resources into. Default: resourceGroup().location')
param location string = resourceGroup().location

@description('Log Analytics Workspace name. Default: log-spotifyexp-$<uniqueSuffix>')
param logAnalyticsWorkspaceName string = 'log-spotifyexp-${uniqueSuffix}'

@description('Switch to enable/disable DiagnosticSettings for the resources. Default: false')
param logsEnabled bool = false

@description('Value of the Spotify-ClientID Key Vault secret')
@secure()
param spotifyClientId string

@description('Value of the Spotify-ClientSecret Key Vault secret')
@secure()
param spotifyClientSecret string

@description('Value of the Spotify-RefreshToken Key Vault secret')
@secure()
param spotifyRefreshToken string

@description('Storage Account name. Default: stspotifyexp$<uniqueSuffix>')
param storageAccountName string = 'stspotifyexp${replace(uniqueSuffix, '-', '')}'

@description('Switch to enable/disable exporting CSVs to Azure Blob Storage. Default: true')
param storageExportEnabled bool = true

@description('A unique string to add as a suffix to all resources. Default: substring(uniqueString(resourceGroup().id), 0, 5)')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 5)

var cosmosContainerNames = [
  'Following'
  'Library'
  'Playlist'
  'RecentlyPlayed'
]
var cosmosDatabaseName = 'cosmos-spotifyexport'

// Timer-triggered functions only need a single replica.
var minReplicas = 0
var maxReplicas = 1

// Resource Group Lock
resource rgLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: 'DoNotDelete'
  properties: {
    level: 'CanNotDelete'
    notes: 'This lock prevents the accidental deletion of resources'
  }
  scope: resourceGroup()
}

module compute 'modules/compute.bicep' = {
  name: 'Compute'
  params: {
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    containerAppEnvName: containerAppEnvName
    containerImage: containerImage
    cosmosDocumentEndpoint: cosmosEnabled ? cosmos!.outputs.documentEndpoint : ''
    cosmosEnabled: cosmosEnabled
    functionAppName: functionAppName
    keyVaultUri: keyVault.outputs.keyVaultUri
    location: location
    logAnalyticsCustomerId: monitoring.outputs.logAnalyticsCustomerId
    logAnalyticsSharedKey: monitoring.outputs.logAnalyticsSharedKey
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    logsEnabled: logsEnabled
    maxReplicas: maxReplicas
    minReplicas: minReplicas
    storageAccountName: storage.outputs.storageAccountName
    storageExportEnabled: storageExportEnabled
  }
}

module cosmos 'modules/cosmos.bicep' = if (cosmosEnabled) {
  name: 'Cosmos'
  params: {
    containerNames: cosmosContainerNames
    databaseName: cosmosDatabaseName
    cosmosAccountName: cosmosAccountName
    location: location
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    logsEnabled: logsEnabled
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'KeyVault'
  params: {
    keyVaultName: keyVaultName
    keyVaultSecretsEnabled: keyVaultSecretsEnabled
    location: location
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    logsEnabled: logsEnabled
    spotifyClientId: spotifyClientId
    spotifyClientSecret: spotifyClientSecret
    spotifyRefreshToken: spotifyRefreshToken
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'Monitoring'
  params: {
    appInsightsName: appInsightsName
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    logsEnabled: logsEnabled
  }
}

module rbac 'modules/rbac.bicep' = {
  name: 'RBAC'
  params: {
    cosmosAccountName: cosmosEnabled ? cosmos!.outputs.cosmosAccountName : ''
    cosmosEnabled: cosmosEnabled
    functionAppPrincipalId: compute.outputs.functionAppPrincipalId
  }
}

module storage 'modules/storage.bicep' = {
  name: 'Storage'
  params: {
    location: location
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    logsEnabled: logsEnabled
    storageAccountName: storageAccountName
  }
}
