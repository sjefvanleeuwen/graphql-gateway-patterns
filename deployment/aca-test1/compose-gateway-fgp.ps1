param(
  [Parameter(Mandatory = $true)][string]$ProductsFqdn,
  [Parameter(Mandatory = $true)][string]$ReviewsFqdn,
  [Parameter(Mandatory = $true)][string]$ShippingFqdn,
  [Parameter(Mandatory = $true)][string]$OrdersFqdn,
  [ValidateSet('https','http')][string]$Scheme = 'https'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $repoRoot  # ...\deployment\aca-test1 -> repo root
$srcRoot = Join-Path $repoRoot 'src'
$schemasDir = Join-Path $srcRoot 'schemas'

if (-not (Test-Path $srcRoot)) { throw "src directory not found at $srcRoot" }
if (-not (Test-Path $schemasDir)) { throw "schemas directory not found at $schemasDir" }

function Write-SubgraphConfig {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Subgraph,
    [Parameter(Mandatory = $true)][string]$BaseAddress
  )

  $obj = @{
    subgraph = $Subgraph
    http = @{ baseAddress = $BaseAddress }
  }

  ($obj | ConvertTo-Json -Depth 5) | Set-Content -Path $Path -Encoding UTF8
}

$productsBase = "${Scheme}://$ProductsFqdn/graphql"
$reviewsBase = "${Scheme}://$ReviewsFqdn/graphql"
$shippingBase = "${Scheme}://$ShippingFqdn/graphql"
$ordersBase = "${Scheme}://$OrdersFqdn/graphql"

Write-Host "Composing gateway.fgp for ACA with subgraph endpoints:" 
Write-Host "- Products:  $productsBase"
Write-Host "- Reviews:   $reviewsBase"
Write-Host "- Shipping:  $shippingBase"
Write-Host "- Orders:    $ordersBase"

$configProducts = Join-Path $schemasDir 'products-config.aca.json'
$configReviews  = Join-Path $schemasDir 'reviews-config.aca.json'
$configShipping = Join-Path $schemasDir 'shipping-config.aca.json'
$configOrders   = Join-Path $schemasDir 'orders-config.aca.json'

Write-SubgraphConfig -Path $configProducts -Subgraph 'Products' -BaseAddress $productsBase
Write-SubgraphConfig -Path $configReviews  -Subgraph 'Reviews'  -BaseAddress $reviewsBase
Write-SubgraphConfig -Path $configShipping -Subgraph 'Shipping' -BaseAddress $shippingBase
Write-SubgraphConfig -Path $configOrders   -Subgraph 'Orders'   -BaseAddress $ordersBase

Push-Location $srcRoot
try {
  Write-Host "Restoring dotnet tools (fusion CLI)..."
  dotnet tool restore | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "dotnet tool restore failed" }

  Write-Host "Packing subgraphs..."
  dotnet fusion subgraph pack -w . -s schemas/products.graphql -c schemas/products-config.aca.json -p schemas/products.fsp | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "fusion subgraph pack failed (Products)" }

  dotnet fusion subgraph pack -w . -s schemas/reviews.graphql  -c schemas/reviews-config.aca.json  -p schemas/reviews.fsp  | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "fusion subgraph pack failed (Reviews)" }

  dotnet fusion subgraph pack -w . -s schemas/shipping.graphql -c schemas/shipping-config.aca.json -p schemas/shipping.fsp | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "fusion subgraph pack failed (Shipping)" }

  dotnet fusion subgraph pack -w . -s schemas/orders.graphql   -c schemas/orders-config.aca.json   -p schemas/orders.fsp   | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "fusion subgraph pack failed (Orders)" }

  dotnet fusion subgraph pack -w . -s schemas/status.graphql   -c schemas/status-config.json       -p schemas/status.fsp   | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "fusion subgraph pack failed (Status)" }

  Write-Host "Composing gateway.fgp..."
  dotnet fusion compose -p Gateway/gateway.fgp -s schemas/products.fsp -s schemas/reviews.fsp -s schemas/shipping.fsp -s schemas/orders.fsp -s schemas/status.fsp | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "fusion compose failed" }

  Write-Host "Gateway configuration generated at src/Gateway/gateway.fgp"
}
finally {
  Pop-Location
}
