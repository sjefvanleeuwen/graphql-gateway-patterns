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
  }
}

resource sb 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: '${abbrs.serviceBusNamespaces}${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
}

resource sbQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: sb
  name: 'orders'
}

// Role Assignment for Identity to access Service Bus (Data Owner)
resource sbRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sb.id, identity.id, 'Azure Service Bus Data Owner')
  scope: sb
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '090c5cfd-751d-490a-894a-3ce6f1109419')
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Connection String for Wolverine (if not using Managed Identity directly, but Wolverine supports MI? 
// The code uses connection string. Let's provide it.)
var sbConnectionString = 'Endpoint=sb://${sb.name}.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=${sb.listKeys().primaryKey}'

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
        name: 'ConnectionStrings__messaging'
        value: sbConnectionString
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
        name: 'ConnectionStrings__messaging'
        value: sbConnectionString
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
