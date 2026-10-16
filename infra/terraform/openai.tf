# Optional Azure OpenAI account + model deployment. Controlled by var.enable_azure_openai.
# When disabled the app relies on the Groq fallback provider.
resource "azurerm_cognitive_account" "openai" {
  count                 = var.enable_azure_openai ? 1 : 0
  name                  = local.openai_name
  resource_group_name   = azurerm_resource_group.main.name
  location              = azurerm_resource_group.main.location
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = local.openai_name
  tags                  = local.base_tags
}

resource "azurerm_cognitive_deployment" "openai" {
  count                = var.enable_azure_openai ? 1 : 0
  name                 = local.openai_deployment
  cognitive_account_id = azurerm_cognitive_account.openai[0].id

  model {
    format  = "OpenAI"
    name    = var.azure_openai_model
    version = var.azure_openai_model_version
  }

  scale {
    type     = "Standard"
    tier     = "Standard"
    capacity = 10
  }
}
