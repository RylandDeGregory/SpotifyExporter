@description('GitHub branch authorized to deploy the Function App.')
param githubBranch string

@description('GitHub organization or account that owns the repository.')
param githubOwner string

@description('GitHub repository authorized to deploy the Function App.')
param githubRepository string

@description('The Azure Region to deploy the resources into.')
param location string

var githubSubject = 'repo:${githubOwner}/${githubRepository}:ref:refs/heads/${githubBranch}'
var contributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
var rbacAdministratorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f58310d9-a9f6-439a-9e8d-f62e7b41a168')

resource deploymentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'mi-github-spotifyexport'
  location: location

  resource githubCredential 'federatedIdentityCredentials' = {
    name: 'github-${githubBranch}'
    properties: {
      audiences: [
        'api://AzureADTokenExchange'
      ]
      issuer: 'https://token.actions.githubusercontent.com'
      subject: githubSubject
    }
  }
}

resource infrastructureDeploymentRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(deploymentIdentity.id, resourceGroup().id, contributorRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: contributorRoleId
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource infrastructureRbacRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(deploymentIdentity.id, resourceGroup().id, rbacAdministratorRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: rbacAdministratorRoleId
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output clientId string = deploymentIdentity.properties.clientId
