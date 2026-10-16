output "resource_group_name" {
  description = "Name of the workload resource group."
  value       = azurerm_resource_group.main.name
}

output "container_app_name" {
  description = "Name of the Container App."
  value       = azurerm_container_app.app.name
}

output "container_app_fqdn" {
  description = "Public FQDN of the Container App."
  value       = azurerm_container_app.app.latest_revision_fqdn
}

output "health_url" {
  description = "URL to hit to check the service health."
  value       = "https://${azurerm_container_app.app.latest_revision_fqdn}/health"
}

output "ask_url" {
  description = "URL of the RAG endpoint."
  value       = "https://${azurerm_container_app.app.latest_revision_fqdn}/ask"
}

output "container_registry_login_server" {
  description = "ACR login server. Use with `az acr build`."
  value       = azurerm_container_registry.acr.login_server
}

output "container_registry_name" {
  description = "ACR resource name."
  value       = azurerm_container_registry.acr.name
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = azurerm_key_vault.kv.vault_uri
}

output "managed_identity_client_id" {
  description = "Client ID of the app's user-assigned managed identity."
  value       = azurerm_user_assigned_identity.app.client_id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the app's user-assigned managed identity."
  value       = azurerm_user_assigned_identity.app.principal_id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID."
  value       = azurerm_log_analytics_workspace.law.id
}

output "alert_id" {
  description = "Resource ID of the 5xx metric alert."
  value       = azurerm_monitor_metric_alert.http_5xx.id
}

output "action_group_id" {
  description = "Resource ID of the alert action group."
  value       = azurerm_monitor_action_group.main.id
}

output "llm_provider" {
  description = "Resolved LLM provider for this deployment."
  value       = local.llm_provider
}
