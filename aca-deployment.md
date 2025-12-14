# Manual Deployment Guide (Azure CLI)

This guide describes how to provision and deploy the GraphQL Gateway solution using standard Azure CLI (`az`) commands, bypassing `azd`.

## Automated Script

A PowerShell script `manual-deploy.ps1` has been created to automate the following steps.

```powershell
./manual-deploy.ps1
```

## Manual Steps

### 1. Clean Slate

Ensure previous resource groups are removed.

```powershell
az group delete --name rg-aca-3 --yes --no-wait
```

### 2. Provision Infrastructure

We will deploy the infrastructure using Bicep. This creates the Container Registry (ACR), Container Apps Environment, PostgreSQL, and the Container Apps themselves (running a placeholder 'Hello World' image initially).

```powershell
$LOCATION = 'northeurope'
$ENV_NAME = 'aca-3'
$RG_NAME = "rg-$ENV_NAME"

# Create the deployment at subscription scope
az deployment sub create `
  --name "manual-deploy-$ENV_NAME" `
  --location $LOCATION `
  --template-file infra/main.bicep `
  --parameters environmentName=$ENV_NAME location=$LOCATION
```

### 3. Get Outputs

Retrieve the ACR login server name from the deployment outputs.

```powershell
# Get the ACR name
$ACR_LOGIN_SERVER = az deployment sub show --name "manual-deploy-$ENV_NAME" --query properties.outputs.AZURE_CONTAINER_REGISTRY_ENDPOINT.value -o tsv
$ACR_NAME = $ACR_LOGIN_SERVER.Split('.')[0]
```

### 4. Build and Push Images

Login to the registry and build/push images for each service.

```powershell
az acr login --name $ACR_NAME

# Example for Gateway
docker build -t $ACR_LOGIN_SERVER/graphql-gateway/gateway:latest -f src/Gateway/Dockerfile .
docker push $ACR_LOGIN_SERVER/graphql-gateway/gateway:latest
# Repeat for all services...
```

### 5. Deploy (Update Container Apps)

Update the Container Apps to use the new images.

```powershell
az containerapp update --name <app-name> --resource-group $RG_NAME --image <image-tag>
```

