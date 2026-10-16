resource "azurerm_key_vault" "kv" {
  name                          = local.key_vault_name
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  enable_rbac_authorization     = true
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
  public_network_access_enabled = !var.enable_private_endpoints
  tags                          = local.base_tags

  network_acls {
    default_action = var.enable_private_endpoints ? "Deny" : "Allow"
    bypass         = "AzureServices"
  }
}

# The identity running Terraform (CLI user or the CI service principal) needs
# data-plane access to write the secrets below. This is scoped to just this vault.
resource "azurerm_role_assignment" "deployer_kv_admin" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "secrets" {
  for_each     = local.kv_secrets
  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.kv.id
  content_type = "text/plain"

  depends_on = [azurerm_role_assignment.deployer_kv_admin]
}
