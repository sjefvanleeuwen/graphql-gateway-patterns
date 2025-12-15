#!/usr/bin/env pwsh
# ============================================================================
# Deploy Everything - Full Deployment Orchestrator
# ============================================================================
# This script deploys the entire GraphQL Gateway stack in the correct sequence:
#   1. Validate prerequisites
#   2. Initialize azd environment
#   3. Provision infrastructure (Bicep)
#   4. Build and push Docker images
#   5. Deploy Container Apps
#   6. Compose and publish FGP schema
# ============================================================================

param(
    [Parameter(Mandatory = $false)]
    [string]$Environment = "",
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "northeurope",
    
    [Parameter(Mandatory = $false)]
    [string]$PostgresPassword = "",
    
    [Parameter(Mandatory = $false)]
    [string]$NitroAdminToken = "",
    
    [Parameter(Mandatory = $false)]
    [string]$ImageTag = "latest",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$ParameterSet = "dev",
    
    [switch]$SkipLogin,
    [switch]$SkipProvision,
    [switch]$SkipBuild,
    [switch]$SkipDeploy,
    [switch]$SkipFgpPublish,
    [switch]$Force  # Skip confirmations
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = $PSScriptRoot

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Banner {
    param([string]$Text, [string]$Color = "Cyan")
    $width = 66
    $padding = [math]::Max(0, ($width - $Text.Length - 2) / 2)
    $leftPad = " " * [math]::Floor($padding)
    $rightPad = " " * [math]::Ceiling($padding)
    
    Write-Host ("+" + ("-" * $width) + "+") -ForegroundColor $Color
    Write-Host ("|$leftPad$Text$rightPad|") -ForegroundColor $Color
    Write-Host ("+" + ("-" * $width) + "+") -ForegroundColor $Color
}

function Write-Step {
    param([int]$Number, [string]$Text)
    Write-Host ""
    Write-Host "[$Number/6] $Text" -ForegroundColor Yellow
    Write-Host ("-" * 50) -ForegroundColor DarkGray
}

function Test-Command {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

function Get-SecureInput {
    param([string]$Prompt)
    $secure = Read-Host $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

# ============================================================================
# Main Script
# ============================================================================

Write-Banner "GraphQL Gateway - Full Deployment"
Write-Host ""
$envDisplay = if ([string]::IsNullOrWhiteSpace($Environment)) { '(will prompt)' } else { $Environment }
Write-Host "  Environment: $envDisplay" -ForegroundColor Gray
Write-Host "  Location:    $Location" -ForegroundColor Gray
Write-Host "  Parameters:  $ParameterSet" -ForegroundColor Gray
Write-Host "  Image Tag:   $ImageTag" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# Step 0: Validate Prerequisites
# ============================================================================

Write-Step 0 "Validating Prerequisites"

$prerequisites = @(
    @{ Name = 'az'; DisplayName = 'Azure CLI' }
    @{ Name = 'azd'; DisplayName = 'Azure Developer CLI' }
    @{ Name = 'docker'; DisplayName = 'Docker' }
    @{ Name = 'dotnet'; DisplayName = '.NET SDK' }
)

$missingTools = @()
foreach ($tool in $prerequisites) {
    if (Test-Command $tool.Name) {
        Write-Host "  [OK] $($tool.DisplayName)" -ForegroundColor Green
    } else {
        Write-Host "  [X] $($tool.DisplayName) - NOT FOUND" -ForegroundColor Red
        $missingTools += $tool.DisplayName
    }
}

# Check for Fusion CLI
$fusionInstalled = dotnet tool list -g | Select-String -Pattern "fusioncli" -Quiet
if ($fusionInstalled) {
    Write-Host "  [OK] Fusion CLI" -ForegroundColor Green
} else {
    Write-Host "  [!] Fusion CLI - not installed (will install later)" -ForegroundColor Yellow
}

if ($missingTools.Count -gt 0) {
    Write-Host ""
    Write-Host "[X] Missing required tools: $($missingTools -join ', ')" -ForegroundColor Red
    Write-Host "    Please install them and try again." -ForegroundColor Red
    exit 1
}

# Check Docker is running
$dockerRunning = docker info 2>&1 | Select-String -Pattern "Server Version" -Quiet
if (-not $dockerRunning) {
    Write-Host ""
    Write-Host "[X] Docker is not running. Please start Docker Desktop." -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Docker is running" -ForegroundColor Green

# ============================================================================
# Step 1: Azure Login and Environment Setup
# ============================================================================

Write-Step 1 "Azure Authentication and Environment"

if (-not $SkipLogin) {
    # Check if already logged in
    $account = az account show 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Logging into Azure..." -ForegroundColor Yellow
        az login
        if ($LASTEXITCODE -ne 0) { throw "Azure login failed" }
    } else {
        $accountInfo = $account | ConvertFrom-Json
        Write-Host "  [OK] Already logged in as: $($accountInfo.user.name)" -ForegroundColor Green
    }
    
    # azd auth
    Write-Host "  Authenticating azd..." -ForegroundColor Yellow
    azd auth login
    if ($LASTEXITCODE -ne 0) { throw "azd auth login failed" }
}

# Prompt for environment name if not provided
if ([string]::IsNullOrWhiteSpace($Environment)) {
    $Environment = Read-Host "  Enter environment name (e.g. dev staging prod)"
    if ([string]::IsNullOrWhiteSpace($Environment)) {
        Write-Host "[X] Environment name is required" -ForegroundColor Red
        exit 1
    }
}

# Check if environment exists
Push-Location $ScriptRoot
try {
    $existingEnvs = azd env list --output json 2>$null | ConvertFrom-Json
    $envExists = $existingEnvs | Where-Object { $_.Name -eq $Environment }
    
    if ($envExists) {
        Write-Host "  [OK] Using existing environment: $Environment" -ForegroundColor Green
        azd env select $Environment
    } else {
        Write-Host "  Creating new environment: $Environment" -ForegroundColor Yellow
        azd env new $Environment
        if ($LASTEXITCODE -ne 0) { throw "azd env new failed" }
    }
    
    # Set location
    azd env set AZURE_LOCATION $Location
    
    # Set image tag
    azd env set IMAGE_TAG $ImageTag
}
finally {
    Pop-Location
}

# ============================================================================
# Step 2: Configure Secrets
# ============================================================================

Write-Step 2 "Configuring Secrets"

Push-Location $ScriptRoot
try {
    # PostgreSQL password
    $existingPgPass = azd env get-value POSTGRES_PASSWORD 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($existingPgPass)) {
        if ([string]::IsNullOrWhiteSpace($PostgresPassword)) {
            $PostgresPassword = Get-SecureInput "  Enter PostgreSQL admin password"
        }
        azd env set POSTGRES_PASSWORD $PostgresPassword
        Write-Host "  [OK] PostgreSQL password set" -ForegroundColor Green
    } else {
        Write-Host "  [OK] PostgreSQL password already configured" -ForegroundColor Green
    }
    
    # Nitro admin token
    $existingNitroToken = azd env get-value NITRO_ADMIN_TOKEN 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($existingNitroToken)) {
        if ([string]::IsNullOrWhiteSpace($NitroAdminToken)) {
            $NitroAdminToken = Get-SecureInput "  Enter Nitro admin token (for FGP publishing)"
        }
        azd env set NITRO_ADMIN_TOKEN $NitroAdminToken
        Write-Host "  [OK] Nitro admin token set" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Nitro admin token already configured" -ForegroundColor Green
    }
}
finally {
    Pop-Location
}

# ============================================================================
# Step 3: Provision Infrastructure
# ============================================================================

Write-Step 3 "Provisioning Infrastructure"

if ($SkipProvision) {
    Write-Host "  [Skip] Skipping provision step" -ForegroundColor Yellow
} else {
    if (-not $Force) {
        Write-Host ""
        Write-Host "  This will create/update Azure resources:" -ForegroundColor Yellow
        Write-Host "    - Resource Group" -ForegroundColor Gray
        Write-Host "    - Virtual Network + Subnets" -ForegroundColor Gray
        Write-Host "    - Container Registry" -ForegroundColor Gray
        Write-Host "    - Container Apps Environment" -ForegroundColor Gray
        Write-Host "    - PostgreSQL Flexible Server" -ForegroundColor Gray
        Write-Host "    - Log Analytics + App Insights" -ForegroundColor Gray
        Write-Host ""
        $confirm = Read-Host "  Continue? (y/N)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "  Aborted by user" -ForegroundColor Yellow
            exit 0
        }
    }
    
    Push-Location $ScriptRoot
    try {
        $paramFile = Join-Path $ScriptRoot "environments/$ParameterSet.parameters.json"
        
        Write-Host "  Running azd provision..." -ForegroundColor Yellow
        if (Test-Path $paramFile) {
            Write-Host "  Using parameter file: $ParameterSet.parameters.json" -ForegroundColor Gray
            # Note: azd doesn't directly support parameter files, but the main.parameters.json 
            # uses environment variables which we've already set
        }
        
        # Set DEPLOY_APPS to false for initial provision (infra only)
        azd env set DEPLOY_APPS false
        
        azd provision --no-prompt
        if ($LASTEXITCODE -ne 0) { throw "azd provision failed" }
        
        Write-Host "  [OK] Infrastructure provisioned" -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}

# ============================================================================
# Step 4: Build and Push Docker Images
# ============================================================================

Write-Step 4 "Building and Pushing Docker Images"

if ($SkipBuild) {
    Write-Host "  [Skip] Skipping build step" -ForegroundColor Yellow
} else {
    $buildScript = Join-Path $ScriptRoot "scripts/build-images.ps1"
    
    if (-not (Test-Path $buildScript)) {
        Write-Host "  [X] build-images.ps1 not found" -ForegroundColor Red
        exit 1
    }
    
    Push-Location $ScriptRoot
    try {
        & $buildScript -ImageTag $ImageTag -AlsoTagTimestamp
        if ($LASTEXITCODE -ne 0) { throw "Build failed" }
        Write-Host "  [OK] Images built and pushed" -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}

# ============================================================================
# Step 5: Deploy Container Apps
# ============================================================================

Write-Step 5 "Deploying Container Apps"

if ($SkipDeploy) {
    Write-Host "  [Skip] Skipping deploy step" -ForegroundColor Yellow
} else {
    Push-Location $ScriptRoot
    try {
        # Set DEPLOY_APPS to true to deploy apps
        azd env set DEPLOY_APPS true
        
        Write-Host "  Running azd provision (apps)..." -ForegroundColor Yellow
        azd provision --no-prompt
        if ($LASTEXITCODE -ne 0) { throw "azd provision (apps) failed" }
        
        Write-Host "  [OK] Container Apps deployed" -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}

# ============================================================================
# Step 6: Compose and Publish FGP Schema
# ============================================================================

Write-Step 6 "Composing and Publishing Gateway Schema"

if ($SkipFgpPublish) {
    Write-Host "  [Skip] Skipping FGP publish step" -ForegroundColor Yellow
} else {
    # Ensure Fusion CLI is installed
    $fusionInstalled = dotnet tool list -g | Select-String -Pattern "fusion" -Quiet
    if (-not $fusionInstalled) {
        Write-Host "  Installing Fusion CLI..." -ForegroundColor Yellow
        dotnet tool install -g HotChocolate.Fusion.Cli
        if ($LASTEXITCODE -ne 0) { throw "Failed to install Fusion CLI" }
    }
    
    # Wait for services to stabilize
    Write-Host "  Waiting 30 seconds for Container Apps to stabilize..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    
    # Run the publish script
    $publishScript = Join-Path $ScriptRoot "scripts/publish-fgp.ps1"
    
    if (Test-Path $publishScript) {
        Push-Location $ScriptRoot
        try {
            & $publishScript -Environment aca
            if ($LASTEXITCODE -ne 0) { throw "FGP publish failed" }
            Write-Host "  [OK] Gateway schema published" -ForegroundColor Green
        }
        finally {
            Pop-Location
        }
    } else {
        Write-Host "  [!] publish-fgp.ps1 not found, skipping" -ForegroundColor Yellow
    }
}

# ============================================================================
# Done!
# ============================================================================

Write-Host ""
Write-Banner "Deployment Complete!" "Green"
Write-Host ""

# Show endpoints
Push-Location $ScriptRoot
try {
    $gatewayUrl = azd env get-value GATEWAY_URL 2>$null
    $frontendUrl = azd env get-value FRONTEND_URL 2>$null
    $resourceGroup = azd env get-value AZURE_RESOURCE_GROUP 2>$null
    
    Write-Host "Your GraphQL Gateway is ready!" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   Gateway:        $gatewayUrl" -ForegroundColor White
    Write-Host "   Frontend:       $frontendUrl" -ForegroundColor White
    Write-Host "   Resource Group: $resourceGroup" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To view logs:  azd monitor" -ForegroundColor Gray
    Write-Host "To cleanup:    azd down --purge" -ForegroundColor Gray
    Write-Host ""
}
finally {
    Pop-Location
}
