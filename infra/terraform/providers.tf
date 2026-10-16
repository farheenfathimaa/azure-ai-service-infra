provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      # Allow `terraform destroy` to remove the resource group even if it holds
      # resources created outside of Terraform (for example by policy remediation).
      prevent_deletion_if_contains_resources = false
    }
  }

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  # GitHub Actions authenticates with OIDC (federated credentials). No secrets.
  use_oidc = var.use_oidc
}
