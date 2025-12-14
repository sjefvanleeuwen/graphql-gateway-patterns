targetScope = 'subscription'

@description('Resource group name to create')
param resourceGroupName string

@description('Azure region for all resources')
param location string

@description('VNet address prefix (CIDR). Example: 10.210.0.0/16')
param vnetAddressPrefix string

@description('ACA infrastructure subnet address prefix (CIDR). Must be at least /23. Example: 10.210.0.0/23')
param acaInfrastructureSubnetPrefix string

@description('PostgreSQL delegated subnet address prefix (CIDR). Example: 10.210.2.0/24')
param postgresSubnetPrefix string

@description('PostgreSQL admin username')
param postgresAdminUsername string = 'postgres'

@secure()
@description('PostgreSQL admin password')
param postgresAdminPassword string

@description('PostgreSQL server version')
@allowed([
  '14'
  '15'
  '16'
])
param postgresVersion string = '15'

@description('ACR SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Basic'

@description('Whether to enable ACR admin user')
param acrAdminUserEnabled bool = true

var tags = {
  deployment: 'alderaan'
  theme: 'starwars'
  codename: 'alderaan'
  // Useful if you later decide to use azd tooling
  'azd-env-name': 'alderaan'
}

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module core 'resources.bicep' = {
  name: 'core'
  scope: rg
  params: {
    location: location
    tags: tags
    vnetAddressPrefix: vnetAddressPrefix
    acaInfrastructureSubnetPrefix: acaInfrastructureSubnetPrefix
    postgresSubnetPrefix: postgresSubnetPrefix
    acrSku: acrSku
    acrAdminUserEnabled: acrAdminUserEnabled
    postgresAdminUsername: postgresAdminUsername
    postgresAdminPassword: postgresAdminPassword
    postgresVersion: postgresVersion
  }
}

output RESOURCE_GROUP_NAME string = rg.name
output ACR_NAME string = core.outputs.ACR_NAME
output ACR_LOGIN_SERVER string = core.outputs.ACR_LOGIN_SERVER
output CONTAINERAPPS_ENVIRONMENT_NAME string = core.outputs.CONTAINERAPPS_ENVIRONMENT_NAME
output VNET_NAME string = core.outputs.VNET_NAME
output ACA_SUBNET_NAME string = core.outputs.ACA_SUBNET_NAME
output ACA_SUBNET_ID string = core.outputs.ACA_SUBNET_ID

output LOG_ANALYTICS_WORKSPACE_NAME string = core.outputs.LOG_ANALYTICS_WORKSPACE_NAME
output APPLICATIONINSIGHTS_NAME string = core.outputs.APPLICATIONINSIGHTS_NAME
output APPLICATIONINSIGHTS_CONNECTION_STRING string = core.outputs.APPLICATIONINSIGHTS_CONNECTION_STRING

output POSTGRES_SERVER_NAME string = core.outputs.POSTGRES_SERVER_NAME
output POSTGRES_FQDN string = core.outputs.POSTGRES_FQDN
output POSTGRES_DATABASE_NAME string = core.outputs.POSTGRES_DATABASE_NAME
