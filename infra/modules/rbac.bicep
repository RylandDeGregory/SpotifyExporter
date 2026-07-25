@description('Name of the Cosmos DB Account to grant data access on. Empty when Cosmos is disabled.')
param cosmosAccountName string = ''

@description('Switch to enable/disable the Cosmos DB data plane role assignment.')
param cosmosEnabled bool

@description('Principal ID of the Function App system-assigned managed identity.')
param functionAppPrincipalId string

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2026-03-15' existing = if (cosmosEnabled) {
  name: cosmosAccountName
}

// Built-in Azure RBAC Roles
//See https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
var roles = [
  {
    name: 'Key Vault Secrets User'
    roleId: '4633458b-17de-408a-b874-0445c86b69e6'
  }
  {
    name: 'Monitoring Metrics Publisher'
    roleId: '3913510d-42f4-4e42-8a64-420c390055eb'
  }
  {
    name: 'Storage Blob Data Contributor'
    roleId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  }
  {
    // Required for identity-based AzureWebJobsStorage
    name: 'Storage Queue Data Contributor'
    roleId: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  }
  {
    // Required for identity-based AzureWebJobsStorage
    name: 'Storage Table Data Contributor'
    roleId: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa9'
  }
]

resource roleDefinitions 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = [
  for role in roles: {
    scope: subscription()
    name: role.roleId
  }
]

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for (role, i) in roles: {
    name: guid(functionAppPrincipalId, resourceGroup().id, role.roleId)
    scope: resourceGroup()
    properties: {
      roleDefinitionId: roleDefinitions[i].id
      principalId: functionAppPrincipalId
      principalType: 'ServicePrincipal'
    }
  }
]

// Cosmos DB uses its own data-plane RBAC system rather than Azure RBAC
// See: https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-connect-role-based-access-control
resource cosmosSqlRbacRoleDefinition 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2026-03-15' existing = if (cosmosEnabled) {
  parent: cosmosAccount
  name: '00000000-0000-0000-0000-000000000002' // Cosmos DB Built-in Data Contributor
}

resource cosmosSqlRbacRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2026-03-15' = if (cosmosEnabled) {
  parent: cosmosAccount
  name: guid(functionAppPrincipalId, cosmosAccount.id, cosmosSqlRbacRoleDefinition.id)
  properties: {
    principalId: functionAppPrincipalId
    roleDefinitionId: cosmosSqlRbacRoleDefinition.id
    scope: cosmosAccount.id
  }
}
