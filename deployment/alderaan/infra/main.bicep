targetScope = 'subscription'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Environment name (dev, staging, prod)')
param environmentName string

@description('Azure region for all resources')
param location string

@description('Resource group name override (optional)')
param resourceGroupName string = ''

@description('Tags to apply to all resources')
param tags object = {}

// Network
@description('VNet address prefix (CIDR)')
param vnetAddressPrefix string = '10.210.0.0/16'

@description('ACA infrastructure subnet address prefix (CIDR). Must be at least /23')
param acaInfrastructureSubnetPrefix string = '10.210.0.0/23'

@description('PostgreSQL delegated subnet address prefix (CIDR)')
param postgresSubnetPrefix string = '10.210.2.0/24'

// Database
@description('PostgreSQL admin username')
param postgresAdminUsername string = 'postgres'

@secure()
@description('PostgreSQL admin password')
param postgresAdminPassword string

@description('PostgreSQL version')
@allowed(['14', '15', '16'])
param postgresVersion string = '15'

// Container Registry
@description('ACR SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string = 'Basic'

// Container Apps
@secure()
@description('Admin token for Nitro Schema API')
param nitroAdminToken string

@description('Docker image tag to deploy')
param imageTag string = 'latest'

@description('Repository prefix for container images')
param repositoryPrefix string = 'graphql-gateway'

@description('Whether to deploy the container apps (set to false for initial infra provision)')
param deployApps bool = true

// ============================================================================
// VARIABLES
// ============================================================================

var abbrs = loadJsonContent('./abbreviations.json')
var uniqueSuffix = toLower(take(uniqueString(subscription().id, rgName), 8))
var resourceToken = '${environmentName}-${uniqueSuffix}'

// Resource group name: use override or generate
var rgName = !empty(resourceGroupName) ? resourceGroupName : 'rg-graphql-gateway-${environmentName}'

// Star Wars theme tags
var defaultTags = union(tags, {
  'azd-env-name': environmentName
  project: 'graphql-gateway'
  codename: 'alderaan'
})

// ============================================================================
// RESOURCE GROUP
// ============================================================================

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgName
  location: location
  tags: defaultTags
}

// ============================================================================
// CORE INFRASTRUCTURE MODULES
// ============================================================================

module network './core/network.bicep' = {
  name: 'network-${resourceToken}'
  scope: rg
  params: {
    location: location
    tags: defaultTags
    resourceToken: resourceToken
    abbrs: abbrs
    vnetAddressPrefix: vnetAddressPrefix
    acaInfrastructureSubnetPrefix: acaInfrastructureSubnetPrefix
    postgresSubnetPrefix: postgresSubnetPrefix
  }
}

module monitoring './core/monitoring.bicep' = {
  name: 'monitoring-${resourceToken}'
  scope: rg
  params: {
    location: location
    tags: defaultTags
    resourceToken: resourceToken
    abbrs: abbrs
  }
}

module registry './core/registry.bicep' = {
  name: 'registry-${resourceToken}'
  scope: rg
  params: {
    location: location
    tags: defaultTags
    resourceToken: resourceToken
    abbrs: abbrs
    sku: acrSku
  }
}

module database './core/database.bicep' = {
  name: 'database-${resourceToken}'
  scope: rg
  params: {
    location: location
    tags: defaultTags
    resourceToken: resourceToken
    abbrs: abbrs
    vnetId: network.outputs.vnetId
    postgresSubnetId: network.outputs.postgresSubnetId
    adminUsername: postgresAdminUsername
    adminPassword: postgresAdminPassword
    version: postgresVersion
  }
}

// ============================================================================
// CONTAINER APPS MODULES
// ============================================================================

module environment './apps/environment.bicep' = {
  name: 'environment-${resourceToken}'
  scope: rg
  params: {
    location: location
    tags: defaultTags
    resourceToken: resourceToken
    abbrs: abbrs
    acaSubnetId: network.outputs.acaSubnetId
    logAnalyticsCustomerId: monitoring.outputs.logAnalyticsCustomerId
    logAnalyticsSharedKey: monitoring.outputs.logAnalyticsSharedKey
  }
}

