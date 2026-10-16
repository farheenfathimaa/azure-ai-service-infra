# Remote state lives in an Azure Storage container created by infra/bootstrap.
# Configuration is intentionally partial so no secrets/ids are committed; supply
# values via backend config:
#   terraform init -backend-config=backend.hcl
# or via `-backend-config="key=value"` flags (used by CI).
terraform {
  backend "azurerm" {}
}
