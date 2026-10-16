#!/usr/bin/env bash
# Creates a secretless GitHub Actions OIDC identity (app registration + federated
# credentials) and grants the RBAC it needs. No client secret is created.
#
# Usage:
#   ./setup-oidc.sh <owner/repo> [state-storage-account-resource-id] [environment]
set -euo pipefail

GITHUB_REPO="${1:?usage: setup-oidc.sh <owner/repo> [state-storage-account-id] [environment]}"
STATE_STORAGE_ACCOUNT_ID="${2:-}"
ENVIRONMENT="${3:-}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-gh-azure-ai-service-infra}"

if [[ -n "${ARM_SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "$ARM_SUBSCRIPTION_ID"
fi
CURRENT_SUB="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
echo "Subscription: $CURRENT_SUB"
echo "Tenant:       $TENANT_ID"

echo "Creating app registration '$APP_DISPLAY_NAME'"
APP_ID="$(az ad app create --display-name "$APP_DISPLAY_NAME" --query appId -o tsv)"
[[ -n "$APP_ID" ]] || APP_ID="$(az ad app list --display-name "$APP_DISPLAY_NAME" --query '[0].appId' -o tsv)"

echo "Ensuring service principal exists"
SP_OBJECT_ID="$(az ad sp list --filter "appId eq '$APP_ID'" --query '[0].id' -o tsv)"
if [[ -z "$SP_OBJECT_ID" ]]; then
  SP_OBJECT_ID="$(az ad sp create --id "$APP_ID" --query id -o tsv)"
fi

create_federated_credential() {
  local name="$1" subject="$2"
  if az ad app federated-credential list --id "$APP_ID" --query "[?name=='$name'].name" -o tsv | grep -q .; then
    echo "  federated credential '$name' already exists"
    return
  fi
  local payload
  payload="$(cat <<JSON
{
  "name": "$name",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "$subject",
  "audiences": ["api://AzureADTokenExchange"]
}
JSON
)"
  az ad app federated-credential create --id "$APP_ID" --parameters "$payload" -o none
  echo "  created federated credential '$name' ($subject)"
}

echo "Creating federated credentials"
create_federated_credential "github-pull-request" "repo:${GITHUB_REPO}:pull_request"
create_federated_credential "github-main" "repo:${GITHUB_REPO}:ref:refs/heads/main"
if [[ -n "$ENVIRONMENT" ]]; then
  create_federated_credential "github-env-${ENVIRONMENT}" "repo:${GITHUB_REPO}:environment:${ENVIRONMENT}"
fi

echo "Granting subscription roles"
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal \
  --role "Contributor" --scope "/subscriptions/$CURRENT_SUB" -o none
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" --scope "/subscriptions/$CURRENT_SUB" -o none

if [[ -n "$STATE_STORAGE_ACCOUNT_ID" ]]; then
  echo "Granting Storage Blob Data Contributor on the state account"
  az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal \
    --role "Storage Blob Data Contributor" --scope "$STATE_STORAGE_ACCOUNT_ID" -o none
fi

echo ""
echo "OIDC setup complete. Set these as GitHub Actions repository VARIABLES:"
echo "  AZURE_CLIENT_ID       = $APP_ID"
echo "  AZURE_TENANT_ID       = $TENANT_ID"
echo "  AZURE_SUBSCRIPTION_ID = $CURRENT_SUB"
echo ""
echo "Also set: TF_STATE_RESOURCE_GROUP, TF_STATE_STORAGE_ACCOUNT, TF_STATE_CONTAINER."
