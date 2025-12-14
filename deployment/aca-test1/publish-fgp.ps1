[CmdletBinding()]
param(
  [ValidateSet('none','local','aca')][string]$Compose = 'none',
  [string]$GatewayStatusGraphQLEndpoint,
  [string]$Token,
  [string]$FgpPath,
  [string]$DeploymentName = 'alderaan-bootstrap',
  [string]$ParametersFile = $(Join-Path $PSScriptRoot 'main.parameters.json')
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

function Resolve-RepoRoot {
  $repoRoot = Split-Path -Parent $PSScriptRoot
  return (Split-Path -Parent $repoRoot) # deployment/aca-test1 -> repo root
}

function Resolve-FgpPath {
  param([string]$Path)
  if (-not [string]::IsNullOrWhiteSpace($Path)) { return $Path }
  $repoRoot = Resolve-RepoRoot
  return (Join-Path $repoRoot 'src\Gateway\gateway.fgp')
}

function Resolve-Token {
  param([string]$ExplicitToken)

  if (-not [string]::IsNullOrWhiteSpace($ExplicitToken)) { return $ExplicitToken }

  if (-not [string]::IsNullOrWhiteSpace($env:NITRO_ADMIN_TOKEN)) {
    return [string]$env:NITRO_ADMIN_TOKEN
  }

  # Optional: allow placing a token in main.parameters.json as parameters.nitroAdminToken.value
  if (Test-Path $ParametersFile) {
    try {
      $params = (Get-Content -Raw $ParametersFile | ConvertFrom-Json)
      $fromParams = $params.parameters.nitroAdminToken.value
      if (-not [string]::IsNullOrWhiteSpace($fromParams)) { return [string]$fromParams }
    }
    catch {
      Write-Warning "Could not parse ParametersFile '$ParametersFile' for nitroAdminToken."
    }
  }

  $secure = Read-Host 'Enter Nitro admin token' -AsSecureString
  return Get-PlainTextFromSecureString -Secure $secure
}

function Resolve-GatewayEndpoint {
  param([string]$Explicit, [string]$ComposeMode)

  if (-not [string]::IsNullOrWhiteSpace($Explicit)) { return $Explicit }

  if ($ComposeMode -eq 'local') {
    return 'http://localhost:5000/status/graphql'
  }

  # ACA: infer the public gateway fqdn from the deployment outputs
  $outputsJson = az deployment sub show --name $DeploymentName --query properties.outputs -o json
  if ([string]::IsNullOrWhiteSpace($outputsJson)) {
    throw "No outputs returned. Did you run deployment/aca-test1/provision.ps1 successfully?"
  }

  $outputs = $outputsJson | ConvertFrom-Json
  $rg = $outputs.resourcE_GROUP_NAME.value
  if ([string]::IsNullOrWhiteSpace($rg)) { throw "Missing resource group output (RESOURCE_GROUP_NAME)." }

  $gatewayFqdn = az containerapp show -g $rg -n gateway --query properties.configuration.ingress.fqdn -o tsv
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gatewayFqdn)) {
    throw "Failed to resolve gateway FQDN from Container Apps."
  }

  return "https://$gatewayFqdn/status/graphql"
}

function Compose-Local {
  $repoRoot = Resolve-RepoRoot
  $composeScript = Join-Path $repoRoot 'src\compose.ps1'
  if (-not (Test-Path $composeScript)) {
    throw "Local compose script not found: $composeScript"
  }

  Write-Host "Composing gateway.fgp for local..." -ForegroundColor Cyan
  & $composeScript
  if ($LASTEXITCODE -ne 0) { throw "Local compose failed" }
}

