resource "azurerm_container_app_environment" "env" {
  name                       = local.container_env_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  infrastructure_subnet_id   = azurerm_subnet.apps.id
  tags                       = local.base_tags
}

resource "azurerm_container_app" "app" {
  name                         = local.container_app_name
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = local.base_tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  # Pull images from ACR using the managed identity (no registry password).
  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.app.id
  }

  # Key Vault secrets surfaced to the runtime via the managed identity.
  dynamic "secret" {
    for_each = azurerm_key_vault_secret.secrets
    content {
      name                = secret.key
      identity            = azurerm_user_assigned_identity.app.id
      key_vault_secret_id = secret.value.versionless_id
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "app"
      image  = "${azurerm_container_registry.acr.login_server}/${var.image_name}:${var.image_tag}"
      cpu    = tostring(var.container_cpu)
      memory = var.container_memory

      env {
        name  = "APP_ENV"
        value = var.environment
      }
      env {
        name  = "LLM_PROVIDER"
        value = local.llm_provider
      }
      env {
        name  = "ALLOW_FALLBACK"
        value = tostring(var.enable_groq_fallback)
      }
      env {
        name  = "ALLOW_BOOM"
        value = tostring(var.enable_boom_endpoint)
      }
      env {
        name  = "AZURE_OPENAI_ENDPOINT"
        value = local.azure_openai_endpoint_effective
      }
      env {
        name  = "AZURE_OPENAI_DEPLOYMENT"
        value = local.azure_openai_deployment_effective
      }
      env {
        name  = "AZURE_OPENAI_API_VERSION"
        value = var.azure_openai_api_version
      }
      env {
        name  = "GROQ_MODEL"
        value = var.groq_model
      }

      # Secret-backed environment variables (AZURE_OPENAI_KEY, GROQ_API_KEY).
      dynamic "env" {
        for_each = local.secret_env
        content {
          name        = env.key
          secret_name = env.value
        }
      }

      liveness_probe {
        transport = "HTTP"
        port      = 8000
        path      = "/health"
      }

      readiness_probe {
        transport = "HTTP"
        port      = 8000
        path      = "/health"
      }
    }
  }

  ingress {
    external_enabled           = true
    target_port                = 8000
    transport                  = "http"
    allow_insecure_connections = false

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  # The image reference is managed out-of-band by the deploy workflow (az acr build)
  # so a new tag can roll a revision without Terraform churn on every build.
  lifecycle {
    ignore_changes = [
      template[0].container[0].image,
    ]
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.kv_secrets_user,
  ]
}
