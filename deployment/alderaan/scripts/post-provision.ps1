#!/usr/bin/env pwsh
# ============================================================================
# Post-Provision Script
# Runs after azd provision to compose and publish FGP schema
# ============================================================================

param(
    [string]$Environment = $env:AZURE_ENV_NAME,
    [string]$ResourceGroup = $env:AZURE_RESOURCE_GROUP,
    [switch]$SkipFgpPublish
)

$ErrorActionPreference = 'Stop'

Write-Host "+------------------------------------------------------------------+" -ForegroundColor Cyan
Write-Host "|              Post-Provision: GraphQL Gateway                     |" -ForegroundColor Cyan
Write-Host "+------------------------------------------------------------------+" -ForegroundColor Cyan
Write-Host ""

# Get deployment outputs from azd
Write-Host "[>] Reading deployment outputs..." -ForegroundColor Yellow

$gatewayUrl = azd env get-value GATEWAY_URL 2>$null
$frontendUrl = azd env get-value FRONTEND_URL 2>$null
$nitroWsUrl = azd env get-value NITRO_WS_URL 2>$null
$nitroFqdn = azd env get-value NITRO_INTERNAL_FQDN 2>$null
$nitroAdminToken = azd env get-value NITRO_ADMIN_TOKEN 2>$null

Write-Host ""
Write-Host "[>] Deployed Endpoints:" -ForegroundColor Green
Write-Host "   Gateway:  $gatewayUrl"
Write-Host "   Frontend: $frontendUrl"
Write-Host "   Nitro WS: $nitroWsUrl"
Write-Host ""

if ($SkipFgpPublish) {
    Write-Host "[Skip] Skipping FGP publish (--skip-fgp-publish flag)" -ForegroundColor Yellow
    exit 0
}

# Check if Nitro is available
if ([string]::IsNullOrWhiteSpace($nitroFqdn)) {
    Write-Host "[!] NITRO_INTERNAL_FQDN not set, skipping FGP publish" -ForegroundColor Yellow
    Write-Host "   You can manually publish later with: src/compose-fgp.ps1 -Environment aca" -ForegroundColor Gray
    exit 0
}

# Wait for Container Apps to stabilize
Write-Host "[Wait] Waiting 45 seconds for Container Apps to stabilize..." -ForegroundColor Yellow
Start-Sleep -Seconds 45

# Navigate to src directory
$scriptDir = Split-Path -Parent $PSScriptRoot
$deploymentDir = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent $deploymentDir
$srcDir = Join-Path $repoRoot "src"

if (-not (Test-Path $srcDir)) {
    Write-Host "[X] Cannot find src directory at: $srcDir" -ForegroundColor Red
    exit 1
}

Push-Location $srcDir

try {
    # Check for compose-fgp.ps1
    $composeFgpScript = Join-Path $srcDir "compose-fgp.ps1"
    if (-not (Test-Path $composeFgpScript)) {
        Write-Host "[X] compose-fgp.ps1 not found at: $composeFgpScript" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "[>] Composing and publishing FGP schema..." -ForegroundColor Yellow
    Write-Host ""

    # Determine parameters
    $params = @{
        Environment = 'aca'
        Token = $nitroAdminToken
    }
    
    if (-not [string]::IsNullOrWhiteSpace($ResourceGroup)) {
        Write-Host "    Target Resource Group: $ResourceGroup" -ForegroundColor Gray
        $params['ResourceGroup'] = $ResourceGroup
    } else {
        Write-Host "    Target Resource Group: (default)" -ForegroundColor Gray
    }

    # Run compose-fgp.ps1
    Write-Host "    Running: compose-fgp.ps1 -Environment aca -ResourceGroup $ResourceGroup ..." -ForegroundColor DarkGray
    & $composeFgpScript @params

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] FGP compose/publish failed!" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "[OK] FGP schema published successfully!" -ForegroundColor Green
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "+------------------------------------------------------------------+" -ForegroundColor Green
Write-Host "|                    Deployment Complete!                          |" -ForegroundColor Green
Write-Host "+------------------------------------------------------------------+" -ForegroundColor Green
Write-Host ""
Write-Host "[>] Your GraphQL Gateway is ready at:" -ForegroundColor Cyan
Write-Host "   $gatewayUrl" -ForegroundColor White
Write-Host ""
Write-Host "[>] Frontend available at:" -ForegroundColor Cyan
Write-Host "   $frontendUrl" -ForegroundColor White
Write-Host ""
