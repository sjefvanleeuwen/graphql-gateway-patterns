param(
  [string]$DeploymentName = 'alderaan-bootstrap',
  [string]$RepositoryPrefix = 'graphql-gateway',
  [string]$ImageTag = 'latest',
  [string]$ParametersFile = $(Join-Path $PSScriptRoot 'main.parameters.json'),
  [switch]$SkipPostgres
)

$ErrorActionPreference = 'Stop'

function Get-PlainTextFromSecureString {
  param([Parameter(Mandatory = $true)][SecureString]$Secure)
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

function Ensure-ContainerApp {
  param(
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [Parameter(Mandatory = $true)][string]$EnvironmentName,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Image,
    [Parameter(Mandatory = $true)][ValidateSet('external','internal')][string]$Ingress,
    [Parameter(Mandatory = $true)][int]$TargetPort,
    [Parameter(Mandatory = $true)][string]$RegistryServer,
    [Parameter(Mandatory = $true)][string]$RegistryUsername,
    [Parameter(Mandatory = $true)][string]$RegistryPassword,
    [string[]]$Secrets,
    [string[]]$EnvVars,
    [string]$HealthProbeType = 'none',  # 'none', 'http', 'tcp'
    [string]$HealthProbePort = '',
    [string]$HealthProbePath = ''
  )

  $existsCount = az containerapp list -g $ResourceGroup --query "[?name=='$Name'] | length(@)" -o tsv
  if ($LASTEXITCODE -ne 0) { throw "az containerapp list failed while checking existence of $Name" }
  $exists = ([int]$existsCount -gt 0)

  if (-not $exists) {
    Write-Host "Creating container app '$Name' ($Ingress) ..."

    $args = @(
      'containerapp','create',
      '--name', $Name,
      '--resource-group', $ResourceGroup,
      '--environment', $EnvironmentName,
      '--image', $Image,
      '--ingress', $Ingress,
      '--target-port', "$TargetPort",
      '--revisions-mode', 'single',
      '--registry-server', $RegistryServer,
      '--registry-username', $RegistryUsername,
      '--registry-password', $RegistryPassword,
      '--allow-insecure', 'true'
    )

    if ($Secrets -and $Secrets.Count -gt 0) { $args += @('--secrets') + $Secrets }
    if ($EnvVars -and $EnvVars.Count -gt 0) { $args += @('--env-vars') + $EnvVars }

    # Add health probes
    if ($HealthProbeType -eq 'http' -and -not [string]::IsNullOrWhiteSpace($HealthProbePath)) {
      $args += @(
        '--health-probe-type', 'liveness',
        '--health-probe-protocol', 'http',
        '--health-probe-method', 'GET',
        '--health-probe-port', $HealthProbePort,
        '--health-probe-path', $HealthProbePath,
        '--health-probe-interval', '10',
        '--health-probe-timeout', '5'
      )
    }

    az @args | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "az containerapp create failed for $Name" }
    return
  }

  Write-Host "Updating container app '$Name' ..."

  # Update image first
  az containerapp update -g $ResourceGroup -n $Name --image $Image | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "az containerapp update --image failed for $Name" }

  # Apply secrets/env vars if provided
  if ($Secrets -and $Secrets.Count -gt 0) {
    az containerapp secret set -g $ResourceGroup -n $Name --secrets @Secrets | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "az containerapp secret set failed for $Name" }
  }

  if ($EnvVars -and $EnvVars.Count -gt 0) {
    az containerapp update -g $ResourceGroup -n $Name --set-env-vars @EnvVars | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "az containerapp update --set-env-vars failed for $Name" }
  }
}

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

