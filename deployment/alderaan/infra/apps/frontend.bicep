// ============================================================================
// Frontend Module
// React/Vue frontend served via nginx
// ============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param environmentId string
param registryLoginServer string
param registryName string
param gatewayFqdn string
param appInsightsConnectionString string

param imageTag string = 'latest'
param repositoryPrefix string = 'graphql-gateway'

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: registryName
}

var registryPassword = acr.listCredentials().passwords[0].value
var registryUsername = acr.listCredentials().username

resource frontend 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'frontend'
  location: location
  tags: union(tags, { 'azd-service-name': 'frontend' })
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
        transport: 'auto'
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
      ]
    }
    template: {
      containers: [
        {
          name: 'frontend'
          image: '${registryLoginServer}/${repositoryPrefix}/frontend:${imageTag}'
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            // Runtime environment injection for the frontend
            { name: 'GRAPHQL_HTTP', value: 'https://${gatewayFqdn}/graphql' }
            { name: 'GRAPHQL_WS', value: 'wss://${gatewayFqdn}/graphql' }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/'
                port: 80
              }
              initialDelaySeconds: 5
              periodSeconds: 10
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/'
                port: 80
              }
              initialDelaySeconds: 3
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
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

output fqdn string = frontend.properties.configuration.ingress.fqdn
output url string = 'https://${frontend.properties.configuration.ingress.fqdn}'
