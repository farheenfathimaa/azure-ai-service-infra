locals {
  require_tag_json      = jsondecode(file("${path.module}/policies/require-tag.json"))
  deny_public_blob_json = jsondecode(file("${path.module}/policies/deny-public-blob.json"))

  # Resource types that do not support tags; exempted from the required-tags policy.
  tag_policy_excluded_types = [
    "Microsoft.Authorization/roleAssignments",
    "Microsoft.Authorization/policyAssignments",
    "Microsoft.Authorization/policyDefinitions",
    "Microsoft.Network/virtualNetworks/subnets",
    "Microsoft.Network/privateEndpoints/privateDnsZoneGroups",
    "Microsoft.KeyVault/vaults/secrets",
    "Microsoft.CognitiveServices/accounts/deployments",
    "Microsoft.Insights/diagnosticSettings",
  ]
}

resource "azurerm_policy_definition" "require_tag" {
  name         = "require-tag-${local.name_prefix}"
  display_name = "Require a tag on resources (${var.environment})"
  description  = "Denies or audits resources that are missing a required tag."
  policy_type  = "Custom"
  mode         = local.require_tag_json.mode

  policy_rule = jsonencode(local.require_tag_json.policyRule)
  parameters  = jsonencode(local.require_tag_json.parameters)
}

resource "azurerm_policy_definition" "deny_public_blob" {
  name         = "deny-public-blob-${local.name_prefix}"
  display_name = "Deny public blob access on storage accounts (${var.environment})"
  description  = "Prevents storage accounts from allowing anonymous public access to blobs."
  policy_type  = "Custom"
  mode         = local.deny_public_blob_json.mode

  policy_rule = jsonencode(local.deny_public_blob_json.policyRule)
  parameters  = jsonencode(local.deny_public_blob_json.parameters)
}

# One assignment per required tag, scoped to the workload resource group.
resource "azurerm_resource_group_policy_assignment" "require_tag" {
  for_each = toset(var.required_tags)

  name                 = substr("require-tag-${each.value}", 0, min(24, length("require-tag-${each.value}")))
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = azurerm_policy_definition.require_tag.id
  description          = "Require the '${each.value}' tag."

  parameters = jsonencode({
    tagName               = each.value
    effect                = var.enforce_tag_policy ? "deny" : "audit"
    excludedResourceTypes = local.tag_policy_excluded_types
  })
}

resource "azurerm_resource_group_policy_assignment" "deny_public_blob" {
  name                 = "deny-public-blob"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = azurerm_policy_definition.deny_public_blob.id
  description          = "Deny storage accounts that allow anonymous public blob access."

  parameters = jsonencode({
    effect = "Deny"
  })
}
