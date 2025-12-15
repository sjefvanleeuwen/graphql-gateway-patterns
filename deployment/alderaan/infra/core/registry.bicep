// ============================================================================
// Container Registry Module
// ============================================================================
targetScope = 'resourceGroup'

param location string
param tags object
param resourceToken string
param abbrs object

@allowed(['Basic', 'Standard', 'Premium'])
param sku string = 'Basic'

// ACR names must be alphanumeric only, 5-50 chars
var acrName = take(replace('${abbrs.containerRegistryRegistries}${replace(resourceToken, '-', '')}', '-', ''), 50)

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: { name: sku }
  properties: {
    adminUserEnabled: true
  }
}

output id string = acr.id
output name string = acr.name
output loginServer string = acr.properties.loginServer
