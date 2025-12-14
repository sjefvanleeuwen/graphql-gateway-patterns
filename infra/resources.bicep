param location string
param resourceToken string
param tags object
param abbrs object
param principalId string = ''

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${abbrs.userAssignedIdentities}${resourceToken}'
  location: location
  tags: tags
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: replace('${abbrs.containerRegistry}${resourceToken}', '-', '')
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' = {
  name: 'vnet-${resourceToken}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'aca-subnet'
        properties: {
          addressPrefix: '10.0.0.0/23'
          delegations: [
            {
              name: 'Microsoft.App/environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'psql-subnet'
        properties: {
          addressPrefix: '10.0.2.0/24'
          delegations: [
            {
              name: 'Microsoft.DBforPostgreSQL/flexibleServers'
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

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'private.postgres.database.azure.com'
  location: 'global'
  tags: tags
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'postgres-link-${resourceToken}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource env 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: '${abbrs.appManagedEnvironments}${resourceToken}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: vnet.properties.subnets[0].id
    }
  }
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2022-12-01' = {
  name: '${abbrs.dBforPostgreSQLFlexibleServers}${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '15'
    administratorLogin: 'postgres'
    administratorLoginPassword: 'Password123!'
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    network: {
      delegatedSubnetResourceId: vnet.properties.subnets[1].id
      privateDnsZoneArmResourceId: privateDnsZone.id
    }
  }
  dependsOn: [
    privateDnsZoneLink
  ]
}

var postgresConnectionString = 'Host=${postgres.properties.fullyQualifiedDomainName};Port=5432;Database=postgres;Username=postgres;Password=Password123!'

module gateway 'app.bicep' = {
  name: 'gateway'
  params: {
    name: '${abbrs.containerApps}gateway-${resourceToken}'
    location: location
    tags: tags
    identityName: identity.id
    containerAppsEnvironmentName: env.name
    containerRegistryName: acr.name
    external: true
    env: [
      {
        name: 'ASPNETCORE_ENVIRONMENT'
        value: 'Development'
      }
    ]
  }
}

module products 'app.bicep' = {
  name: 'products'
  params: {
    name: '${abbrs.containerApps}products-${resourceToken}'
    location: location
    tags: tags
    identityName: identity.id
    containerAppsEnvironmentName: env.name
    containerRegistryName: acr.name
    env: [
      {
        name: 'ASPNETCORE_ENVIRONMENT'
        value: 'Development'
      }
    ]
  }
}

module reviews 'app.bicep' = {
  name: 'reviews'
  params: {
    name: '${abbrs.containerApps}reviews-${resourceToken}'
    location: location
    tags: tags
    identityName: identity.id
    containerAppsEnvironmentName: env.name
    containerRegistryName: acr.name
    env: [
      {
        name: 'ASPNETCORE_ENVIRONMENT'
        value: 'Development'
      }
    ]
  }
}

module shipping 'app.bicep' = {
  name: 'shipping'
  params: {
    name: '${abbrs.containerApps}shipping-${resourceToken}'
    location: location
    tags: tags
    identityName: identity.id
    containerAppsEnvironmentName: env.name
    containerRegistryName: acr.name
    env: [
      {
        name: 'ASPNETCORE_ENVIRONMENT'
        value: 'Development'
      }
    ]
  }
}

module orders 'app.bicep' = {
  name: 'orders'
  params: {
    name: '${abbrs.containerApps}orders-${resourceToken}'
    location: location
    tags: tags
    identityName: identity.id
    containerAppsEnvironmentName: env.name
    containerRegistryName: acr.name
    env: [
      {
        name: 'ASPNETCORE_ENVIRONMENT'
        value: 'Development'
      }
      {
        name: 'ConnectionStrings__postgres'
        value: postgresConnectionString
      }
    ]
  }
}

module backoffice 'app.bicep' = {
  name: 'backoffice'
  params: {
    name: '${abbrs.containerApps}backoffice-${resourceToken}'
    location: location
    tags: tags
    identityName: identity.id
    containerAppsEnvironmentName: env.name
    containerRegistryName: acr.name
    env: [
      {
        name: 'ASPNETCORE_ENVIRONMENT'
        value: 'Development'
      }
      {
        name: 'ConnectionStrings__postgres'
        value: postgresConnectionString
      }
    ]
  }
}

module frontend 'app.bicep' = {
  name: 'frontend'
  params: {
    name: '${abbrs.containerApps}frontend-${resourceToken}'
    location: location
    tags: tags
    identityName: identity.id
    containerAppsEnvironmentName: env.name
    containerRegistryName: acr.name
    external: true
    targetPort: 80
    env: [
      {
        name: 'GRAPHQL_HTTP'
        value: 'https://${gateway.outputs.fqdn}/graphql'
      }
      {
        name: 'GRAPHQL_WS'
        value: 'wss://${gateway.outputs.fqdn}/graphql'
      }
    ]
  }
}

output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.properties.loginServer

output AZURE_KEY_VAULT_ENDPOINT string = '' // Not used
output AZURE_RESOURCE_CONTAINER_APPS_ENVIRONMENT_NAME string = env.name
