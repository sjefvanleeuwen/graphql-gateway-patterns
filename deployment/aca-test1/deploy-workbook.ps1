param(
  [string]$DeploymentName = 'alderaan-bootstrap',
  [string]$WorkbookTemplatePath = $(Join-Path $PSScriptRoot 'workbook-orders.json')
)

$ErrorActionPreference = 'Stop'

Write-Host "Loading outputs from deployment '$DeploymentName'..."
$outputsJson = az deployment sub show --name $DeploymentName --query properties.outputs -o json
if ([string]::IsNullOrWhiteSpace($outputsJson)) {
  throw "No outputs returned. Did you run provision.ps1 successfully?"
}
$outputs = $outputsJson | ConvertFrom-Json

$resourceGroupName = $outputs.resourcE_GROUP_NAME.value
$logAnalyticsName = $outputs.loG_ANALYTICS_WORKSPACE_NAME.value

if ([string]::IsNullOrWhiteSpace($resourceGroupName) -or [string]::IsNullOrWhiteSpace($logAnalyticsName)) {
  throw "Missing required deployment outputs."
}

Write-Host "Resource Group: $resourceGroupName"
Write-Host "Log Analytics Workspace: $logAnalyticsName"

# Get the Log Analytics workspace ID
$logAnalyticsId = az monitor log-analytics workspace show -g $resourceGroupName -n $logAnalyticsName --query id -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($logAnalyticsId)) {
  throw "Failed to fetch Log Analytics workspace ID"
}

Write-Host "Log Analytics ID: $logAnalyticsId"

# Read the workbook template
if (-not (Test-Path $WorkbookTemplatePath)) {
  throw "Workbook template not found at $WorkbookTemplatePath"
}

Write-Host "Creating workbook from template..."

# Create a unique workbook name (must be GUID for workbooks)
$workbookName = [guid]::NewGuid().ToString()

# Read and parse workbook content
$workbookObject = Get-Content $WorkbookTemplatePath -Raw | ConvertFrom-Json
$workbookSerialized = $workbookObject | ConvertTo-Json -Compress

# Create minimal ARM template
$armTemplate = @{
  "`$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
  contentVersion = "1.0.0.0"
  resources = @(
    @{
      type = "Microsoft.Insights/workbooks"
      apiVersion = "2023-06-01"
      name = $workbookName
      location = "northeurope"
      kind = "shared"
      tags = @{
        Environment = "Production"
        Purpose = "OrdersMonitoring"
      }
      properties = @{
        displayName = "Orders Processing Monitor"
        serializedData = $workbookSerialized
        version = "1.0"
        sourceId = $logAnalyticsId
        category = "workbook"
      }
    }
  )
} | ConvertTo-Json -Depth 20

$templateFile = "$env:TEMP\workbook-template-$workbookName.json"
$armTemplate | Out-File -FilePath $templateFile -Encoding UTF8 -Force

Write-Host "Deploying workbook '$workbookName'..."

az deployment group create `
  --resource-group $resourceGroupName `
  --template-file $templateFile `
  --mode Incremental | Out-Host

if ($LASTEXITCODE -ne 0) {
  throw "Failed to deploy workbook"
}

Remove-Item -Path $templateFile -Force -ErrorAction SilentlyContinue

Write-Host "`n✅ Workbook deployed successfully!"
Write-Host "View it at: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourcegroups/$resourceGroupName/providers/microsoft.insights/workbooks"
