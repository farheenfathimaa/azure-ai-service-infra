#!/usr/bin/env bash
# Creates the Azure Storage account + container that Terraform uses for remote state.
# Run once per subscription/environment before `terraform init`.
#
# Usage: ./bootstrap.sh [location] [resource-group] [storage-account] [container]
set -euo pipefail

SUBSCRIPTION_ID="${ARM_SUBSCRIPTION_ID:-}"
LOCATION="${1:-eastus2}"
RESOURCE_GROUP_NAME="${2:-rg-tfstate}"
STORAGE_ACCOUNT_NAME="${3:-sttfstate$RANDOM$RANDOM}"
CONTAINER_NAME="${4:-tfstate}"

if [[ -n "$SUBSCRIPTION_ID" ]]; then
  echo "Selecting subscription $SUBSCRIPTION_ID"
  az account set --subscription "$SUBSCRIPTION_ID"
fi
CURRENT_SUB="$(az account show --query id -o tsv)"
echo "Using subscription $CURRENT_SUB"

echo "Creating resource group $RESOURCE_GROUP_NAME"
az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" \
  --tags managed_by=terraform purpose=tfstate -o none

echo "Creating storage account $STORAGE_ACCOUNT_NAME"
az storage account create \
  --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --https-only true \
  --allow-blob-public-access false \
  --allow-shared-key-access true \
  --tags managed_by=terraform purpose=tfstate -o none

echo "Enabling blob versioning and soft delete"
az storage account blob-service-properties update \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 30 -o none

echo "Creating container $CONTAINER_NAME"
# Use the account key for this one-time create: the caller's Storage Blob Data
# Contributor role is granted below and may not have propagated yet. Terraform
# itself still uses AAD auth (use_azuread_auth = true) for remote state.
az storage container create \
  --name "$CONTAINER_NAME" \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --auth-mode key -o none

STORAGE_ID="$(az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query id -o tsv)"
PRINCIPAL_ID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
if [[ -n "$PRINCIPAL_ID" ]]; then
  echo "Granting current user Storage Blob Data Contributor on the state account"
  az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type User \
    --role "Storage Blob Data Contributor" --scope "$STORAGE_ID" -o none
fi

TENANT_ID="$(az account show --query tenantId -o tsv)"

echo ""
echo "Bootstrap complete. Write this to infra/terraform/backend.hcl:"
echo ""
cat <<EOF
resource_group_name  = "$RESOURCE_GROUP_NAME"
storage_account_name = "$STORAGE_ACCOUNT_NAME"
container_name       = "$CONTAINER_NAME"
key                  = "azure-ai-service-infra.tfstate"
use_azuread_auth     = true
EOF
echo ""
echo "Azure values for GitHub Actions repo variables:"
echo "  AZURE_SUBSCRIPTION_ID = $CURRENT_SUB"
echo "  AZURE_TENANT_ID       = $TENANT_ID"