# Postgres connection string for Orders + BackOffice
$postgresConnectionString = $null
if (-not $SkipPostgres) {
  $postgresFqdn = $outputs.postgreS_FQDN.value
  $postgresDbName = $outputs.postgreS_DATABASE_NAME.value

  $pgUser = 'postgres'
  $pgPasswordPlain = $null

  if (Test-Path $ParametersFile) {
    try {
      $paramsJson = Get-Content -Raw -Path $ParametersFile | ConvertFrom-Json
      $pgUserFromParams = $paramsJson.parameters.postgresAdminUsername.value
      $pgPassFromParams = $paramsJson.parameters.postgresAdminPassword.value

      if (-not [string]::IsNullOrWhiteSpace($pgUserFromParams)) { $pgUser = $pgUserFromParams }
      if (-not [string]::IsNullOrWhiteSpace($pgPassFromParams)) { $pgPasswordPlain = $pgPassFromParams }
    }
    catch {
      Write-Warning "Could not parse ParametersFile '$ParametersFile' for postgres credentials."
    }
  }

  if ([string]::IsNullOrWhiteSpace($pgPasswordPlain)) {
    $secure = Read-Host "Enter Postgres admin password" -AsSecureString
    $pgPasswordPlain = Get-PlainTextFromSecureString -Secure $secure
  }

  if (-not [string]::IsNullOrWhiteSpace($postgresFqdn) -and -not [string]::IsNullOrWhiteSpace($postgresDbName)) {
    $postgresConnectionString = "Host=$postgresFqdn;Database=$postgresDbName;Username=$pgUser;Password=$pgPasswordPlain;Ssl Mode=Require;Trust Server Certificate=true"
  }
}

function ImageRef([string]$serviceName) {
  return ("$acrLoginServer/$RepositoryPrefix/$serviceName" + ':' + $ImageTag)
}

# Internal services
Ensure-ContainerApp -ResourceGroup $resourceGroupName -EnvironmentName $environmentName -Name 'products'  -Image (ImageRef 'products')  -Ingress 'internal' -TargetPort 8080 -RegistryServer $acrLoginServer -RegistryUsername $acrUsername -RegistryPassword $acrPassword -HealthProbeType 'http' -HealthProbePort 8080 -HealthProbePath '/graphql'
Ensure-ContainerApp -ResourceGroup $resourceGroupName -EnvironmentName $environmentName -Name 'reviews'   -Image (ImageRef 'reviews')   -Ingress 'internal' -TargetPort 8080 -RegistryServer $acrLoginServer -RegistryUsername $acrUsername -RegistryPassword $acrPassword -HealthProbeType 'http' -HealthProbePort 8080 -HealthProbePath '/graphql'
Ensure-ContainerApp -ResourceGroup $resourceGroupName -EnvironmentName $environmentName -Name 'shipping'  -Image (ImageRef 'shipping')  -Ingress 'internal' -TargetPort 8080 -RegistryServer $acrLoginServer -RegistryUsername $acrUsername -RegistryPassword $acrPassword -HealthProbeType 'http' -HealthProbePort 8080 -HealthProbePath '/graphql'

# Orders + BackOffice need Postgres
$ordersSecrets = @()
$ordersEnv = @()
if ($postgresConnectionString) {
  $ordersSecrets = @("postgres-conn=$postgresConnectionString")
  $ordersEnv = @('ConnectionStrings__postgres=secretref:postgres-conn')
} else {
  Write-Warning "Postgres connection string not set; Orders/BackOffice may fail to start."
}

Ensure-ContainerApp -ResourceGroup $resourceGroupName -EnvironmentName $environmentName -Name 'orders'     -Image (ImageRef 'orders')     -Ingress 'internal' -TargetPort 8080 -RegistryServer $acrLoginServer -RegistryUsername $acrUsername -RegistryPassword $acrPassword -Secrets $ordersSecrets -EnvVars $ordersEnv
Ensure-ContainerApp -ResourceGroup $resourceGroupName -EnvironmentName $environmentName -Name 'backoffice' -Image (ImageRef 'backoffice') -Ingress 'internal' -TargetPort 8080 -RegistryServer $acrLoginServer -RegistryUsername $acrUsername -RegistryPassword $acrPassword -Secrets $ordersSecrets -EnvVars $ordersEnv

# Nitro Schema API (internal) is the source of truth + multicast WebSocket hub for gateway.fgp
$nitroAdminTokenPlain = $null
try {
  if (Test-Path $ParametersFile) {
    $params = (Get-Content -Raw $ParametersFile | ConvertFrom-Json)
    if ($params.parameters.nitroAdminToken.value) { $nitroAdminTokenPlain = [string]$params.parameters.nitroAdminToken.value }
  }
}
catch {
  Write-Warning "Could not parse ParametersFile '$ParametersFile' for nitroAdminToken."
}

if ([string]::IsNullOrWhiteSpace($nitroAdminTokenPlain)) {
  if (-not [string]::IsNullOrWhiteSpace($env:NITRO_ADMIN_TOKEN)) {
    $nitroAdminTokenPlain = [string]$env:NITRO_ADMIN_TOKEN
  }
}

