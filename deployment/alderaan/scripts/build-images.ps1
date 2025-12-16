#!/usr/bin/env pwsh
# ============================================================================
# Build and Push Images Script
# Builds Docker images and pushes to ACR
# ============================================================================

param(
    [Parameter(Mandatory = $false)]
    [string]$Environment = $env:AZURE_ENV_NAME,
    
    [Parameter(Mandatory = $false)]
    [string]$ImageTag = "latest",
    
    [Parameter(Mandatory = $false)]
    [string]$Services = "",  # Comma-separated list of services to build (empty = all)
    
    [switch]$AlsoTagTimestamp,
    [switch]$SkipBuild,
    [switch]$ListOnly,  # Just list discovered services, don't build

    [Parameter(Mandatory = $false)]
    [string]$AcrName = $env:AZURE_CONTAINER_REGISTRY_NAME,

    [Parameter(Mandatory = $false)]
    [string]$AcrLoginServer = $env:AZURE_CONTAINER_REGISTRY_ENDPOINT
)

$ErrorActionPreference = 'Stop'

# Get ACR info from azd if not provided
if ([string]::IsNullOrWhiteSpace($AcrLoginServer) -or [string]::IsNullOrWhiteSpace($AcrName)) {
    $AcrLoginServer = azd env get-value AZURE_CONTAINER_REGISTRY_ENDPOINT 2>$null
    $AcrName = azd env get-value AZURE_CONTAINER_REGISTRY_NAME 2>$null
}

if ([string]::IsNullOrWhiteSpace($AcrLoginServer) -or [string]::IsNullOrWhiteSpace($AcrName)) {
    Write-Host "[X] ACR not found. Provide parameters, set env vars, or run 'azd provision'." -ForegroundColor Red
    exit 1
}

$timestampTag = "v$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))"
$repositoryPrefix = "graphql-gateway"

Write-Host "+------------------------------------------------------------------+" -ForegroundColor Cyan
Write-Host "|                    Build and Push Images                         |" -ForegroundColor Cyan
Write-Host "+------------------------------------------------------------------+" -ForegroundColor Cyan
Write-Host ""
Write-Host "ACR: $acrLoginServer" -ForegroundColor Gray
Write-Host "Tag: $ImageTag" -ForegroundColor Gray
if ($AlsoTagTimestamp) {
    Write-Host "Timestamp Tag: $timestampTag" -ForegroundColor Gray
}
Write-Host ""

# Login to ACR
Write-Host "[Auth] Logging into ACR..." -ForegroundColor Yellow
az acr login --name $acrName | Out-Host
if ($LASTEXITCODE -ne 0) { throw "ACR login failed" }

# Find repo root
$scriptDir = Split-Path -Parent $PSScriptRoot
$deploymentDir = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent $deploymentDir
$srcDir = Join-Path $repoRoot "src"

# ============================================================================
# Auto-discover .NET services by scanning for Dockerfiles in src/
# ============================================================================
function Get-ServiceNameFromDirectory {
    param([string]$DirectoryName)
    
    # Convert PascalCase directory names to kebab-case service names
    # e.g., "ProductsService" -> "products", "NitroSchemaApi" -> "nitro-schema-api"
    $name = $DirectoryName -replace 'Service$', ''  # Remove "Service" suffix
    $name = $name -replace 'Api$', '-api'           # Convert "Api" suffix
    
    # Insert hyphens before capitals and lowercase everything
    $name = ($name -creplace '([A-Z])', '-$1').TrimStart('-').ToLower()
    
    # Clean up double hyphens
    $name = $name -replace '--', '-'
    
    return $name
}

Write-Host "[Search] Discovering services from src/ directory..." -ForegroundColor Yellow

$dotnetServices = @()
$discoveredDirs = Get-ChildItem -Path $srcDir -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName "Dockerfile")
}

