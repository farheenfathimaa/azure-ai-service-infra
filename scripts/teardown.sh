#!/usr/bin/env bash
# Destroys the Terraform-managed stack.
#
# Usage:
#   ./teardown.sh                         # destroy the workload stack
#   DESTROY_BOOTSTRAP=1 ./teardown.sh     # also delete the state resource group
#   DESTROY_OIDC=1 CLIENT_ID=<appId> ./teardown.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../infra/terraform"

echo "Destroying workload stack in ${TF_DIR}"
terraform -chdir="${TF_DIR}" init -backend-config=backend.hcl -input=false
terraform -chdir="${TF_DIR}" destroy -auto-approve

if [[ "${DESTROY_BOOTSTRAP:-0}" == "1" ]]; then
  RG="${STATE_RESOURCE_GROUP:-rg-tfstate}"
  echo "Deleting remote-state resource group ${RG}"
  az group delete --name "${RG}" --yes --no-wait
fi

if [[ "${DESTROY_OIDC:-0}" == "1" ]]; then
  : "${CLIENT_ID:?CLIENT_ID is required when DESTROY_OIDC=1}"
  echo "Deleting OIDC app registration ${CLIENT_ID}"
  az ad app delete --id "${CLIENT_ID}"
fi

echo "Teardown complete."
