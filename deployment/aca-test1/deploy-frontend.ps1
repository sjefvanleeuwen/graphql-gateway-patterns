param(
  [string]$DeploymentName = 'alderaan-bootstrap',
  [string]$RepositoryPrefix = 'graphql-gateway',
  [string]$ImageTag = 'latest',
  [switch]$SkipImageUpdate
)

$ErrorActionPreference = 'Stop'

Write-Host "Loading outputs from deployment '$DeploymentName'..."
$outputsJson = az deployment sub show --name $DeploymentName --query properties.outputs -o json
if ([string]::IsNullOrWhiteSpace($outputsJson)) {
  throw "No outputs returned. Did you run deployment/aca-test1/provision.ps1 successfully?"
}
$outputs = $outputsJson | ConvertFrom-Json

$resourceGroupName = $outputs.resourcE_GROUP_NAME.value
$acrLoginServer = $outputs.acR_LOGIN_SERVER.value

if ([string]::IsNullOrWhiteSpace($resourceGroupName)) {
  throw "Missing resource group output."
}

$gatewayFqdn = az containerapp show -g $resourceGroupName -n gateway --query properties.configuration.ingress.fqdn -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gatewayFqdn)) {
  throw "Failed to fetch gateway FQDN. Is the 'gateway' container app created?"
}

$frontendEnv = @(
  "GRAPHQL_HTTP=https://$gatewayFqdn/graphql",
  "GRAPHQL_WS=wss://$gatewayFqdn/graphql"
)

Write-Host "Setting frontend runtime GraphQL endpoints:"
Write-Host "- GRAPHQL_HTTP=$($frontendEnv[0].Split('=')[1])"
Write-Host "- GRAPHQL_WS=$($frontendEnv[1].Split('=')[1])"

if (-not $SkipImageUpdate) {
  $image = "$acrLoginServer/$RepositoryPrefix/frontend:$ImageTag"
  Write-Host "Updating frontend image -> $image"
  az containerapp update -g $resourceGroupName -n frontend --image $image | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "az containerapp update --image failed for frontend" }
}

Write-Host "Updating frontend env vars..."
az containerapp update -g $resourceGroupName -n frontend --set-env-vars @frontendEnv | Out-Host
if ($LASTEXITCODE -ne 0) { throw "az containerapp update --set-env-vars failed for frontend" }

$frontendFqdn = az containerapp show -g $resourceGroupName -n frontend --query properties.configuration.ingress.fqdn -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($frontendFqdn)) { throw "Failed to fetch frontend FQDN" }

Write-Host ""
Write-Host "Done. Frontend endpoint: https://$frontendFqdn/"
