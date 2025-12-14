#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Composes a fresh gateway.fgp with correct service URLs for the target environment.

.DESCRIPTION
    This script uses existing schema files from the schemas/ folder and generates
    a new gateway.fgp with URLs appropriate for the target environment:
    
    - 'local': Uses Docker Compose internal DNS (http://products:8080/graphql)
    - 'aca': Queries Azure Container Apps to get actual FQDNs
    
    The script uses HotChocolate Fusion CLI to pack subgraphs and compose the FGP.

.PARAMETER Environment
    Target environment: 'local' for Docker Compose, 'aca' for Azure Container Apps.

.PARAMETER ResourceGroup
    Azure resource group name (required for 'aca' environment). Default: alderaan

.PARAMETER GatewayUrl
    Override gateway publish endpoint URL.

.PARAMETER Token
    Admin token for publish authentication.

.PARAMETER SkipPublish
    Only compose the FGP, don't publish it.

.PARAMETER OutputPath
    Custom output path for gateway.fgp. Default: Gateway/gateway.fgp

.EXAMPLE
    # Compose for local Docker Compose and publish
    .\compose-fgp.ps1 -Environment local

.EXAMPLE
    # Compose for ACA and publish
    .\compose-fgp.ps1 -Environment aca -ResourceGroup alderaan

.EXAMPLE
    # Just compose for local, don't publish
    .\compose-fgp.ps1 -Environment local -SkipPublish

.EXAMPLE
    # Compose for ACA with custom token
    .\compose-fgp.ps1 -Environment aca -ResourceGroup alderaan -Token "my-secret-token"
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('local', 'aca')]
    [string]$Environment,

    [string]$ResourceGroup = 'alderaan',

    [string]$GatewayUrl = $null,

    [string]$Token = $null,

    [switch]$SkipPublish,

    [string]$OutputPath = $null
)

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

$schemasDir = Join-Path $PSScriptRoot 'schemas'
$workDir = Join-Path $PSScriptRoot '.fusion-work'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = [System.IO.Path]::Combine($PSScriptRoot, 'Gateway', 'gateway.fgp')
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    $Token = $env:NITRO_ADMIN_TOKEN
    if ([string]::IsNullOrWhiteSpace($Token)) {
        $Token = 'dev-token'
    }
}

# Subgraphs to include
$subgraphs = @(
    @{ Name = 'Products'; Schema = 'products.graphql' },
    @{ Name = 'Reviews'; Schema = 'reviews.graphql' },
    @{ Name = 'Shipping'; Schema = 'shipping.graphql' },
    @{ Name = 'Orders'; Schema = 'orders.graphql' },
    @{ Name = 'Status'; Schema = 'status.graphql' }
)

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

function Get-LocalUrl {
    param([string]$SubgraphName)
    
    $name = $SubgraphName.ToLower()
    if ($name -eq 'status') {
        return 'http://localhost:8080/status/graphql'
    }
    return "http://${name}:8080/graphql"
}

function Get-AcaUrl {
    param(
        [string]$SubgraphName,
        [string]$ResourceGroup
    )
    
    $name = $SubgraphName.ToLower()
    
    if ($name -eq 'status') {
        return 'http://localhost:8080/status/graphql'
    }
    
    Write-Host "    Querying ACA for '$name'..." -ForegroundColor Gray
    
    $fqdn = az containerapp show `
        --name $name `
        --resource-group $ResourceGroup `
        --query "properties.configuration.ingress.fqdn" `
        --output tsv 2>$null
    
    if ([string]::IsNullOrWhiteSpace($fqdn)) {
        throw "Container app '$name' not found in resource group '$ResourceGroup'"
    }
    
    # Check if external or internal
    $isExternal = az containerapp show `
        --name $name `
        --resource-group $ResourceGroup `
        --query "properties.configuration.ingress.external" `
        --output tsv 2>$null
    
    # Internal services are accessed via http within the environment
    if ($isExternal -eq 'true') {
        return "https://${fqdn}/graphql"
    }
    else {
        return "http://${fqdn}/graphql"
    }
}

