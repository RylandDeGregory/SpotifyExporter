@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Flex Consumption plan name.')
param appServicePlanName string

@description('Document (SQL) endpoint of the Cosmos DB Account. Empty when Cosmos is disabled.')
param cosmosDocumentEndpoint string

@description('Switch to enable/disable exporting to a Cosmos DB NoSQL Account.')
param cosmosEnabled bool

@description('Blob container URL used by Flex Consumption One Deploy.')
param deploymentStorageContainerUrl string

@description('Function App name.')
param functionAppName string

@description('Memory allocated to each Flex Consumption instance in MB.')
@allowed([512, 1024, 2048, 4096])
param instanceMemoryMB int = 512

@description('URI of the Key Vault holding the Spotify secrets.')
param keyVaultUri string

@description('The Azure Region to deploy the resources into.')
param location string

@description('Function App managed identity name.')
param managedIdentityName string

@description('Maximum Flex Consumption scale-out instance count.')
@minValue(1)
@maxValue(1000)
param maximumInstanceCount int = 5

@description('Name of the Storage Account used for AzureWebJobsStorage.')
param storageAccountName string

@description('Switch to enable/disable exporting CSVs to Azure Blob Storage.')
param storageExportEnabled bool

@description('Resource ID of the delegated Flex Consumption integration subnet.')
param subnetId string

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    keyVaultReferenceIdentity: managedIdentity.id
    virtualNetworkSubnetId: subnetId
    siteConfig: {
      minTlsVersion: '1.2'
      vnetRouteAllEnabled: true
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: deploymentStorageContainerUrl
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: managedIdentity.id
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
      }
      runtime: {
        name: 'powershell'
        version: '7.6'
      }
    }
  }

  resource appSettings 'config' = {
    name: 'appsettings'
    properties: {
      APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${managedIdentity.properties.clientId};Authorization=AAD'
      APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsConnectionString
      AzureWebJobsStorage__accountName: storageAccountName
      AzureWebJobsStorage__clientId: managedIdentity.properties.clientId
      AzureWebJobsStorage__credential: 'managedidentity'
      COSMOS_CONNECTION_STRING__accountEndpoint: cosmosEnabled ? cosmosDocumentEndpoint : ''
      COSMOS_CONNECTION_STRING__clientId: managedIdentity.properties.clientId
      COSMOS_CONNECTION_STRING__credential: 'managedidentity'
      COSMOS_ENABLED: '${cosmosEnabled}'
      FUNCTIONS_EXTENSION_VERSION: '~4'
      PLAYLIST_TYPE: 'User'
      SPOTIFY_CLIENT_ID: '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/Spotify-ClientId/)'
      SPOTIFY_CLIENT_SECRET: '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/Spotify-ClientSecret/)'
      SPOTIFY_REFRESH_TOKEN: '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/Spotify-RefreshToken/)'
      STORAGE_ENABLED: '${storageExportEnabled}'
    }
  }

  resource ftpPublishingCredentials 'basicPublishingCredentialsPolicies' = {
    name: 'ftp'
    properties: {
      allow: false
    }
  }

  resource scmPublishingCredentials 'basicPublishingCredentialsPolicies' = {
    name: 'scm'
    properties: {
      allow: false
    }
  }
}

output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output managedIdentityClientId string = managedIdentity.properties.clientId
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
