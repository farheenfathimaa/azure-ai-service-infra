resource "azurerm_log_analytics_workspace" "law" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.base_tags
}

resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = substr("ai-${var.environment}", 0, 12)
  tags                = local.base_tags

  dynamic "email_receiver" {
    for_each = var.alert_email != null ? [var.alert_email] : []
    content {
      name          = "primary"
      email_address = email_receiver.value
    }
  }
}

# Fires when the Container App returns 5xx responses. Test it by driving traffic
# to /boom (see README "Verify the stack").
resource "azurerm_monitor_metric_alert" "http_5xx" {
  name                = "alert-http5xx-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.app.id]
  description         = "Container App ${local.container_app_name} returned ${var.alert_5xx_threshold}+ 5xx responses."
  severity            = 2
  window_size         = var.alert_window_size
  frequency           = var.alert_frequency
  tags                = local.base_tags

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "Requests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.alert_5xx_threshold

    dimension {
      name     = "statusCodeCategory"
      operator = "Include"
      values   = ["5xx"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}
