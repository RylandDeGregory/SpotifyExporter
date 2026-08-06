// SpotifyExporter on Azure Functions Flex Consumption.

@description('Application Insights name. Default: appi-spotifyexp-$<uniqueSuffix>')
param appInsightsName string = 'appi-spotifyexp-${uniqueSuffix}'

@description('Cosmos DB Account name. Default: cosno-spotifyexp-$<uniqueSuffix>')
param cosmosAccountName string = 'cosno-spotifyexp-${uniqueSuffix}'

@description('Switch to enable/disable provisioning and exporting to a Cosmos DB NoSQL Account. Default: false')
param cosmosEnabled bool = false

@description('Function App name. Default: func-spotifyexp-$<uniqueSuffix>')
param functionAppName string = 'func-spotifyexp-${uniqueSuffix}'

@description('Function App managed identity name. Default: mi-spotifyexp-$<uniqueSuffix>')
param functionAppManagedIdentityName string = 'mi-spotifyexp-${uniqueSuffix}'

@description('Flex Consumption App Service Plan name. Default: asp-spotifyexp-$<uniqueSuffix>')
param appServicePlanName string = 'asp-spotifyexp-${uniqueSuffix}'

@description('Flex Consumption integration subnet address prefix.')
param functionSubnetAddressPrefix string = '10.0.0.0/27'

@description('Flex Consumption integration subnet name. Default: snet-functionAppVirtualNetworkIntegration')
param functionSubnetName string = 'snet-functionAppVirtualNetworkIntegration'

@description('GitHub branch authorized to deploy the Function App.')
param githubBranch string

@description('GitHub organization or account that owns the repository.')
param githubOwner string

@description('GitHub repository authorized to deploy the Function App.')
param githubRepository string

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
param spotifyClientId string = ''

@description('Value of the Spotify-ClientSecret Key Vault secret')
@secure()
param spotifyClientSecret string = ''

@description('Value of the Spotify-RefreshToken Key Vault secret')
@secure()
param spotifyRefreshToken string = ''

@description('Storage Account name. Default: stspotifyexp$<uniqueSuffix>')
param storageAccountName string = 'stspotifyexp${replace(uniqueSuffix, '-', '')}'

@description('Switch to enable/disable exporting CSVs to Azure Blob Storage. Default: true')
param storageExportEnabled bool = true

@description('A unique string to add as a suffix to all resources. Default: substring(uniqueString(resourceGroup().id), 0, 5)')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 5)

@description('Virtual network name. Default: vnet-spotifyexp-$<uniqueSuffix>')
param virtualNetworkName string = 'vnet-spotifyexp-${uniqueSuffix}'

@description('Virtual network address prefix.')
param virtualNetworkAddressPrefix string = '10.0.0.0/24'

var cosmosContainerNames = [
  'Following'
  'Library'
  'Playlist'
  'RecentlyPlayed'
]
var cosmosDatabaseName = 'cosmos-spotifyexport'

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
    cosmosDocumentEndpoint: cosmosEnabled ? cosmos!.outputs.documentEndpoint : ''
    cosmosEnabled: cosmosEnabled
    deploymentStorageContainerUrl: storage.outputs.deploymentStorageContainerUrl
    functionAppName: functionAppName
    managedIdentityName: functionAppManagedIdentityName
    keyVaultUri: keyVault.outputs.keyVaultUri
    location: location
    appServicePlanName: appServicePlanName
    storageAccountName: storage.outputs.storageAccountName
    storageExportEnabled: storageExportEnabled
    subnetId: network.outputs.subnetId
  }
}

module cicd 'modules/cicd.bicep' = {
  name: 'CICD'
  params: {
    githubBranch: githubBranch
    githubOwner: githubOwner
    githubRepository: githubRepository
    location: location
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
    subnetId: network.outputs.subnetId
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

module network 'modules/network.bicep' = {
  name: 'Network'
  params: {
    location: location
    subnetAddressPrefix: functionSubnetAddressPrefix
    subnetName: functionSubnetName
    virtualNetworkAddressPrefix: virtualNetworkAddressPrefix
    virtualNetworkName: virtualNetworkName
  }
}

module rbac 'modules/rbac.bicep' = {
  name: 'RBAC'
  params: {
    cosmosAccountName: cosmosEnabled ? cosmos!.outputs.cosmosAccountName : ''
    cosmosEnabled: cosmosEnabled
    functionAppPrincipalId: compute.outputs.managedIdentityPrincipalId
  }
}

module storage 'modules/storage.bicep' = {
  name: 'Storage'
  params: {
    location: location
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    logsEnabled: logsEnabled
    storageAccountName: storageAccountName
    subnetId: network.outputs.subnetId
  }
}

output githubActionsClientId string = cicd.outputs.clientId
output tenantId string = tenant().tenantId