module subgraphs './apps/subgraphs.bicep' = if (deployApps) {
  name: 'subgraphs-${resourceToken}'
  scope: rg
  params: {
    location: location
    tags: defaultTags
    environmentId: environment.outputs.environmentId
    registryLoginServer: registry.outputs.loginServer
    registryName: registry.outputs.name
    postgresConnectionString: database.outputs.connectionString
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    imageTag: imageTag
    repositoryPrefix: repositoryPrefix
  }
}

module nitro './apps/nitro.bicep' = if (deployApps) {
  name: 'nitro-${resourceToken}'
  scope: rg
  params: {
    location: location
    tags: defaultTags
    environmentId: environment.outputs.environmentId
    registryLoginServer: registry.outputs.loginServer
    registryName: registry.outputs.name
    postgresConnectionString: database.outputs.connectionString
    nitroAdminToken: nitroAdminToken
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    imageTag: imageTag
    repositoryPrefix: repositoryPrefix
  }
}

module gateway './apps/gateway.bicep' = if (deployApps) {
  name: 'gateway-${resourceToken}'
  scope: rg
  params: {
    location: location
    tags: defaultTags
    environmentId: environment.outputs.environmentId
    registryLoginServer: registry.outputs.loginServer
    registryName: registry.outputs.name
    nitroSchemaWsUrl: nitro.outputs.internalWsUrl
    nitroAdminToken: nitroAdminToken
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    imageTag: imageTag
    repositoryPrefix: repositoryPrefix
  }
}

module frontend './apps/frontend.bicep' = if (deployApps) {
  name: 'frontend-${resourceToken}'
  scope: rg
  params: {
    location: location
    tags: defaultTags
    environmentId: environment.outputs.environmentId
    registryLoginServer: registry.outputs.loginServer
    registryName: registry.outputs.name
    gatewayFqdn: gateway.outputs.fqdn
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    imageTag: imageTag
    repositoryPrefix: repositoryPrefix
  }
}

module workers './apps/workers.bicep' = if (deployApps) {
  name: 'workers-${resourceToken}'
  scope: rg
  params: {
    location: location
    tags: defaultTags
    environmentId: environment.outputs.environmentId
    registryLoginServer: registry.outputs.loginServer
    registryName: registry.outputs.name
    postgresConnectionString: database.outputs.connectionString
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    imageTag: imageTag
    repositoryPrefix: repositoryPrefix
  }
}

// ============================================================================
// OUTPUTS (for azd and scripts)
// ============================================================================

// Azure resource identifiers
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId

// Container Registry
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = registry.outputs.name

// Container Apps Environment
output AZURE_CONTAINER_APPS_ENVIRONMENT_NAME string = environment.outputs.environmentName
output AZURE_CONTAINER_APPS_ENVIRONMENT_ID string = environment.outputs.environmentId
output AZURE_CONTAINER_APPS_ENVIRONMENT_DEFAULT_DOMAIN string = environment.outputs.defaultDomain

// Service endpoints
output GATEWAY_FQDN string = deployApps ? gateway.outputs.fqdn : ''
output GATEWAY_URL string = deployApps ? 'https://${gateway.outputs.fqdn}/graphql' : ''
output FRONTEND_FQDN string = deployApps ? frontend.outputs.fqdn : ''
output FRONTEND_URL string = deployApps ? 'https://${frontend.outputs.fqdn}' : ''

// Nitro Schema API
output NITRO_INTERNAL_FQDN string = deployApps ? nitro.outputs.internalFqdn : ''
output NITRO_WS_URL string = deployApps ? nitro.outputs.internalWsUrl : ''

// Database
output POSTGRES_FQDN string = database.outputs.fqdn
output POSTGRES_DATABASE string = database.outputs.databaseName

// Monitoring
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.appInsightsConnectionString
output LOG_ANALYTICS_WORKSPACE_NAME string = monitoring.outputs.logAnalyticsWorkspaceName

// Subgraph FQDNs (for FGP composition)
output PRODUCTS_FQDN string = deployApps ? subgraphs.outputs.productsFqdn : ''
output REVIEWS_FQDN string = deployApps ? subgraphs.outputs.reviewsFqdn : ''
output SHIPPING_FQDN string = deployApps ? subgraphs.outputs.shippingFqdn : ''
output ORDERS_FQDN string = deployApps ? subgraphs.outputs.ordersFqdn : ''
