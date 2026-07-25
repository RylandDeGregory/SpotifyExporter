@description('Resource ID of the subnet allowed to reach the Cosmos DB Account.')
param allowedSubnetId string

@description('Names of the Cosmos DB containers to create.')
param containerNames array

@description('Cosmos DB Account name.')
param cosmosAccountName string

@description('Name of the Cosmos DB SQL database.')
param databaseName string

@description('The Azure Region to deploy the resources into.')
param location string

@description('Resource ID of the Log Analytics Workspace for diagnostics.')
param logAnalyticsWorkspaceId string

@description('Switch to enable/disable DiagnosticSettings for the resources.')
param logsEnabled bool

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2026-03-15' = {
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
    disableLocalAuth: true
    isVirtualNetworkFilterEnabled: true
    virtualNetworkRules: [
      {
        id: allowedSubnetId
        ignoreMissingVNetServiceEndpoint: false
      }
    ]
  }

  resource cosmosDatabase 'sqlDatabases' = {
    name: databaseName
    properties: {
      resource: {
        id: databaseName
      }
    }

    resource cosmosContainers 'containers' = [
      for containerName in containerNames: {
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
      }
    ]
  }
}

resource cosmosDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: cosmosAccount
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

output cosmosAccountId string = cosmosAccount.id
output cosmosAccountName string = cosmosAccount.name
output documentEndpoint string = cosmosAccount.properties.documentEndpoint
