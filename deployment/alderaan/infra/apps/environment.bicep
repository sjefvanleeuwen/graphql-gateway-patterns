// ============================================================================
// Container Apps Environment Module
// ============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param resourceToken string
param abbrs object

param acaSubnetId string
param logAnalyticsCustomerId string
@secure()
param logAnalyticsSharedKey string

@description('Whether the environment is zone-redundant')
param zoneRedundant bool = false

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${abbrs.appManagedEnvironments}${resourceToken}'
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: acaSubnetId
      internal: false
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
    zoneRedundant: zoneRedundant
  }
}

output environmentId string = environment.id
output environmentName string = environment.name
output defaultDomain string = environment.properties.defaultDomain
output staticIp string = environment.properties.staticIp
