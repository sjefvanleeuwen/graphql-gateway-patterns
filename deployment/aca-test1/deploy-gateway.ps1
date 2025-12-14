param(
  [string]$DeploymentName = 'alderaan-bootstrap',
  [string]$RepositoryPrefix = 'graphql-gateway',
  [string]$ImageTag = 'latest',
  [switch]$SkipBuild,
  [switch]$RecomposeFgp,
  [switch]$AlsoTagLatest
)

$ErrorActionPreference = 'Stop'

Write-Host "Loading outputs from deployment '$DeploymentName'..."
$outputsJson = az deployment sub show --name $DeploymentName --query properties.outputs -o json
if ([string]::IsNullOrWhiteSpace($outputsJson)) {
  throw "No outputs returned. Did you run deployment/aca-test1/provision.ps1 successfully?"
}
$outputs = $outputsJson | ConvertFrom-Json

$resourceGroupName = $outputs.resourcE_GROUP_NAME.value
$environmentName = $outputs.containerappS_ENVIRONMENT_NAME.value
$acrLoginServer = $outputs.acR_LOGIN_SERVER.value
$acrName = $outputs.acR_NAME.value

if ([string]::IsNullOrWhiteSpace($resourceGroupName) -or [string]::IsNullOrWhiteSpace($environmentName)) {
  throw "Missing required deployment outputs (resource group / environment name)."
}
if ([string]::IsNullOrWhiteSpace($acrLoginServer) -or [string]::IsNullOrWhiteSpace($acrName)) {
  throw "Missing required ACR outputs."
}

Write-Host "Resource Group: $resourceGroupName"
Write-Host "Container Apps Env: $environmentName"
Write-Host "ACR: $acrLoginServer"
Write-Host "Image tag: $ImageTag"
Write-Host ""

Write-Host "Fetching ACR credentials (admin user)..."
$acrCredsJson = az acr credential show -n $acrName --query "{username:username,password:passwords[0].value}" -o json
$acrCreds = $acrCredsJson | ConvertFrom-Json
$acrUsername = $acrCreds.username
$acrPassword = $acrCreds.password

if ([string]::IsNullOrWhiteSpace($acrUsername) -or [string]::IsNullOrWhiteSpace($acrPassword)) {
  throw "Failed to retrieve ACR admin credentials. Ensure acrAdminUserEnabled=true."
}

$tagToDeploy = $ImageTag
$shouldAlsoTagLatest = $AlsoTagLatest

if (-not $SkipBuild -and $ImageTag -eq 'latest') {
  # Using :latest will often not roll a new ACA revision because the image string doesn't change.
  # Deploy a unique tag to force a new revision, but also refresh :latest for convenience.
  $tagToDeploy = "alderaan-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
  $shouldAlsoTagLatest = $true
}

$imageToDeploy = "$acrLoginServer/$RepositoryPrefix/gateway:$tagToDeploy"
$latestImage = "$acrLoginServer/$RepositoryPrefix/gateway:latest"

if (-not $SkipBuild) {
  if ($RecomposeFgp) {
    Write-Host "Resolving internal subgraph FQDNs for Fusion compose..."
    $productsFqdn = az containerapp show -g $resourceGroupName -n products --query properties.configuration.ingress.fqdn -o tsv
    $reviewsFqdn  = az containerapp show -g $resourceGroupName -n reviews  --query properties.configuration.ingress.fqdn -o tsv
    $shippingFqdn = az containerapp show -g $resourceGroupName -n shipping --query properties.configuration.ingress.fqdn -o tsv
    $ordersFqdn   = az containerapp show -g $resourceGroupName -n orders   --query properties.configuration.ingress.fqdn -o tsv

    if ([string]::IsNullOrWhiteSpace($productsFqdn) -or [string]::IsNullOrWhiteSpace($reviewsFqdn) -or [string]::IsNullOrWhiteSpace($shippingFqdn) -or [string]::IsNullOrWhiteSpace($ordersFqdn)) {
      throw "Could not resolve one or more internal subgraph FQDNs (products/reviews/shipping/orders)."
    }

    $composeScript = Join-Path $PSScriptRoot 'compose-gateway-fgp.ps1'
    if (-not (Test-Path $composeScript)) { throw "Compose script not found: $composeScript" }

    & $composeScript -ProductsFqdn $productsFqdn -ReviewsFqdn $reviewsFqdn -ShippingFqdn $shippingFqdn -OrdersFqdn $ordersFqdn -Scheme 'https'
    if ($LASTEXITCODE -ne 0) { throw "compose-gateway-fgp.ps1 failed" }
  }

  Write-Host "Logging into ACR..."
  az acr login --name $acrName | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "az acr login failed" }

  Write-Host "Building gateway image -> $imageToDeploy"
  Push-Location "C:\source\graphql-gateway-patterns\src"
  try {
    docker build -t $imageToDeploy -f "Gateway\Dockerfile" .
    if ($LASTEXITCODE -ne 0) { throw "docker build failed for gateway" }

    docker push $imageToDeploy
    if ($LASTEXITCODE -ne 0) { throw "docker push failed for gateway" }

    if ($shouldAlsoTagLatest) {
      docker tag $imageToDeploy $latestImage
      if ($LASTEXITCODE -ne 0) { throw "docker tag failed for gateway (:latest)" }

      docker push $latestImage
      if ($LASTEXITCODE -ne 0) { throw "docker push failed for gateway (:latest)" }
    }
  }
  finally {
    Pop-Location
  }
} else {
  Write-Host "Skipping docker build/push (SkipBuild set)."
}

Write-Host "Resolving frontend FQDN (for Gateway CORS_ALLOWED_ORIGINS)..."
$frontendFqdn = az containerapp show -g $resourceGroupName -n frontend --query properties.configuration.ingress.fqdn -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($frontendFqdn)) {
  throw "Failed to fetch frontend FQDN. Is the 'frontend' container app created?"
}

$gatewayCorsOrigins = @(
  "https://$frontendFqdn",
  'http://localhost:5173',
  'http://localhost:3000',
  'http://localhost:4999'
) -join ','

Write-Host "Updating gateway container app image + env vars..."
$registryArgs = @(
  'containerapp','registry','set',
  '-g', $resourceGroupName,
  '-n', 'gateway',
  '--server', $acrLoginServer,
  '--username', $acrUsername,
  '--password', $acrPassword
)

az @registryArgs | Out-Host
if ($LASTEXITCODE -ne 0) { throw "az containerapp registry set failed for gateway" }

$updateArgs = @(
  'containerapp','update',
  '-g', $resourceGroupName,
  '-n', 'gateway',
  '--image', $imageToDeploy,
  '--set-env-vars', "CORS_ALLOWED_ORIGINS=$gatewayCorsOrigins"
)

az @updateArgs | Out-Host

if ($LASTEXITCODE -ne 0) { throw "az containerapp update failed for gateway" }

$gatewayFqdn = az containerapp show -g $resourceGroupName -n gateway --query properties.configuration.ingress.fqdn -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gatewayFqdn)) { throw "Failed to fetch gateway FQDN" }

Write-Host ""
Write-Host "Done. Gateway endpoint: https://$gatewayFqdn/graphql"
Write-Host "CORS_ALLOWED_ORIGINS set to: $gatewayCorsOrigins"
