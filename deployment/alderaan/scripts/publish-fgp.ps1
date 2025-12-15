#!/usr/bin/env pwsh
# ============================================================================
# Compose and Publish FGP Script
# Wrapper for src/compose-fgp.ps1 with azd integration
# ============================================================================

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('local', 'aca')]
    [string]$Environment = 'aca',
    
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Get resource group from azd
$resourceGroup = azd env get-value AZURE_RESOURCE_GROUP 2>$null

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║               Compose & Publish Gateway FGP                  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Find repo root
$scriptDir = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $scriptDir
$srcDir = Join-Path $repoRoot "src"

$composeFgpScript = Join-Path $srcDir "compose-fgp.ps1"

if (-not (Test-Path $composeFgpScript)) {
    Write-Host "❌ compose-fgp.ps1 not found at: $composeFgpScript" -ForegroundColor Red
    exit 1
}

Push-Location $srcDir
try {
    $params = @('-Environment', $Environment)
    
    if (-not [string]::IsNullOrWhiteSpace($resourceGroup)) {
        $params += @('-ResourceGroup', $resourceGroup)
    }
    
    if ($DryRun) {
        $params += '-DryRun'
    }
    
    & $composeFgpScript @params
}
finally {
    Pop-Location
}
