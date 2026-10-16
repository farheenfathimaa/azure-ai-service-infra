variable "subscription_id" {
  description = "Azure subscription ID. Null uses the ambient CLI/OIDC context."
  type        = string
  default     = null
}

variable "tenant_id" {
  description = "Azure tenant ID. Null uses the ambient CLI/OIDC context."
  type        = string
  default     = null
}

variable "use_oidc" {
  description = "Use OIDC federated credentials (GitHub Actions) instead of a client secret."
  type        = bool
  default     = false
}

variable "project_name" {
  description = "Short, lowercase project name used as a resource name prefix."
  type        = string
  default     = "azureaisvc"

  validation {
    condition     = can(regex("^[a-z0-9]{3,15}$", var.project_name))
    error_message = "project_name must be 3-15 lowercase alphanumeric characters."
  }
}

variable "environment" {
  description = "Deployment environment (dev, test, prod). Also used as the required 'environment' tag."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus2"
}

variable "tags" {
  description = "Additional tags merged into the standard tag set."
  type        = map(string)
  default     = {}
}

# --- Networking -------------------------------------------------------------

variable "vnet_address_space" {
  description = "Address space for the virtual network."
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

variable "apps_subnet_prefix" {
  description = "Prefix for the Container Apps environment subnet (must be /23 or larger)."
  type        = string
  default     = "10.20.0.0/23"
}

variable "private_endpoint_subnet_prefix" {
  description = "Prefix for the private endpoint subnet."
  type        = string
  default     = "10.20.2.0/24"
}

variable "enable_private_endpoints" {
  description = "Create private endpoints (and private DNS zones) for ACR and Key Vault. Disables public network access on those services."
  type        = bool
  default     = false
}

# --- Container image / app --------------------------------------------------

variable "image_name" {
  description = "Container image repository name inside ACR."
  type        = string
  default     = "azure-ai-service"
}

variable "image_tag" {
  description = "Container image tag to deploy. CI passes the git SHA so each build rolls a new revision."
  type        = string
  default     = "latest"
}

variable "container_cpu" {
  description = "vCPU allocated to the container."
  type        = number
  default     = 0.5
}

variable "container_memory" {
  description = "Memory allocated to the container, e.g. 1Gi."
  type        = string
  default     = "1Gi"
}

variable "min_replicas" {
  description = "Minimum number of container replicas (0 enables scale-to-zero)."
  type        = number
  default     = 0
}

variable "max_replicas" {
  description = "Maximum number of container replicas."
  type        = number
  default     = 3
}

variable "enable_boom_endpoint" {
  description = "Expose /boom (returns HTTP 500) so the 5xx alert can be tested. Disable in prod."
  type        = bool
  default     = true
}

# --- LLM providers ----------------------------------------------------------

variable "enable_azure_openai" {
  description = "Provision Azure OpenAI and use it as the primary LLM provider. When false the service falls back to Groq (if configured)."
  type        = bool
  default     = true
}

variable "azure_openai_endpoint" {
  description = "Bring-your-own Azure OpenAI endpoint. Overrides the Terraform-provisioned account when set."
  type        = string
  default     = null
}

variable "azure_openai_key" {
  description = "Bring-your-own Azure OpenAI key. Overrides the Terraform-provisioned account when set."
  type        = string
  default     = null
  sensitive   = true
}

variable "azure_openai_deployment" {
  description = "Azure OpenAI chat model deployment name. Defaults to the Terraform-provisioned deployment."
  type        = string
  default     = null
}

variable "azure_openai_api_version" {
  description = "Azure OpenAI REST API version."
  type        = string
  default     = "2024-10-21"
}

variable "azure_openai_model" {
  description = "Model to deploy on the Terraform-provisioned Azure OpenAI account."
  type        = string
  default     = "gpt-4o-mini"
}

variable "azure_openai_model_version" {
  description = "Version of the model to deploy."
  type        = string
  default     = "2024-07-18"
}

variable "enable_groq_fallback" {
  description = "Enable the Groq fallback provider."
  type        = bool
  default     = true
}

variable "groq_api_key" {
  description = "Groq API key. Stored in Key Vault and injected at runtime. Leave null to deploy without Groq."
  type        = string
  default     = null
  sensitive   = true
}

variable "groq_model" {
  description = "Groq model used for the fallback provider."
  type        = string
  default     = "llama-3.1-8b-instant"
}

# --- Observability ----------------------------------------------------------

variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30
}

variable "alert_email" {
  description = "Email address notified by the 5xx alert action group. Leave null to create the action group without receivers."
  type        = string
  default     = null
}

variable "alert_5xx_threshold" {
  description = "Number of 5xx responses within the evaluation window that triggers the alert."
  type        = number
  default     = 5
}

variable "alert_window_size" {
  description = "Alert evaluation window (ISO8601 duration)."
  type        = string
  default     = "PT5M"
}

variable "alert_frequency" {
  description = "Alert evaluation frequency (ISO8601 duration)."
  type        = string
  default     = "PT1M"
}

# --- Governance -------------------------------------------------------------

variable "required_tags" {
  description = "Tag keys the required-tags policy enforces on resources in the resource group."
  type        = list(string)
  default     = ["environment", "project", "owner"]
}

variable "enforce_tag_policy" {
  description = "Deny (true) or audit (false) resources missing required tags."
  type        = bool
  default     = true
}
