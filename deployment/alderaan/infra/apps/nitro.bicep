// ============================================================================
// Nitro Schema API Module
// WebSocket hub for live gateway.fgp distribution
// ============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param environmentId string
param registryLoginServer string
param registryName string
@secure()
param postgresConnectionString string
@secure()
param nitroAdminToken string
param appInsightsConnectionString string

param imageTag string = 'latest'
param repositoryPrefix string = 'graphql-gateway'

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: registryName
}

var registryPassword = acr.listCredentials().passwords[0].value
var registryUsername = acr.listCredentials().username

resource nitro 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'nitro-schema-api'
  location: location
  tags: union(tags, { 'azd-service-name': 'nitro-schema-api' })
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 8080
        allowInsecure: true
        transport: 'auto'  // Allows WebSocket upgrade
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
        { name: 'postgres-conn', value: postgresConnectionString }
        { name: 'nitro-admin-token', value: nitroAdminToken }
      ]
    }
    template: {
      containers: [
        {
          name: 'nitro-schema-api'
          image: '${registryLoginServer}/${repositoryPrefix}/nitro-schema-api:${imageTag}'
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            { name: 'ConnectionStrings__postgres', secretRef: 'postgres-conn' }
            { name: 'NITRO_ADMIN_TOKEN', secretRef: 'nitro-admin-token' }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
            { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 10
              periodSeconds: 10
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 5
              periodSeconds: 5
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
}

output internalFqdn string = nitro.properties.configuration.ingress.fqdn
output internalWsUrl string = 'ws://${nitro.properties.configuration.ingress.fqdn}/ws'
output internalHttpUrl string = 'http://${nitro.properties.configuration.ingress.fqdn}'
