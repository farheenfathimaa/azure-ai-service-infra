locals {
  name_prefix = "${var.project_name}-${var.environment}"
  suffix      = random_string.suffix.result

  # Standard tag set. `owner` is part of the required-tags policy, give it a default.
  base_tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      owner       = lookup(var.tags, "owner", "platform-team")
      managed_by  = "terraform"
    },
    var.tags,
  )

  # Resource names
  resource_group_name = "rg-${local.name_prefix}"
  vnet_name           = "vnet-${local.name_prefix}"
  apps_subnet_name    = "snet-apps"
  pe_subnet_name      = "snet-private-endpoints"
  acr_name            = "acr${var.project_name}${var.environment}${local.suffix}"
  key_vault_name      = "kv-${var.project_name}-${local.suffix}"
  log_analytics_name  = "log-${local.name_prefix}-${local.suffix}"
  container_env_name  = "cae-${local.name_prefix}"
  container_app_name  = "ca-${local.name_prefix}"
  identity_name       = "id-${local.name_prefix}"
  openai_name         = "aoai-${local.name_prefix}-${local.suffix}"

  # GitHub Actions passes unset repository variables/secrets as empty strings.
  # Treat blank values as "not configured" so optional inputs stay optional.
  azure_openai_endpoint_override   = try(trimspace(var.azure_openai_endpoint) != "" ? var.azure_openai_endpoint : null, null)
  azure_openai_key_override        = try(trimspace(var.azure_openai_key) != "" ? var.azure_openai_key : null, null)
  azure_openai_deployment_override = try(trimspace(var.azure_openai_deployment) != "" ? var.azure_openai_deployment : null, null)
  groq_api_key_effective           = try(trimspace(var.groq_api_key) != "" ? var.groq_api_key : null, null)
  alert_email_effective            = try(trimspace(var.alert_email) != "" ? var.alert_email : null, null)

  openai_deployment = coalesce(local.azure_openai_deployment_override, replace(var.azure_openai_model, ".", "-"))

  # Azure OpenAI wiring: prefer bring-your-own values, else the provisioned account.
  created_openai_endpoint = try("https://${azurerm_cognitive_account.openai[0].custom_subdomain_name}.openai.azure.com/", null)
  created_openai_key      = try(azurerm_cognitive_account.openai[0].primary_access_key, null)

  azure_openai_endpoint_effective   = coalesce(local.azure_openai_endpoint_override, local.created_openai_endpoint, "")
  azure_openai_key_effective        = coalesce(local.azure_openai_key_override, local.created_openai_key)
  azure_openai_deployment_effective = coalesce(local.azure_openai_deployment_override, var.enable_azure_openai ? local.openai_deployment : null, "")

  # Secrets are written to Key Vault only when their value exists.
  kv_secrets = merge(
    local.azure_openai_key_effective != null ? { "azure-openai-key" = local.azure_openai_key_effective } : {},
    var.enable_groq_fallback && local.groq_api_key_effective != null ? { "groq-api-key" = local.groq_api_key_effective } : {},
  )

  # Map Key Vault secret names to the environment variables the app reads.
  secret_env = merge(
    contains(keys(local.kv_secrets), "azure-openai-key") ? { AZURE_OPENAI_KEY = "azure-openai-key" } : {},
    contains(keys(local.kv_secrets), "groq-api-key") ? { GROQ_API_KEY = "groq-api-key" } : {},
  )

  # Provider toggle resolved at deploy time.
  llm_provider = (
    var.enable_azure_openai && local.azure_openai_key_effective != null
    ? (var.enable_groq_fallback && local.groq_api_key_effective != null ? "auto" : "azure_openai")
    : (var.enable_groq_fallback && local.groq_api_key_effective != null ? "groq" : "echo")
  )
}
