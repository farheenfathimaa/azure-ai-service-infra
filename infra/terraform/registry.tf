resource "azurerm_container_registry" "acr" {
  name                          = local.acr_name
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  sku                           = "Basic"
  admin_enabled                 = false
  public_network_access_enabled = !var.enable_private_endpoints
  tags                          = local.base_tags
}
