#Requires -Version 5.1
<#
.SYNOPSIS
    Creates a secretless GitHub Actions OIDC identity (app registration +
    federated credentials) and the RBAC it needs.

.DESCRIPTION
    Creates an Entra ID application, a service principal, and two federated
    credentials (one for pull requests, one for the main branch). It then grants
    the required roles. No client secret is ever created or stored.

    Required roles granted on the subscription:
      * Contributor              - create/update the workload resources
      * User Access Administrator - create the role assignments Terraform defines
    And on the Terraform state storage account:
      * Storage Blob Data Contributor - read/write remote state without keys

.EXAMPLE
    ./setup-oidc.ps1 -GitHubRepo contoso/azure-ai-service-infra `
                     -StateStorageAccountId /subscriptions/.../storageAccounts/sttfstate123456
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GitHubRepo,

    [string]$SubscriptionId = $env:ARM_SUBSCRIPTION_ID,

    [string]$AppDisplayName = 'gh-azure-ai-service-infra',

    # Optional: scope the state RBAC. Pass the storage account resource ID.
    [string]$StateStorageAccountId,

    # Optional: also add an environment federated credential (e.g. "production").
    [string]$Environment = ''
)

$ErrorActionPreference = 'Stop'

if ($SubscriptionId) {
    az account set --subscription $SubscriptionId | Out-Null
}
$currentSub = az account show --query id -o tsv
$tenantId = az account show --query tenantId -o tsv
Write-Host "Subscription: $currentSub"
Write-Host "Tenant:       $tenantId"

Write-Host "Creating app registration '$AppDisplayName'"
$appId = az ad app create --display-name $AppDisplayName --query appId -o tsv
if (-not $appId) { $appId = az ad app list --display-name $AppDisplayName --query "[0].appId" -o tsv }

Write-Host "Ensuring service principal exists"
$spObjectId = az ad sp list --filter "appId eq '$appId'" --query "[0].id" -o tsv
if (-not $spObjectId) {
    $spObjectId = az ad sp create --id $appId --query id -o tsv
}

function New-FederatedCredential {
    param([string]$Name, [string]$Subject, [string]$Issuer = 'https://token.actions.githubusercontent.com', [string[]]$Audiences = @('api://AzureADTokenExchange'))
    $existing = az ad app federated-credential list --id $appId --query "[?name=='$Name'].name" -o tsv
    if ($existing) { Write-Host "  federated credential '$Name' already exists"; return }
    $payload = @{
        name      = $Name
        issuer    = $Issuer
        subject   = $Subject
        audiences = $Audiences
    } | ConvertTo-Json -Compress
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $payload -Encoding utf8
    az ad app federated-credential create --id $appId --parameters "@$tmp" | Out-Null
    Remove-Item $tmp -Force
    Write-Host "  created federated credential '$Name' ($Subject)"
}

Write-Host "Creating federated credentials"
New-FederatedCredential -Name 'github-pull-request' -Subject "repo:${GitHubRepo}:pull_request"
New-FederatedCredential -Name 'github-main'         -Subject "repo:${GitHubRepo}:ref:refs/heads/main"
if ($Environment) {
    New-FederatedCredential -Name "github-env-$Environment" -Subject "repo:${GitHubRepo}:environment:${Environment}"
}

Write-Host "Granting subscription roles"
az role assignment create --assignee-object-id $spObjectId --assignee-principal-type ServicePrincipal `
    --role "Contributor" --scope "/subscriptions/$currentSub" | Out-Null
az role assignment create --assignee-object-id $spObjectId --assignee-principal-type ServicePrincipal `
    --role "User Access Administrator" --scope "/subscriptions/$currentSub" | Out-Null

if ($StateStorageAccountId) {
    Write-Host "Granting Storage Blob Data Contributor on the state account"
    az role assignment create --assignee-object-id $spObjectId --assignee-principal-type ServicePrincipal `
        --role "Storage Blob Data Contributor" --scope $StateStorageAccountId | Out-Null
}

Write-Host ""
Write-Host "OIDC setup complete. Set these as GitHub Actions repository VARIABLES" -ForegroundColor Green
Write-Host "(Settings -> Secrets and variables -> Actions -> Variables):"
Write-Host "  AZURE_CLIENT_ID       = $appId"
Write-Host "  AZURE_TENANT_ID       = $tenantId"
Write-Host "  AZURE_SUBSCRIPTION_ID = $currentSub"
Write-Host ""
Write-Host "Also set the Terraform backend variables: TF_STATE_RESOURCE_GROUP,"
Write-Host "TF_STATE_STORAGE_ACCOUNT, TF_STATE_CONTAINER."
