param(
  [string]$GatewayGraphQlUrl = 'http://localhost:5000/status/graphql',
  [string]$FgpPath = $null,
  [string]$Token = $env:NITRO_ADMIN_TOKEN
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($FgpPath)) {
  $FgpPath = [System.IO.Path]::Combine($PSScriptRoot, 'Gateway', 'gateway.fgp')
}

if ([string]::IsNullOrWhiteSpace($Token)) {
  $Token = 'dev-token'
}

if (-not (Test-Path $FgpPath)) {
  throw "FGP file not found: $FgpPath"
}

$fgpBytes = [System.IO.File]::ReadAllBytes($FgpPath)
$fgpBase64 = [Convert]::ToBase64String($fgpBytes)

$payload = @{
  query = 'mutation Publish($fgpBase64: String!, $token: String!) { publishGatewayFgp(fgpBase64: $fgpBase64, token: $token) }'
  variables = @{
    fgpBase64 = $fgpBase64
    token = $Token
  }
}

$json = $payload | ConvertTo-Json -Depth 6

Write-Host "Publishing $(($fgpBytes.Length)) bytes to $GatewayGraphQlUrl" -ForegroundColor Cyan

try {
  $resp = Invoke-RestMethod -Method Post -Uri $GatewayGraphQlUrl -ContentType 'application/json' -Body $json
}
catch {
  Write-Host "Request failed" -ForegroundColor Red
  throw
}

if ($resp.errors) {
  Write-Host "GraphQL errors:" -ForegroundColor Red
  $resp.errors | ConvertTo-Json -Depth 10 | Write-Host
  exit 1
}

Write-Host "Publish request accepted." -ForegroundColor Green
$resp | ConvertTo-Json -Depth 10 | Write-Host
