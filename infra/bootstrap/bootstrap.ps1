#Requires -Version 5.1
<#
.SYNOPSIS
    Creates the Azure Storage account + container that Terraform uses for remote state.

.DESCRIPTION
    Run this once per subscription/environment before `terraform init`. It creates a
    dedicated resource group and a hardened (HTTPS-only, no public blob access,
    versioned, soft-delete) storage account, then prints the backend config to use.

.EXAMPLE
    ./bootstrap.ps1 -Location eastus2
#>
[CmdletBinding()]
param(
    [string]$SubscriptionId = $env:ARM_SUBSCRIPTION_ID,
    [string]$Location = 'eastus2',
    [string]$ResourceGroupName = 'rg-tfstate',
    [string]$StorageAccountName,
    [string]$ContainerName = 'tfstate'
)

$ErrorActionPreference = 'Stop'

if (-not $StorageAccountName) {
    $suffix = -join ((1..6) | ForEach-Object { Get-Random -Minimum 0 -Maximum 10 })
    $StorageAccountName = "sttfstate$suffix"
}

if ($SubscriptionId) {
    Write-Host "Selecting subscription $SubscriptionId"
    az account set --subscription $SubscriptionId | Out-Null
}
$currentSub = az account show --query id -o tsv
Write-Host "Using subscription $currentSub"

Write-Host "Creating resource group $ResourceGroupName"
az group create --name $ResourceGroupName --location $Location --tags managed_by=terraform purpose=tfstate | Out-Null

Write-Host "Creating storage account $StorageAccountName"
az storage account create `
    --name $StorageAccountName `
    --resource-group $ResourceGroupName `
    --location $Location `
    --sku Standard_LRS `
    --kind StorageV2 `
    --min-tls-version TLS1_2 `
    --https-only true `
    --allow-blob-public-access false `
    --allow-shared-key-access true `
    --tags managed_by=terraform purpose=tfstate | Out-Null

Write-Host "Enabling blob versioning and soft delete"
az storage account blob-service-properties update `
    --account-name $StorageAccountName `
    --resource-group $ResourceGroupName `
    --enable-versioning true `
    --enable-delete-retention true `
    --delete-retention-days 30 | Out-Null

Write-Host "Creating container $ContainerName"
# Use the account key for this one-time create: the caller's Storage Blob Data
# Contributor role is granted below and may not have propagated yet. Terraform
# itself still uses AAD auth (use_azuread_auth = true) for remote state.
az storage container create `
    --name $ContainerName `
    --account-name $StorageAccountName `
    --auth-mode key | Out-Null

$storageId = az storage account show --name $StorageAccountName --resource-group $ResourceGroupName --query id -o tsv
$principalId = az ad signed-in-user show --query id -o tsv 2>$null
if ($principalId) {
    Write-Host "Granting current user Storage Blob Data Contributor on the state account"
    az role assignment create --assignee-object-id $principalId --assignee-principal-type User `
        --role "Storage Blob Data Contributor" --scope $storageId | Out-Null
}

$tenantId = az account show --query tenantId -o tsv

Write-Host ""
Write-Host "Bootstrap complete. Add this to infra/terraform/backend.hcl:" -ForegroundColor Green
Write-Host ""
@"
resource_group_name  = "$ResourceGroupName"
storage_account_name = "$StorageAccountName"
container_name       = "$ContainerName"
key                  = "azure-ai-service-infra.tfstate"
use_azuread_auth     = true
"@
Write-Host ""
Write-Host "Azure values for GitHub Actions repo variables:"
Write-Host "  AZURE_SUBSCRIPTION_ID = $currentSub"
Write-Host "  AZURE_TENANT_ID       = $tenantId"
