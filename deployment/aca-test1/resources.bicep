targetScope = 'resourceGroup'

param location string
param tags object
param vnetAddressPrefix string
param acaInfrastructureSubnetPrefix string
param postgresSubnetPrefix string
param acrSku string = 'Basic'
param acrAdminUserEnabled bool = true

param postgresAdminUsername string = 'postgres'
@secure()
param postgresAdminPassword string
param postgresVersion string = '15'

var token = toLower(uniqueString(resourceGroup().id))

// Star Wars naming theme (prefixes) — keep globally-unique suffix via `token`
// City-style naming theme (Alderaan + cities).
// NOTE: Many Azure resources still require global uniqueness; we keep `token` suffix for that.
var city = {
  vnet: 'vnet-aldera'
  acaSubnet: 'subnet-aldera'
  psqlSubnet: 'subnet-crevasse'
  // ACR name must be 5-50 chars, lowercase letters/numbers only.
  acrPrefix: 'craldera'
  log: 'log-tyrin'
  cae: 'cae-aldera'
  appi: 'appi-aldera'
  psql: 'psql-aldera'
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' = {
  name: '${city.vnet}-${token}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: city.acaSubnet
        properties: {
          addressPrefix: acaInfrastructureSubnetPrefix
        }
      }
      {
        name: city.psqlSubnet
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

resource acaSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-11-01' existing = {
  parent: vnet
  name: city.acaSubnet
}

resource postgresSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-11-01' existing = {
  parent: vnet
  name: city.psqlSubnet
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  // ACR name must be 5-50 chars, lowercase letters/numbers only.
  name: take('${city.acrPrefix}${replace(token, '-', '')}', 50)
  location: location
  tags: tags
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: acrAdminUserEnabled
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${city.log}-${token}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${city.appi}-${token}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'private.postgres.database.azure.com'
  location: 'global'
  tags: tags
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'psql-link-${token}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource cae 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: '${city.cae}-${token}'
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: acaSubnet.id
      internal: false
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: '${city.psql}-${token}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: postgresAdminUsername
    administratorLoginPassword: postgresAdminPassword
    version: postgresVersion
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      delegatedSubnetResourceId: postgresSubnet.id
      privateDnsZoneArmResourceId: privateDnsZone.id
    }
  }
}

resource postgresDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  parent: postgres
  name: 'orders'
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// Create A record in private DNS zone for Postgres FQDN
// Postgres in a delegated subnet gets the first available IP (.4)
var postgresSubnetOctets = split(split(postgresSubnetPrefix, '/')[0], '.')
var postgresPrivateIp = '${postgresSubnetOctets[0]}.${postgresSubnetOctets[1]}.${postgresSubnetOctets[2]}.4'

resource postgresARecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateDnsZone
  name: postgres.name
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: postgresPrivateIp
      }
    ]
  }
}

output ACR_NAME string = acr.name
output ACR_LOGIN_SERVER string = acr.properties.loginServer
output CONTAINERAPPS_ENVIRONMENT_NAME string = cae.name
output VNET_NAME string = vnet.name
output ACA_SUBNET_NAME string = acaSubnet.name
output ACA_SUBNET_ID string = acaSubnet.id

output LOG_ANALYTICS_WORKSPACE_NAME string = logAnalytics.name
output APPLICATIONINSIGHTS_NAME string = appInsights.name
output APPLICATIONINSIGHTS_CONNECTION_STRING string = appInsights.properties.ConnectionString

output POSTGRES_SERVER_NAME string = postgres.name
output POSTGRES_FQDN string = postgres.properties.fullyQualifiedDomainName
output POSTGRES_DATABASE_NAME string = postgresDb.name