if ([string]::IsNullOrWhiteSpace($nitroAdminTokenPlain)) {
  $secureNitro = Read-Host "Enter Nitro admin token (used to publish gateway.fgp)" -AsSecureString
  $nitroAdminTokenPlain = Get-PlainTextFromSecureString -Secure $secureNitro
}

$nitroSecrets = @()
$nitroEnv = @()
if ($postgresConnectionString) {
  $nitroSecrets = @(
    "postgres-conn=$postgresConnectionString",
    "nitro-admin-token=$nitroAdminTokenPlain"
  )
  $nitroEnv = @(
    'ConnectionStrings__postgres=secretref:postgres-conn',
    'NITRO_ADMIN_TOKEN=secretref:nitro-admin-token'
  )
} else {
  Write-Warning "Postgres connection string not set; nitro-schema-api will fail to start."
}

Ensure-ContainerApp -ResourceGroup $resourceGroupName -EnvironmentName $environmentName -Name 'nitro-schema-api' -Image (ImageRef 'nitro-schema-api') -Ingress 'internal' -TargetPort 8080 -RegistryServer $acrLoginServer -RegistryUsername $acrUsername -RegistryPassword $acrPassword -Secrets $nitroSecrets -EnvVars $nitroEnv

$nitroFqdn = az containerapp show -g $resourceGroupName -n nitro-schema-api --query properties.configuration.ingress.fqdn -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($nitroFqdn)) { throw "Failed to fetch nitro-schema-api FQDN" }

# External apps (create frontend first so we can set Gateway CORS correctly)
Ensure-ContainerApp -ResourceGroup $resourceGroupName -EnvironmentName $environmentName -Name 'frontend'  -Image (ImageRef 'frontend')  -Ingress 'external' -TargetPort 80   -RegistryServer $acrLoginServer -RegistryUsername $acrUsername -RegistryPassword $acrPassword -HealthProbeType 'http' -HealthProbePort 80 -HealthProbePath '/'

$frontendFqdn = az containerapp show -g $resourceGroupName -n frontend --query properties.configuration.ingress.fqdn -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($frontendFqdn)) { throw "Failed to fetch frontend FQDN" }

$gatewayCorsOrigins = @(
  "https://$frontendFqdn",
  'http://localhost:5173',
  'http://localhost:3000',
  'http://localhost:4999'
) -join ','

$gatewayEnv = @(
  "CORS_ALLOWED_ORIGINS=$gatewayCorsOrigins",
  "NITRO_SCHEMA_WS=ws://$nitroFqdn/ws",
  'NITRO_ADMIN_TOKEN=secretref:nitro-admin-token'
)

$gatewaySecrets = @(
  "nitro-admin-token=$nitroAdminTokenPlain"
)

Ensure-ContainerApp -ResourceGroup $resourceGroupName -EnvironmentName $environmentName -Name 'gateway'   -Image (ImageRef 'gateway')   -Ingress 'external' -TargetPort 8080 -RegistryServer $acrLoginServer -RegistryUsername $acrUsername -RegistryPassword $acrPassword -Secrets $gatewaySecrets -EnvVars $gatewayEnv -HealthProbeType 'http' -HealthProbePort 8080 -HealthProbePath '/graphql'

$gatewayFqdn = az containerapp show -g $resourceGroupName -n gateway --query properties.configuration.ingress.fqdn -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gatewayFqdn)) { throw "Failed to fetch gateway FQDN" }

# Now that Gateway is deployed, point the frontend runtime config at it.
$frontendEnv = @(
  "GRAPHQL_HTTP=https://$gatewayFqdn/graphql",
  "GRAPHQL_WS=wss://$gatewayFqdn/graphql"
)

Ensure-ContainerApp -ResourceGroup $resourceGroupName -EnvironmentName $environmentName -Name 'frontend'  -Image (ImageRef 'frontend')  -Ingress 'external' -TargetPort 80   -RegistryServer $acrLoginServer -RegistryUsername $acrUsername -RegistryPassword $acrPassword -EnvVars $frontendEnv

Write-Host ""
Write-Host "Done. Public endpoints:"
Write-Host "- Gateway:  https://$gatewayFqdn/graphql"
Write-Host "- Frontend: https://$frontendFqdn/"
