@description('The Azure Region to deploy the resources into.')
param location string

@description('Resource ID of the Log Analytics Workspace for diagnostics.')
param logAnalyticsWorkspaceId string

@description('Switch to enable/disable DiagnosticSettings for the resources.')
param logsEnabled bool

@description('Storage Account name.')
param storageAccountName string

resource storageAccount 'Microsoft.Storage/storageAccounts@2026-04-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }

  resource blobService 'blobServices' existing = {
    name: 'default'
  }
}

resource blobServiceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: storageAccount::blobService
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
    workspaceId: logAnalyticsWorkspaceId
  }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