function Compose-Aca {
  $repoRoot = Resolve-RepoRoot
  $composeScript = Join-Path $repoRoot 'deployment\aca-test1\compose-gateway-fgp.ps1'
  if (-not (Test-Path $composeScript)) {
    throw "ACA compose script not found: $composeScript"
  }

  $outputsJson = az deployment sub show --name $DeploymentName --query properties.outputs -o json
  if ([string]::IsNullOrWhiteSpace($outputsJson)) {
    throw "No outputs returned. Did you run deployment/aca-test1/provision.ps1 successfully?"
  }

  $outputs = $outputsJson | ConvertFrom-Json
  $rg = $outputs.resourcE_GROUP_NAME.value
  if ([string]::IsNullOrWhiteSpace($rg)) { throw "Missing resource group output (RESOURCE_GROUP_NAME)." }

  Write-Host "Resolving internal subgraph FQDNs (ACA)..." -ForegroundColor Cyan
  $productsFqdn = az containerapp show -g $rg -n products --query properties.configuration.ingress.fqdn -o tsv
  $reviewsFqdn  = az containerapp show -g $rg -n reviews  --query properties.configuration.ingress.fqdn -o tsv
  $shippingFqdn = az containerapp show -g $rg -n shipping --query properties.configuration.ingress.fqdn -o tsv
  $ordersFqdn   = az containerapp show -g $rg -n orders   --query properties.configuration.ingress.fqdn -o tsv

  if ([string]::IsNullOrWhiteSpace($productsFqdn) -or [string]::IsNullOrWhiteSpace($reviewsFqdn) -or [string]::IsNullOrWhiteSpace($shippingFqdn) -or [string]::IsNullOrWhiteSpace($ordersFqdn)) {
    throw "Could not resolve one or more internal subgraph FQDNs (products/reviews/shipping/orders)."
  }

  Write-Host "Composing gateway.fgp for ACA..." -ForegroundColor Cyan
  & $composeScript -ProductsFqdn $productsFqdn -ReviewsFqdn $reviewsFqdn -ShippingFqdn $shippingFqdn -OrdersFqdn $ordersFqdn -Scheme 'https'
  if ($LASTEXITCODE -ne 0) { throw "ACA compose failed" }
}

function Publish-Fgp {
  param(
    [Parameter(Mandatory = $true)][string]$Endpoint,
    [Parameter(Mandatory = $true)][string]$FgpFile,
    [Parameter(Mandatory = $true)][string]$AdminToken
  )

  if (-not (Test-Path $FgpFile)) {
    throw "FGP file not found: $FgpFile"
  }

  $fgp = Get-Content -Raw -Path $FgpFile
  $fgpBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($fgp))

  $mutation = @'
mutation PublishGatewayFgp($fgpBase64: String!, $token: String!) {
  publishGatewayFgp(fgpBase64: $fgpBase64, token: $token)
}
'@

  $body = @{
    query = $mutation
    variables = @{
      fgpBase64 = $fgpBase64
      token = $AdminToken
    }
  } | ConvertTo-Json -Depth 10

  Write-Host "Publishing gateway.fgp to: $Endpoint" -ForegroundColor Cyan

  $resp = Invoke-RestMethod -Method Post -Uri $Endpoint -ContentType 'application/json' -Body $body

  if ($resp.errors) {
    $msg = ($resp.errors | ConvertTo-Json -Depth 10)
    throw "GraphQL publish failed: $msg"
  }

  Write-Host "Publish succeeded." -ForegroundColor Green
}

# ---- main ----
$FgpPath = Resolve-FgpPath -Path $FgpPath
$Token = Resolve-Token -ExplicitToken $Token

switch ($Compose) {
  'local' { Compose-Local }
  'aca'   { Compose-Aca }
  'none'  { }
  default { throw "Unknown Compose mode: $Compose" }
}

$GatewayStatusGraphQLEndpoint = Resolve-GatewayEndpoint -Explicit $GatewayStatusGraphQLEndpoint -ComposeMode $Compose
Publish-Fgp -Endpoint $GatewayStatusGraphQLEndpoint -FgpFile $FgpPath -AdminToken $Token

Write-Host "Done." -ForegroundColor Green

<##
Examples:

# Local (docker-compose): compose + publish
# Token defaults to env var NITRO_ADMIN_TOKEN or prompts
#   cd src
#   docker compose up -d
#   $env:NITRO_ADMIN_TOKEN = 'dev-token'
#   cd ..\deployment\aca-test1
#   .\publish-fgp.ps1 -Compose local

# ACA: compose using internal FQDNs + publish to public gateway
#   $env:NITRO_ADMIN_TOKEN = '<your token>'
#   .\publish-fgp.ps1 -Compose aca

# Publish only (no compose), custom endpoint
#   .\publish-fgp.ps1 -Compose none -GatewayStatusGraphQLEndpoint 'https://<gateway>/status/graphql' -FgpPath 'c:\path\to\gateway.fgp'
##> 
