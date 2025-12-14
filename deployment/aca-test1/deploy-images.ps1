param(
  [string]$DeploymentName = 'alderaan-bootstrap',
  [string]$RepositoryPrefix = 'graphql-gateway',
  [switch]$AlsoTagLatest
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot = Split-Path -Parent $RepoRoot  # ...\deployment\aca-test1 -> repo root

Write-Host "Loading outputs from deployment '$DeploymentName'..."
$outputsJson = az deployment sub show --name $DeploymentName --query properties.outputs -o json
if ([string]::IsNullOrWhiteSpace($outputsJson)) {
  throw "No outputs returned. Did you run deployment/aca-test1/provision.ps1 successfully?"
}

$outputs = $outputsJson | ConvertFrom-Json

$acrLoginServer = $outputs.ACR_LOGIN_SERVER.value
$acrName = $outputs.ACR_NAME.value

if ([string]::IsNullOrWhiteSpace($acrLoginServer) -or [string]::IsNullOrWhiteSpace($acrName)) {
  throw "Missing ACR outputs. Ensure the deployment outputs include ACR_NAME and ACR_LOGIN_SERVER."
}

$tag = "alderaan-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"

Write-Host "ACR: $acrLoginServer"
Write-Host "Tag: $tag"
Write-Host ""

Write-Host "Logging into ACR..."
az acr login --name $acrName | Out-Host

function BuildAndPushDotnetService {
  param(
    [Parameter(Mandatory = $true)][string]$ServiceName,
    [Parameter(Mandatory = $true)][string]$DockerfileRelativeToSrc
  )

  $image = "$acrLoginServer/$RepositoryPrefix/${ServiceName}:$tag"
  Write-Host "\nBuilding $ServiceName -> $image"

  Push-Location (Join-Path $RepoRoot 'src')
  try {
    docker build -t $image -f $DockerfileRelativeToSrc .
    if ($LASTEXITCODE -ne 0) { throw "docker build failed for $ServiceName" }

    docker push $image
    if ($LASTEXITCODE -ne 0) { throw "docker push failed for $ServiceName" }

    if ($AlsoTagLatest) {
      $latest = "$acrLoginServer/$RepositoryPrefix/${ServiceName}:latest"
      docker tag $image $latest
      if ($LASTEXITCODE -ne 0) { throw "docker tag failed for $ServiceName (:latest)" }
      docker push $latest
      if ($LASTEXITCODE -ne 0) { throw "docker push failed for $ServiceName (:latest)" }
    }
  }
  finally {
    Pop-Location
  }
}

function BuildAndPushFrontend {
  param([Parameter(Mandatory = $true)][string]$ServiceName)

  $image = "$acrLoginServer/$RepositoryPrefix/${ServiceName}:$tag"
  Write-Host "\nBuilding $ServiceName -> $image"

  Push-Location (Join-Path $RepoRoot 'frontend')
  try {
    docker build -t $image .
    if ($LASTEXITCODE -ne 0) { throw "docker build failed for $ServiceName" }

    docker push $image
    if ($LASTEXITCODE -ne 0) { throw "docker push failed for $ServiceName" }

    if ($AlsoTagLatest) {
      $latest = "$acrLoginServer/$RepositoryPrefix/${ServiceName}:latest"
      docker tag $image $latest
      if ($LASTEXITCODE -ne 0) { throw "docker tag failed for $ServiceName (:latest)" }
      docker push $latest
      if ($LASTEXITCODE -ne 0) { throw "docker push failed for $ServiceName (:latest)" }
    }
  }
  finally {
    Pop-Location
  }
}

# .NET services (Dockerfiles expect src/ as build context)
BuildAndPushDotnetService -ServiceName 'gateway' -DockerfileRelativeToSrc 'Gateway/Dockerfile'
BuildAndPushDotnetService -ServiceName 'products' -DockerfileRelativeToSrc 'ProductsService/Dockerfile'
BuildAndPushDotnetService -ServiceName 'reviews' -DockerfileRelativeToSrc 'ReviewsService/Dockerfile'
BuildAndPushDotnetService -ServiceName 'shipping' -DockerfileRelativeToSrc 'ShippingService/Dockerfile'
BuildAndPushDotnetService -ServiceName 'orders' -DockerfileRelativeToSrc 'OrdersService/Dockerfile'
BuildAndPushDotnetService -ServiceName 'backoffice' -DockerfileRelativeToSrc 'BackOfficeService/Dockerfile'

# Frontend (Dockerfile lives in frontend/)
BuildAndPushFrontend -ServiceName 'frontend'

Write-Host "\nDone. Images pushed with tag: $tag"
if ($AlsoTagLatest) {
  Write-Host "Also pushed :latest tags."
}
