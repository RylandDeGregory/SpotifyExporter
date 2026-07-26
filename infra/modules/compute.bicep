@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Container Apps Environment name.')
param containerAppEnvName string

@description('Container image published to GitHub Container Registry.')
param containerImage string

@description('Document (SQL) endpoint of the Cosmos DB Account. Empty when Cosmos is disabled.')
param cosmosDocumentEndpoint string

@description('Switch to enable/disable exporting to a Cosmos DB NoSQL Account.')
param cosmosEnabled bool

@description('Function App name.')
param functionAppName string

@description('URI of the Key Vault holding the Spotify secrets.')
param keyVaultUri string

@description('The Azure Region to deploy the resources into.')
param location string

@description('Customer ID (workspace GUID) of the Log Analytics Workspace.')
param logAnalyticsCustomerId string

@description('Primary shared key of the Log Analytics Workspace.')
@secure()
param logAnalyticsSharedKey string

@description('Resource ID of the Log Analytics Workspace for diagnostics.')
param logAnalyticsWorkspaceId string

@description('Switch to enable/disable DiagnosticSettings for the resources.')
param logsEnabled bool

@description('Maximum number of replicas.')
param maxReplicas int

@description('Minimum number of replicas.')
param minReplicas int

@description('Name of the Storage Account used for AzureWebJobsStorage.')
param storageAccountName string

@description('Switch to enable/disable exporting CSVs to Azure Blob Storage.')
param storageExportEnabled bool

resource containerAppEnv 'Microsoft.App/managedEnvironments@2026-01-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    zoneRedundant: false
  }
}

resource caeDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logsEnabled) {
  name: 'All Logs and Metrics'
  scope: containerAppEnv
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

resource functionApp 'Microsoft.App/containerApps@2026-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: containerAppEnv.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      // Ingress must be enabled for event-driven scaling, but it can be internal
      // as all functions are timer-triggered.
      ingress: {
        external: false
        targetPort: 80
        allowInsecure: false
        transport: 'auto'
      }
      secrets: [
        {
          name: 'spotify-client-id'
          keyVaultUrl: '${keyVaultUri}secrets/Spotify-ClientId'
          identity: 'system'
        }
        {
          name: 'spotify-client-secret'
          keyVaultUrl: '${keyVaultUri}secrets/Spotify-ClientSecret'
          identity: 'system'
        }
        {
          name: 'spotify-refresh-token'
          keyVaultUrl: '${keyVaultUri}secrets/Spotify-RefreshToken'
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'spotifyexporter'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'APPLICATIONINSIGHTS_AUTHENTICATION_STRING'
              value: 'Authorization=AAD'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsightsConnectionString
            }
            {
              name: 'AzureWebJobsStorage__accountName'
              value: storageAccountName
            }
            {
              name: 'AzureWebJobsStorage__credential'
              value: 'managedidentity'
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
              name: 'COSMOS_CONNECTION_STRING__accountEndpoint'
              value: cosmosEnabled ? cosmosDocumentEndpoint : ''
            }
            {
              name: 'COSMOS_CONNECTION_STRING__credential'
              value: 'managedidentity'
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
              name: 'PLAYLIST_TYPE'
              value: 'User'
            }
            {
              name: 'SPOTIFY_CLIENT_ID'
              secretRef: 'spotify-client-id'
            }
            {
              name: 'SPOTIFY_CLIENT_SECRET'
              secretRef: 'spotify-client-secret'
            }
            {
              name: 'SPOTIFY_REFRESH_TOKEN'
              secretRef: 'spotify-refresh-token'
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output functionAppPrincipalId string = functionApp.identity.principalId
