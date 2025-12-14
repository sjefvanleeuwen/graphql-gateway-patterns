$ErrorActionPreference = 'Stop'

$DeploymentName = 'alderaan-bootstrap'
$Location = 'northeurope'

Write-Host "Provisioning: RG aca-test1 + VNet (/23) + ACR + empty Container Apps Environment" 
Write-Host "Deployment name: $DeploymentName" 
Write-Host "Location: $Location" 

az deployment sub create `
  --name $DeploymentName `
  --location $Location `
  --template-file deployment/aca-test1/main.bicep `
  --parameters @deployment/aca-test1/main.parameters.json
