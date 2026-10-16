#Requires -Version 5.1
<#
.SYNOPSIS
    Destroys the Terraform-managed stack.

.DESCRIPTION
    Runs `terraform destroy` against the remote state. Pass -DestroyBootstrap to
    also delete the remote-state resource group, and -DestroyOidc (with
    -ClientId) to delete the GitHub OIDC app registration.
#>
[CmdletBinding()]
param(
    [switch]$DestroyBootstrap,
    [switch]$DestroyOidc,
    [string]$ClientId,
    [string]$StateResourceGroup = 'rg-tfstate',
    [string]$AutoApprove = '-auto-approve'
)

$ErrorActionPreference = 'Stop'
$tfDir = Join-Path $PSScriptRoot '..\infra\terraform' | Resolve-Path

Write-Host "Destroying workload stack in $tfDir"
Push-Location $tfDir
try {
    terraform init -backend-config=backend.hcl -input=false
    terraform destroy $AutoApprove
}
finally {
    Pop-Location
}

if ($DestroyBootstrap) {
    Write-Host "Deleting remote-state resource group $StateResourceGroup"
    az group delete --name $StateResourceGroup --yes --no-wait
}

if ($DestroyOidc) {
    if (-not $ClientId) { throw "-ClientId is required with -DestroyOidc" }
    Write-Host "Deleting OIDC app registration $ClientId"
    az ad app delete --id $ClientId
}

Write-Host "Teardown complete." -ForegroundColor Green