foreach ($dir in $discoveredDirs) {
    $serviceName = Get-ServiceNameFromDirectory -DirectoryName $dir.Name
    $dockerfile = "$($dir.Name)/Dockerfile"
    
    $dotnetServices += @{
        Name = $serviceName
        Dockerfile = $dockerfile
        Directory = $dir.Name
    }
    
    Write-Host "   Found: $($dir.Name) -> $serviceName" -ForegroundColor Gray
}

if ($dotnetServices.Count -eq 0) {
    Write-Host "[X] No services with Dockerfiles found in src/" -ForegroundColor Red
    exit 1
}

Write-Host "   Discovered $($dotnetServices.Count) .NET services" -ForegroundColor Green
Write-Host ""

# Filter services if -Services parameter provided
if (-not [string]::IsNullOrWhiteSpace($Services)) {
    $serviceFilter = $Services.Split(',') | ForEach-Object { $_.Trim().ToLower() }
    $dotnetServices = $dotnetServices | Where-Object { $serviceFilter -contains $_.Name }
    
    if ($dotnetServices.Count -eq 0) {
        Write-Host "[X] No matching services found for filter: $Services" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "[Filter] Filtered to $($dotnetServices.Count) service(s): $($dotnetServices.Name -join ', ')" -ForegroundColor Yellow
    Write-Host ""
}

# List-only mode
if ($ListOnly) {
    Write-Host "[List] Discovered Services:" -ForegroundColor Cyan
    foreach ($svc in $dotnetServices) {
        Write-Host "   $($svc.Name) <- $($svc.Directory)/Dockerfile" -ForegroundColor White
    }
    
    # Check for frontend
    $frontendDir = Join-Path $repoRoot "frontend"
    if (Test-Path (Join-Path $frontendDir "Dockerfile")) {
        Write-Host "   frontend <- frontend/Dockerfile" -ForegroundColor White
    }
    exit 0
}

function Build-AndPush {
    param(
        [string]$ServiceName,
        [string]$Dockerfile,
        [string]$Context
    )
    
    $image = "$acrLoginServer/$repositoryPrefix/${ServiceName}:$ImageTag"
    Write-Host ""
    Write-Host "[Build] Building $ServiceName..." -ForegroundColor Yellow
    Write-Host "   Image: $image" -ForegroundColor Gray
    
    if (-not $SkipBuild) {
        docker build -t $image -f $Dockerfile $Context
        if ($LASTEXITCODE -ne 0) { throw "docker build failed for $ServiceName" }
    }
    
    Write-Host "[Push] Pushing $ServiceName..." -ForegroundColor Yellow
    docker push $image
    if ($LASTEXITCODE -ne 0) { throw "docker push failed for $ServiceName" }
    
    if ($AlsoTagTimestamp) {
        $timestampImage = "$acrLoginServer/$repositoryPrefix/${ServiceName}:$timestampTag"
        docker tag $image $timestampImage
        docker push $timestampImage
        if ($LASTEXITCODE -ne 0) { throw "docker push failed for $ServiceName (timestamp tag)" }
    }
    
    Write-Host "   [OK] Done" -ForegroundColor Green
}

# Build .NET services
$srcDir = Join-Path $repoRoot "src"
Push-Location $srcDir
try {
    foreach ($svc in $dotnetServices) {
        Build-AndPush -ServiceName $svc.Name -Dockerfile $svc.Dockerfile -Context "."
    }
}
finally {
    Pop-Location
}

# Build Frontend
$frontendDir = Join-Path $repoRoot "frontend"
if (Test-Path $frontendDir) {
    Push-Location $frontendDir
    try {
        Build-AndPush -ServiceName "frontend" -Dockerfile "Dockerfile" -Context "."
    }
    finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "+------------------------------------------------------------------+" -ForegroundColor Green
Write-Host "|                    All Images Pushed!                            |" -ForegroundColor Green
Write-Host "+------------------------------------------------------------------+" -ForegroundColor Green
Write-Host ""
Write-Host "To deploy, run: azd deploy" -ForegroundColor Cyan
Write-Host ""
