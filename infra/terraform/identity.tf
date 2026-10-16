# User-assigned managed identity used by the Container App to pull from ACR and
# read secrets from Key Vault. This is the *only* identity the workload has;
# access is granted per-resource (least privilege) rather than at RG scope.
resource "azurerm_user_assigned_identity" "app" {
  name                = local.identity_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.base_tags
}

# AcrPull on the single registry the app pulls from.
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# Key Vault Secrets User on the single vault the app reads from.
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# Allow the managed identity to be used for the Azure OpenAI data plane without
# handing out account keys. (Only when the Terraform-provisioned account exists.)
resource "azurerm_role_assignment" "openai_user" {
  count                = var.enable_azure_openai ? 1 : 0
  scope                = azurerm_cognitive_account.openai[0].id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}
