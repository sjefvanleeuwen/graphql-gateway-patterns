// ============================================================================
// Subgraph Services Module: Products, Reviews, Shipping, Orders
// ============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param environmentId string
param registryLoginServer string
param registryName string
@secure()
param postgresConnectionString string
param appInsightsConnectionString string

param imageTag string = 'latest'
param repositoryPrefix string = 'graphql-gateway'

// Get registry credentials
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: registryName
}

var registryPassword = acr.listCredentials().passwords[0].value
var registryUsername = acr.listCredentials().username

// Common configuration for all subgraphs
var commonSecrets = [
  { name: 'registry-password', value: registryPassword }
]

var commonRegistries = [
  {
    server: registryLoginServer
    username: registryUsername
    passwordSecretRef: 'registry-password'
  }
]

// Stateless subgraphs (no database dependency)
var statelessServices = [
  { name: 'products', port: 8080 }
  { name: 'reviews', port: 8080 }
  { name: 'shipping', port: 8080 }
]

resource statelessApps 'Microsoft.App/containerApps@2024-03-01' = [for svc in statelessServices: {
  name: svc.name
  location: location
  tags: union(tags, { 'azd-service-name': svc.name })
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: svc.port
        allowInsecure: true
        transport: 'auto'
      }
      registries: commonRegistries
      secrets: commonSecrets
    }
    template: {
      containers: [
        {
          name: svc.name
          image: '${registryLoginServer}/${repositoryPrefix}/${svc.name}:${imageTag}'
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
            { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/graphql?query=%7B__typename%7D'
                port: svc.port
              }
              initialDelaySeconds: 15
              periodSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/graphql?query=%7B__typename%7D'
                port: svc.port
              }
              initialDelaySeconds: 5
              periodSeconds: 5
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}]

// Orders service (needs Postgres for Wolverine messaging)
resource ordersApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'orders'
  location: location
  tags: union(tags, { 'azd-service-name': 'orders' })
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 8080
        allowInsecure: true
        transport: 'auto'
      }
      registries: commonRegistries
      secrets: [
        { name: 'registry-password', value: registryPassword }
        { name: 'postgres-conn', value: postgresConnectionString }
      ]
    }
    template: {
      containers: [
        {
          name: 'orders'
          image: '${registryLoginServer}/${repositoryPrefix}/orders:${imageTag}'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'ConnectionStrings__postgres', secretRef: 'postgres-conn' }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
            { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/graphql?query=%7B__typename%7D'
                port: 8080
              }
              initialDelaySeconds: 20
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 5
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '30'
              }
            }
          }
        ]
      }
    }
  }
}

output productsFqdn string = statelessApps[0].properties.configuration.ingress.fqdn
output reviewsFqdn string = statelessApps[1].properties.configuration.ingress.fqdn
output shippingFqdn string = statelessApps[2].properties.configuration.ingress.fqdn
output ordersFqdn string = ordersApp.properties.configuration.ingress.fqdn
