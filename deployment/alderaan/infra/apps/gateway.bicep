// ============================================================================
// Gateway Module
// HotChocolate Fusion Gateway with Nitro Schema API integration
// ============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param environmentId string
param registryLoginServer string
param registryName string
param nitroSchemaWsUrl string
@secure()
param nitroAdminToken string
param appInsightsConnectionString string

param imageTag string = 'latest'
param repositoryPrefix string = 'graphql-gateway'

@description('CORS allowed origins (comma-separated)')
param corsAllowedOrigins string = '*'

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: registryName
}

var registryPassword = acr.listCredentials().passwords[0].value
var registryUsername = acr.listCredentials().username

resource gateway 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'gateway'
  location: location
  tags: union(tags, { 'azd-service-name': 'gateway' })
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'  // Allows WebSocket for GraphQL subscriptions
        corsPolicy: {
          allowedOrigins: corsAllowedOrigins == '*' ? ['*'] : split(corsAllowedOrigins, ',')
          allowedMethods: ['GET', 'POST', 'OPTIONS']
          allowedHeaders: ['*']
          allowCredentials: corsAllowedOrigins != '*'
        }
      }
      registries: [
        {
          server: registryLoginServer
          username: registryUsername
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        { name: 'registry-password', value: registryPassword }
        { name: 'nitro-admin-token', value: nitroAdminToken }
      ]
    }
    template: {
      containers: [
        {
          name: 'gateway'
          image: '${registryLoginServer}/${repositoryPrefix}/gateway:${imageTag}'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'NITRO_SCHEMA_WS', value: nitroSchemaWsUrl }
            { name: 'NITRO_ADMIN_TOKEN', secretRef: 'nitro-admin-token' }
            { name: 'CORS_ALLOWED_ORIGINS', value: corsAllowedOrigins }
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
            {
              type: 'Readiness'
              httpGet: {
                path: '/graphql?query=%7B__typename%7D'
                port: 8080
              }
              initialDelaySeconds: 10
              periodSeconds: 5
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
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

output fqdn string = gateway.properties.configuration.ingress.fqdn
output url string = 'https://${gateway.properties.configuration.ingress.fqdn}'
output graphqlUrl string = 'https://${gateway.properties.configuration.ingress.fqdn}/graphql'
