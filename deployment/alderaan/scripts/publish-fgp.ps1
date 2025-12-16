#!/usr/bin/env pwsh
# ============================================================================
# Compose and Publish FGP Script
# Wrapper for src/compose-fgp.ps1 with azd integration
# ============================================================================

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('local', 'aca')]
    [string]$Environment = 'aca',
    
    [Parameter(Mandatory = $false)]
    [string]$Token,
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Get resource group from azd if not provided
if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    $ResourceGroup = azd env get-value AZURE_RESOURCE_GROUP 2>$null
}
$envToken = azd env get-value NITRO_ADMIN_TOKEN 2>$null

if ([string]::IsNullOrWhiteSpace($Token) -and -not [string]::IsNullOrWhiteSpace($envToken)) {
    $Token = $envToken
}

Write-Host "--------------------------------------------------" -ForegroundColor Cyan
Write-Host "          Compose & Publish Gateway FGP           " -ForegroundColor Cyan
Write-Host "--------------------------------------------------" -ForegroundColor Cyan
Write-Host ""

# Find repo root
$alderaanDir = Split-Path -Parent $PSScriptRoot
$deploymentDir = Split-Path -Parent $alderaanDir
$repoRoot = Split-Path -Parent $deploymentDir
$srcDir = Join-Path $repoRoot "src"

$composeFgpScript = Join-Path $srcDir "compose-fgp.ps1"

if (-not (Test-Path $composeFgpScript)) {
    Write-Host "[X] compose-fgp.ps1 not found at: $composeFgpScript" -ForegroundColor Red
    exit 1
}

Push-Location $srcDir
try {
    $params = @{
        Environment = $Environment
    }
    
    if (-not [string]::IsNullOrWhiteSpace($resourceGroup)) {
        $params["ResourceGroup"] = $resourceGroup
    }
    
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $params["Token"] = $Token
    }
    
    if ($DryRun) {
        $params["DryRun"] = $true
    }
    
    & $composeFgpScript @params
}
finally {
    Pop-Location
}
