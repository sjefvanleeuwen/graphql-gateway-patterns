# GraphQL Gateway - Azure Container Apps Deployment

Modern AZD-based deployment for the GraphQL Gateway Patterns project.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) (v2.50+)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Docker](https://docs.docker.com/get-docker/)
- [PowerShell 7+](https://docs.microsoft.com/powershell/scripting/install/installing-powershell)
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Fusion CLI](https://www.nuget.org/packages/FusionCli) (`dotnet tool install -g FusionCli`)

## Quick Start

### Option 1: One-Command Deployment

```powershell
# Navigate to deployment folder
cd deployment/alderaan

# Deploy everything (will prompt for secrets)
./deploy.ps1 -Environment dev -Location northeurope

# Or with all parameters
./deploy.ps1 -Environment dev `
    -Location northeurope `
    -PostgresPassword "YourSecurePassword123!" `
    -NitroAdminToken "your-admin-token" `
    -Force
```

### Option 2: Step-by-Step with azd

```powershell
# 1. Navigate to deployment folder
cd deployment/alderaan

# 2. Login to Azure
azd auth login

# 3. Create environment
azd env new dev

# 4. Set required secrets
azd env set AZURE_LOCATION northeurope
azd env set POSTGRES_PASSWORD "YourSecurePassword123!"
azd env set NITRO_ADMIN_TOKEN "your-admin-token-here"

# 5. Provision infrastructure
azd provision

# 6. Build and deploy services
azd deploy
```

### deploy.ps1 Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Environment` | Environment name (dev, staging, prod) | *(prompts)* |
| `-Location` | Azure region | `northeurope` |
| `-PostgresPassword` | PostgreSQL admin password | *(prompts)* |
| `-NitroAdminToken` | Token for FGP publishing | *(prompts)* |
| `-ImageTag` | Docker image tag | `latest` |
| `-ParameterSet` | Parameter file to use (dev/staging/prod) | `dev` |
| `-SkipLogin` | Skip Azure login | |
| `-SkipProvision` | Skip infrastructure provisioning | |
| `-SkipBuild` | Skip Docker image build | |
| `-SkipDeploy` | Skip Container Apps deployment | |
| `-SkipFgpPublish` | Skip FGP schema publishing | |
| `-Force` | Skip confirmation prompts | |

### Deployment Flow

The `deploy.ps1` script orchestrates the full deployment in this sequence:

```
┌─────────────────────────────────────────────────────────────────┐
│                      deploy.ps1 Flow                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [0] Validate Prerequisites                                     │
│      ├── Check: az, azd, docker, dotnet                        │
│      ├── Check: Fusion CLI (installs if missing)               │
│      └── Verify: Docker is running                             │
│                           │                                     │
│                           ▼                                     │
│  [1] Azure Authentication                                       │
│      ├── az login (if not logged in)                           │
│      ├── azd auth login                                        │
│      └── Create/select azd environment                         │
│                           │                                     │
│                           ▼                                     │
│  [2] Configure Secrets                                          │
│      ├── Set POSTGRES_PASSWORD (prompt or parameter)           │
│      └── Set NITRO_ADMIN_TOKEN (prompt or parameter)           │
│                           │                                     │
│                           ▼                                     │
│  [3] Provision Infrastructure (azd provision)                   │
│      ├── Resource Group                                        │
│      ├── VNet + Subnets                                        │
│      ├── Container Registry                                    │
│      ├── Container Apps Environment                            │
│      ├── PostgreSQL Flexible Server                            │
│      └── Log Analytics + App Insights                          │
│                           │                                     │
│                           ▼                                     │
│  [4] Build & Push Images (scripts/build-images.ps1)            │
│      ├── Auto-discover services from src/                      │
│      ├── Build Docker images                                   │
│      └── Push to ACR                                           │
│                           │                                     │
│                           ▼                                     │
│  [5] Deploy Container Apps (azd deploy)                         │
│      ├── Gateway (external)                                    │
│      ├── Frontend (external)                                   │
│      ├── Subgraphs: products, reviews, shipping, orders        │
│      ├── Nitro Schema API (internal)                           │
│      └── BackOffice worker (scale-to-zero)                     │
│                           │                                     │
│                           ▼                                     │
│  [6] Publish Gateway Schema                                     │
│      ├── Wait 30s for services to stabilize                    │
│      ├── Compose FGP with ACA URLs (Fusion CLI)                │
│      └── Publish to Nitro → broadcast to Gateway replicas      │
│                           │                                     │
│                           ▼                                     │
│  ✅ Done! Gateway URL + Frontend URL displayed                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Common Scenarios:**

```powershell
# Full deployment from scratch
./deploy.ps1 -Environment dev

# Redeploy apps only (skip infrastructure)
./deploy.ps1 -Environment dev -SkipProvision

# Rebuild images and redeploy (no infra changes)
./deploy.ps1 -Environment dev -SkipProvision -SkipLogin

# Just republish the gateway schema
./deploy.ps1 -Environment dev -SkipProvision -SkipBuild -SkipDeploy

# CI/CD: fully automated, no prompts
./deploy.ps1 -Environment prod `
    -PostgresPassword $env:PG_PASS `
    -NitroAdminToken $env:NITRO_TOKEN `
    -Force
```

## Project Structure

```
deployment/alderaan/
├── azure.yaml                    # AZD project manifest
├── infra/
│   ├── main.bicep               # Entry point (subscription scope)
│   ├── main.parameters.json     # Parameter template (uses azd env vars)
│   ├── abbreviations.json       # Azure naming conventions
│   │
│   ├── core/                    # Core infrastructure
│   │   ├── network.bicep        # VNet, subnets
│   │   ├── monitoring.bicep     # Log Analytics, App Insights
│   │   ├── registry.bicep       # Container Registry
│   │   └── database.bicep       # PostgreSQL + Private DNS
│   │
│   └── apps/                    # Container Apps
│       ├── environment.bicep    # ACA Environment
│       ├── subgraphs.bicep      # Products, Reviews, Shipping, Orders
│       ├── nitro.bicep          # Nitro Schema API
│       ├── gateway.bicep        # Fusion Gateway
│       ├── frontend.bicep       # Frontend app
│       └── workers.bicep        # BackOffice worker
│
├── environments/                # Environment-specific parameters
│   ├── dev.parameters.json
│   ├── staging.parameters.json
│   └── prod.parameters.json
│
└── scripts/                     # Helper scripts
    ├── post-provision.ps1       # Runs after azd provision
    ├── post-provision.sh        # Bash version
    ├── build-images.ps1         # Auto-discovers & builds services
    └── publish-fgp.ps1          # Compose & publish gateway schema

src/                             # Services auto-discovered from here
├── Gateway/Dockerfile           # -> gateway
├── ProductsService/Dockerfile   # -> products
├── ReviewsService/Dockerfile    # -> reviews
├── ShippingService/Dockerfile   # -> shipping
├── OrdersService/Dockerfile     # -> orders
├── BackOfficeService/Dockerfile # -> backoffice
├── NitroSchemaApi/Dockerfile    # -> nitro-schema-api
└── [NewService]/Dockerfile      # -> auto-discovered!

frontend/                        # Frontend auto-discovered
└── Dockerfile                   # -> frontend
```

> **Note:** The build script auto-discovers services by scanning for `Dockerfile` in each subdirectory. Add a new service by creating a folder with a Dockerfile - no config changes needed!

## Environment Configuration

### Required Environment Variables

| Variable | Description |
|----------|-------------|
| `AZURE_LOCATION` | Azure region (e.g., `northeurope`) |
| `POSTGRES_PASSWORD` | PostgreSQL admin password |
| `NITRO_ADMIN_TOKEN` | Token for FGP publishing |

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE_TAG` | `latest` | Docker image tag to deploy |
| `AZURE_ENV_NAME` | (from azd) | Environment name (dev/staging/prod) |

### Setting Variables

```powershell
# Set secrets (not stored in files)
azd env set POSTGRES_PASSWORD "SecurePassword123!"
azd env set NITRO_ADMIN_TOKEN "my-secret-token"

# View current environment
azd env get-values
```

## Deployment Commands

### Full Deployment

```powershell
# Provision infrastructure + deploy services
azd up
```

### Infrastructure Only

```powershell
# Deploy/update infrastructure without touching apps
azd provision
```

### Applications Only

```powershell
# Deploy all services (assumes infra exists)
azd deploy

# Deploy specific service
azd deploy gateway
azd deploy frontend
```

### Build Images Manually

The build script **auto-discovers services** by scanning `src/` for directories containing a `Dockerfile`. No hardcoded service list needed!

```powershell
# Build and push all discovered services
./scripts/build-images.ps1

# Build with timestamp tag for versioning
./scripts/build-images.ps1 -AlsoTagTimestamp

# Skip build, just push existing images
./scripts/build-images.ps1 -SkipBuild

# Build specific services only
./scripts/build-images.ps1 -Services "gateway,orders"
```

#### Service Discovery

The script automatically:
1. Scans `src/` for directories with a `Dockerfile`
2. Converts directory names to container names (e.g., `ProductsService` → `products`)
3. Builds and pushes each discovered service

**Naming Convention:**
| Directory | Container Name |
|-----------|----------------|
| `Gateway` | `gateway` |
| `ProductsService` | `products` |
| `NitroSchemaApi` | `nitro-schema-api` |
| `BackOfficeService` | `backoffice` |

To add a new service, simply create a directory in `src/` with a `Dockerfile` - it will be automatically discovered and deployed.

```powershell
# List all discovered services without building
./scripts/build-images.ps1 -ListOnly
```

### Publish Gateway Schema

```powershell
# Compose FGP with ACA URLs and publish
./scripts/publish-fgp.ps1 -Environment aca

# Dry run (compose only)
./scripts/publish-fgp.ps1 -Environment aca -DryRun
```

## Multi-Environment Deployment

### Using Environment Parameter Files

```powershell
# Dev environment
azd env new dev
azd env set AZURE_LOCATION northeurope
azd provision --parameter-file environments/dev.parameters.json

# Production environment  
azd env new prod
azd env set AZURE_LOCATION westeurope
azd provision --parameter-file environments/prod.parameters.json
```

### Switching Environments

```powershell
# List environments
azd env list

# Switch to different environment
azd env select prod

# Show current environment
azd env get-values
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Container Apps                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐                           │
│  │   Frontend   │    │   Gateway    │◄──── External Ingress     │
│  │   (React)    │    │  (Fusion)    │                           │
│  └──────────────┘    └──────┬───────┘                           │
│                             │                                    │
│         ┌───────────────────┼───────────────────┐               │
│         │                   │                   │               │
│         ▼                   ▼                   ▼               │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │   Products   │    │   Reviews    │    │   Shipping   │       │
│  │  (GraphQL)   │    │  (GraphQL)   │    │  (GraphQL)   │       │
│  └──────────────┘    └──────────────┘    └──────────────┘       │
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │    Orders    │    │  BackOffice  │    │    Nitro     │       │
│  │  (GraphQL)   │    │   (Worker)   │    │ Schema API   │       │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘       │
│         │                   │                   │               │
│         └───────────────────┴───────────────────┘               │
│                             │                                    │
├─────────────────────────────┼────────────────────────────────────┤
│                             ▼                                    │
│                    ┌──────────────┐                             │
│                    │  PostgreSQL  │◄──── Private DNS Zone       │
│                    │  (Flexible)  │                             │
│                    └──────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

## Monitoring

```powershell
# Open Azure Portal monitoring dashboard
azd monitor

# View logs in terminal
az containerapp logs show -n gateway -g <resource-group> --follow
```

## Troubleshooting

### Container App Not Starting

```powershell
# Check container app status
az containerapp show -n gateway -g <rg> --query "properties.runningStatus"

# View logs
az containerapp logs show -n gateway -g <rg> --tail 100
```

### FGP Publishing Fails

1. Check Nitro Schema API is running
2. Verify `NITRO_ADMIN_TOKEN` matches
3. Ensure subgraphs are accessible from your machine (for composition)

```powershell
# Test Nitro health
curl https://nitro-schema-api.internal.<domain>/health
```

### Database Connection Issues

1. Verify Postgres is in the same VNet
2. Check private DNS zone is linked
3. Confirm connection string uses internal FQDN

## Cleanup

```powershell
# Delete all Azure resources
azd down --purge --force

# Or just the resource group
az group delete --name rg-graphql-gateway-dev --yes
```

## CI/CD Integration

See [aca-bicep-deployment.md](../aca-bicep-deployment.md) for GitHub Actions and Azure DevOps pipeline examples.
