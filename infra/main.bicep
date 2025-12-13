targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

param principalId string = ''

var abbrs = {
  operationalInsightsWorkspaces: 'log-'
  appManagedEnvironments: 'cae-'
  serviceBusNamespaces: 'sb-'
  containerApps: 'ca-'
  userAssignedIdentities: 'id-'
  containerRegistry: 'cr-'
}

var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module resources 'resources.bicep' = {
  name: 'resources'
  scope: rg
  params: {
    location: location
    tags: tags
    resourceToken: resourceToken
    abbrs: abbrs
    principalId: principalId
  }
}

output AZURE_CONTAINER_REGISTRY_ENDPOINT string = resources.outputs.AZURE_CONTAINER_REGISTRY_ENDPOINT
output AZURE_KEY_VAULT_ENDPOINT string = resources.outputs.AZURE_KEY_VAULT_ENDPOINT
output AZURE_RESOURCE_CONTAINER_APPS_ENVIRONMENT_NAME string = resources.outputs.AZURE_RESOURCE_CONTAINER_APPS_ENVIRONMENT_NAME