function Get-GatewayPublishUrl {
    param([string]$ResourceGroup)
    
    Write-Host "    Querying gateway URL..." -ForegroundColor Gray
    
    $fqdn = az containerapp show `
        --name 'gateway' `
        --resource-group $ResourceGroup `
        --query "properties.configuration.ingress.fqdn" `
        --output tsv 2>$null
    
    if ([string]::IsNullOrWhiteSpace($fqdn)) {
        throw "Gateway container app not found in resource group '$ResourceGroup'"
    }
    
    return "https://${fqdn}/status/graphql"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  Fusion Gateway Package Composer" -ForegroundColor Cyan  
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Environment:  $Environment" -ForegroundColor Yellow
Write-Host "Output:       $OutputPath" -ForegroundColor Yellow
Write-Host ""

# Verify Fusion CLI
$fusionVersion = fusion --version 2>$null
if (-not $fusionVersion) {
    Write-Host "Installing HotChocolate Fusion CLI..." -ForegroundColor Yellow
    dotnet tool install --global HotChocolate.Fusion.CommandLine --prerelease
    $fusionVersion = fusion --version
}
Write-Host "Fusion CLI:   $fusionVersion" -ForegroundColor Gray
Write-Host ""

# Clean work directory
if (Test-Path $workDir) {
    Remove-Item -Recurse -Force $workDir
}
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

# Determine gateway publish URL
if ([string]::IsNullOrWhiteSpace($GatewayUrl)) {
    if ($Environment -eq 'local') {
        $GatewayUrl = 'http://localhost:5000/status/graphql'
    }
    else {
        $GatewayUrl = Get-GatewayPublishUrl -ResourceGroup $ResourceGroup
    }
}

Write-Host "Gateway URL:  $GatewayUrl" -ForegroundColor Yellow
Write-Host ""

# Step 1: Build subgraph packages with correct URLs
Write-Host "Step 1: Building subgraph packages..." -ForegroundColor Cyan

$fspFiles = @()

foreach ($sg in $subgraphs) {
    $name = $sg.Name
    $schemaFile = $sg.Schema
    
    Write-Host "  [$name]" -ForegroundColor White
    
    # Get URL for this environment
    if ($Environment -eq 'local') {
        $url = Get-LocalUrl -SubgraphName $name
    }
    else {
        $url = Get-AcaUrl -SubgraphName $name -ResourceGroup $ResourceGroup
    }
    
    Write-Host "    URL: $url" -ForegroundColor Green
    
    # Create subgraph work directory
    $sgWorkDir = Join-Path $workDir $name
    New-Item -ItemType Directory -Path $sgWorkDir -Force | Out-Null
    
    # Copy schema file
    $sourceSchema = Join-Path $schemasDir $schemaFile
    if (-not (Test-Path $sourceSchema)) {
        throw "Schema file not found: $sourceSchema"
    }
    
    $destSchema = Join-Path $sgWorkDir 'schema.graphql'
    Copy-Item -Path $sourceSchema -Destination $destSchema
    
    # Create subgraph-config.json with correct URL
    $config = @{
        subgraph = $name
        http = @{
            baseAddress = $url
        }
    }
    
    $configPath = Join-Path $sgWorkDir 'subgraph-config.json'
    $config | ConvertTo-Json -Depth 4 | Set-Content -Path $configPath -Encoding UTF8
    
    # Pack subgraph
    Write-Host "    Packing..." -ForegroundColor Gray
    
    $fspPath = Join-Path $sgWorkDir "$name.fsp"
    
    $packOutput = fusion subgraph pack -s $destSchema -c $configPath -p $fspPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    Warning: $packOutput" -ForegroundColor Yellow
    }
    
    # Find the .fsp file
    $fspFile = Get-ChildItem -Path $sgWorkDir -Filter "*.fsp" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($fspFile) {
        $fspFiles += $fspFile.FullName
        Write-Host "    Created: $($fspFile.Name)" -ForegroundColor Gray
    }
    else {
        throw "Failed to create .fsp for $name"
    }
}

Write-Host ""
Write-Host "  Packed $($fspFiles.Count) subgraphs" -ForegroundColor Green
Write-Host ""

# Step 2: Compose gateway package
Write-Host "Step 2: Composing gateway.fgp..." -ForegroundColor Cyan

$composeArgs = @('compose', '-p', $OutputPath)
foreach ($fsp in $fspFiles) {
    $composeArgs += '-s'
    $composeArgs += $fsp
}

Write-Host "  Running: fusion $($composeArgs -join ' ')" -ForegroundColor Gray

$composeOutput = & fusion $composeArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Compose failed:" -ForegroundColor Red
    Write-Host $composeOutput
    exit 1
}

if (Test-Path $OutputPath) {
    $fgpSize = (Get-Item $OutputPath).Length
    Write-Host "  Created: $OutputPath" -ForegroundColor Green
    Write-Host "  Size: $fgpSize bytes" -ForegroundColor Gray
}
else {
    Write-Host "  Failed to create gateway.fgp" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 3: Publish (optional)
if ($SkipPublish) {
    Write-Host "Step 3: Skipping publish (-SkipPublish)" -ForegroundColor Yellow
}
else {
    Write-Host "Step 3: Publishing to gateway..." -ForegroundColor Cyan
    Write-Host "  Endpoint: $GatewayUrl" -ForegroundColor Gray
    Write-Host ""
    
    & "$PSScriptRoot\publish-fgp.ps1" `
        -GatewayGraphQlUrl $GatewayUrl `
        -FgpPath $OutputPath `
        -Token $Token
}

# Cleanup
Write-Host ""
Write-Host "Cleaning up..." -ForegroundColor Gray
Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host ""

# Summary
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Environment: $Environment"
Write-Host "  FGP: $OutputPath"
Write-Host "  Subgraphs: $($subgraphs.Count)"
if (-not $SkipPublish) {
    Write-Host "  Published to: $GatewayUrl"
}
Write-Host ""
