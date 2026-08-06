@description('The Azure Region to deploy the resources into.')
param location string

@description('Address prefix of the subnet delegated to Flex Consumption.')
param subnetAddressPrefix string

@description('Name of the subnet delegated to Flex Consumption.')
param subnetName string

@description('Address prefix of the virtual network used by the Function App.')
param virtualNetworkAddressPrefix string

@description('Name of the virtual network used by the Function App.')
param virtualNetworkName string

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefix
      ]
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  name: subnetName
  parent: virtualNetwork
  properties: {
    addressPrefix: subnetAddressPrefix
    delegations: [
      {
        name: 'flex-consumption'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
    serviceEndpoints: [
      {
        service: 'Microsoft.KeyVault'
      }
      {
        service: 'Microsoft.Storage'
      }
    ]
  }
}

output subnetId string = subnet.id
