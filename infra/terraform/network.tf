resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = local.base_tags
}

# Dedicated subnet for the Container Apps environment. Must be delegated to
# Microsoft.App/environments and is sized at /23 for future scale-out.
resource "azurerm_subnet" "apps" {
  name                 = local.apps_subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.apps_subnet_prefix]

  delegation {
    name = "container-apps-delegation"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Subnet for private endpoints (Key Vault / ACR) when them enabled.
resource "azurerm_subnet" "private_endpoints" {
  name                 = local.pe_subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_endpoint_subnet_prefix]
}

# --- Private DNS (only when private endpoints are enabled) ------------------

resource "azurerm_private_dns_zone" "key_vault" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.base_tags
}

resource "azurerm_private_dns_zone" "acr" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.base_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "link-kv"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = local.base_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count                 = var.enable_private_endpoints ? 1 : 0
  name                  = "link-acr"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = local.base_tags
}

resource "azurerm_private_endpoint" "key_vault" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${local.key_vault_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.base_tags

  private_service_connection {
    name                           = "psc-keyvault"
    private_connection_resource_id = azurerm_key_vault.kv.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "dzg-keyvault"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault[0].id]
  }
}

resource "azurerm_private_endpoint" "acr" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "pe-${local.acr_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.base_tags

  private_service_connection {
    name                           = "psc-acr"
    private_connection_resource_id = azurerm_container_registry.acr.id
    is_manual_connection           = false
    subresource_names              = ["registry"]
  }

  private_dns_zone_group {
    name                 = "dzg-acr"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr[0].id]
  }
}
