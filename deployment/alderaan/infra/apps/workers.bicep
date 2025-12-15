// ============================================================================
// Workers Module: BackOffice (scale-to-zero worker)
// Wolverine-based async message processor
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

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: registryName
}

var registryPassword = acr.listCredentials().passwords[0].value
var registryUsername = acr.listCredentials().username

// BackOffice worker - no ingress, can scale to zero
// Processes async messages from Wolverine/PostgreSQL queues
resource backoffice 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'backoffice'
  location: location
  tags: union(tags, { 'azd-service-name': 'backoffice' })
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      // NOTE: Workers typically don't need ingress, but BackOffice may have
      // a health endpoint or admin UI, so we keep internal ingress
      ingress: {
        external: false
        targetPort: 8080
        allowInsecure: true
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
        { name: 'postgres-conn', value: postgresConnectionString }
      ]
    }
    template: {
      containers: [
        {
          name: 'backoffice'
          image: '${registryLoginServer}/${repositoryPrefix}/back-office:${imageTag}'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'ConnectionStrings__postgres', secretRef: 'postgres-conn' }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
            { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
          ]
          // Workers don't need HTTP probes if they don't have endpoints
          // But BackOffice has ingress so we keep a basic probe
          probes: [
            {
              type: 'Liveness'
              tcpSocket: {
                port: 8080
              }
              initialDelaySeconds: 30
              periodSeconds: 30
              failureThreshold: 5
            }
          ]
        }
      ]
      scale: {
        // Scale to zero when no work, scale up based on queue depth
        minReplicas: 0
        maxReplicas: 3
        rules: [
          // KEDA PostgreSQL scaler - monitors Wolverine incoming_envelopes table
          // Uncomment and configure when ready for queue-based scaling
          // {
          //   name: 'queue-depth'
          //   custom: {
          //     type: 'postgresql'
          //     metadata: {
          //       connectionStringFromEnv: 'ConnectionStrings__postgres'
          //       query: 'SELECT COUNT(*) FROM wolverine_incoming_envelopes WHERE status = 0'
          //       targetValue: '10'
          //     }
          //   }
          // }
          
          // For now, use a simple cron scaler to keep at least 1 replica during business hours
          {
            name: 'business-hours'
            custom: {
              type: 'cron'
              metadata: {
                timezone: 'Europe/Amsterdam'
                start: '0 8 * * 1-5'   // 8 AM Mon-Fri
                end: '0 18 * * 1-5'    // 6 PM Mon-Fri
                desiredReplicas: '1'
              }
            }
          }
        ]
      }
    }
  }
}

output backofficeFqdn string = backoffice.properties.configuration.ingress.fqdn
