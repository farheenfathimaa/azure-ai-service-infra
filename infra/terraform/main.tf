# Short random suffix keeps globally-unique names (ACR, Key Vault, OpenAI) stable
# for the lifetime of the stack while avoiding collisions across deployments.
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.base_tags
}

# Identifies whoever is running Terraform (your CLI login, or the GitHub OIDC
# service principal) so we can grant it the roles it needs on the resources it manages.
data "azurerm_client_config" "current" {}
