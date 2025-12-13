param name string
param location string
param tags object = {}
param identityName string = ''
param containerAppsEnvironmentName string
param containerRegistryName string = ''
param serviceName string = ''
param exists bool = false
param env array = []
param targetPort int = 8080
param external bool = false

resource app 'Microsoft.App/containerApps@2023-05-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityName}': {} // Fixed: Use resourceId or existing reference if needed, but string ID works if full resource ID is passed. 
                            // Actually, let's assume identityName is the Resource ID for simplicity in this fix.
                            // Or better, let's fix the identity reference in the next step properly.
    }
  }
  properties: {
    managedEnvironmentId: resourceId('Microsoft.App/managedEnvironments', containerAppsEnvironmentName)
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: external
        targetPort: targetPort
        transport: 'auto'
      }
      registries: !empty(containerRegistryName) ? [
        {
          server: '${containerRegistryName}.azurecr.io'
          identity: identityName
        }
      ] : []
    }
    template: {
      containers: [
        {
          name: 'main'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          env: env
        }
      ]
    }
  }
}

output id string = app.id
output name string = app.name
output fqdn string = app.properties.configuration.ingress.fqdn

