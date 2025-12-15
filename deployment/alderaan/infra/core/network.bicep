// ============================================================================
// Network Module: VNet, Subnets
// ============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param resourceToken string
param abbrs object

param vnetAddressPrefix string
param acaInfrastructureSubnetPrefix string
param postgresSubnetPrefix string

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${abbrs.networkVirtualNetworks}${resourceToken}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: '${abbrs.networkVirtualNetworksSubnets}aca'
        properties: {
          addressPrefix: acaInfrastructureSubnetPrefix
        }
      }
      {
        name: '${abbrs.networkVirtualNetworksSubnets}postgres'
        properties: {
          addressPrefix: postgresSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.DBforPostgreSQL-flexibleServers'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output acaSubnetId string = vnet.properties.subnets[0].id
output acaSubnetName string = vnet.properties.subnets[0].name
output postgresSubnetId string = vnet.properties.subnets[1].id
output postgresSubnetName string = vnet.properties.subnets[1].name
