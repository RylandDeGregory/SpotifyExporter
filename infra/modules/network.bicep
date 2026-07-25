@description('Name of the Container Apps infrastructure subnet.')
param containerAppSubnetName string

@description('Address space for the Container Apps infrastructure subnet. Must be /27 or larger.')
param containerAppSubnetPrefix string

@description('The Azure Region to deploy the resources into.')
param location string

@description('Virtual Network name.')
param virtualNetworkName string

@description('Address space for the Virtual Network.')
param virtualNetworkAddressPrefix string

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2025-07-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefix
      ]
    }
    subnets: [
      {
        name: containerAppSubnetName
        properties: {
          addressPrefix: containerAppSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
              locations: [
                location
              ]
            }
            {
              service: 'Microsoft.AzureCosmosDB'
              locations: [
                location
              ]
            }
            {
              service: 'Microsoft.KeyVault'
              locations: [
                location
              ]
            }
          ]
        }
      }
    ]
  }

  resource containerAppSubnet 'subnets' existing = {
    name: containerAppSubnetName
  }
}

output virtualNetworkId string = virtualNetwork.id
output virtualNetworkName string = virtualNetwork.name
output containerAppSubnetId string = virtualNetwork::containerAppSubnet.id
