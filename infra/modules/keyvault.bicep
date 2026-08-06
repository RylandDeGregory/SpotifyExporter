@description('Key Vault name.')
param keyVaultName string

@description('Switch to enable/disable provisioning of Key Vault Secrets.')
param keyVaultSecretsEnabled bool

@description('The Azure Region to deploy the resources into.')
param location string

@description('Resource ID of the Log Analytics Workspace for diagnostics.')
param logAnalyticsWorkspaceId string

@description('Switch to enable/disable DiagnosticSettings for the resources.')
param logsEnabled bool

@description('Value of the Spotify-ClientID Key Vault secret')
@secure()
param spotifyClientId string

@description('Value of the Spotify-ClientSecret Key Vault secret')
@secure()
param spotifyClientSecret string

@description('Value of the Spotify-RefreshToken Key Vault secret')
@secure()
param spotifyRefreshToken string

@description('Resource ID of the Function App integration subnet allowed through the Key Vault firewall.')
param subnetId string

resource keyVault 'Microsoft.KeyVault/vaults@2026-02-01' = {
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
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: subnetId
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
  }

  resource kvSecretClientId 'secrets' = if (keyVaultSecretsEnabled) {
    name: 'Spotify-ClientId'
    properties: {
      value: spotifyClientId
    }
  }
  resource kvSecretClientSecret 'secrets' = if (keyVaultSecretsEnabled) {
    name: 'Spotify-ClientSecret'
    properties: {
      value: spotifyClientSecret
    }
  }
  resource kvSecretRefreshToken 'secrets' = if (keyVaultSecretsEnabled) {
    name: 'Spotify-RefreshToken'
    properties: {
      value: spotifyRefreshToken
    }
  }
}

resource kvDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: keyVault
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    workspaceId: logAnalyticsWorkspaceId
  }
}

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
