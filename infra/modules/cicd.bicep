@description('GitHub branch authorized to deploy the Function App.')
param githubBranch string

@description('GitHub organization or account that owns the repository.')
param githubOwner string

@description('GitHub repository authorized to deploy the Function App.')
param githubRepository string

@description('The Azure Region to deploy the resources into.')
param location string

var githubSubject = 'repo:${githubOwner}/${githubRepository}:ref:refs/heads/${githubBranch}'
var ownerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8e3af657-a8ff-443c-a75c-2fe8c4bcb635')

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
  name: guid(deploymentIdentity.id, resourceGroup().id, ownerRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: ownerRoleId
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output clientId string = deploymentIdentity.properties.clientId
