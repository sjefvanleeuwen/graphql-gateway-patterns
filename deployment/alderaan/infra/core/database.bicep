// ============================================================================
// Database Module: PostgreSQL Flexible Server + Private DNS
// ============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param resourceToken string
param abbrs object

param vnetId string
param postgresSubnetId string
param adminUsername string
@secure()
param adminPassword string

@allowed(['14', '15', '16'])
param version string = '15'

param databaseName string = 'orders'

@description('PostgreSQL SKU name')
param skuName string = 'Standard_B1ms'

@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param skuTier string = 'Burstable'

param storageSizeGB int = 32

// Private DNS zone for Postgres
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'private.postgres.database.azure.com'
  location: 'global'
  tags: tags
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${abbrs.networkPrivateDnsZoneVirtualNetworkLink}${resourceToken}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnetId }
  }
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: '${abbrs.dBforPostgreSQLFlexibleServers}${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    administratorLogin: adminUsername
    administratorLoginPassword: adminPassword
    version: version
    storage: { storageSizeGB: storageSizeGB }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: { mode: 'Disabled' }
    network: {
      delegatedSubnetResourceId: postgresSubnetId
      privateDnsZoneArmResourceId: privateDnsZone.id
    }
  }
  dependsOn: [privateDnsZoneLink]
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  parent: postgres
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

output id string = postgres.id
output name string = postgres.name
output fqdn string = postgres.properties.fullyQualifiedDomainName
output databaseName string = database.name
output connectionString string = 'Host=${postgres.properties.fullyQualifiedDomainName};Database=${databaseName};Username=${adminUsername};Password=${adminPassword};Ssl Mode=Require;Trust Server Certificate=true'
