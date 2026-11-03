# Verification Evidence

**Date:** 2026-10-30, with live Azure setup added 2026-11-01 (UTC)
**Repository:** `farheenfathimaa/azure-ai-service-infra`
**Environment:** Ubuntu 26.04, no Docker daemon, no GitHub CLI (`gh`). Azure CLI
2.91.0 was installed and logged in on 2026-11-01; the local checks above were
run before that, so they used `init -backend=false`.

Every result below comes from a command that was actually run. Raw output is in
[`docs/evidence/`](evidence/). Tools were installed **locally** for this run
(`/tmp/opencode` and a user-level `uv` tool directory); no system/global packages
were installed and no Azure resources were created, changed, or deleted.

## Versions

| Tool | Version |
| --- | --- |
| Python (test venv) | 3.11.18 |
| Python (system) | 3.14.4 |
| pip | 26.2.2 |
| pytest | 8.3.4 |
| Terraform | 1.9.8 |
| Docker | **not installed** |
| Azure CLI (`az`) | 2.91.0 (installed 2026-11-01) |
| GitHub CLI (`gh`) | **not installed** |
| actionlint | 1.7.7 |
| ShellCheck | 0.10.0 |
| TFLint | 0.55.1 |
| Checkov | 3.4.0 |
| git | 2.53.0 |

## Checks

| Check | Result | Evidence | Notes |
| --- | --- | --- | --- |
| Python dependency install + pytest | **PASS** | [pytest.txt](evidence/pytest.txt) | 6 passed, 1 third-party deprecation warning, 0 failed. |
| Docker build + container smoke (`/health`, `/ask`, `/boom`) | **NOT RUN** | [docker-smoke.txt](evidence/docker-smoke.txt) | Docker CLI/daemon unavailable; installing it needs root. No Docker build was executed. |
| Host-process endpoint smoke (supplementary, **not** Docker) | **PASS** | [local-smoke.txt](evidence/local-smoke.txt) | uvicorn with `LLM_PROVIDER=echo ALLOW_BOOM=true`: `/health` 200, `/ask` 200, `/boom` 500. |
| Terraform `fmt -check -recursive`, `init -backend=false`, `validate` | **PASS** | [terraform-validate.txt](evidence/terraform-validate.txt) | All three exit codes 0. |
| Terraform optional-value null safety | **PASS** | [terraform-locals-null-check.txt](evidence/terraform-locals-null-check.txt) | Isolated `terraform console` test: null, empty, and whitespace-only inputs normalize to null; real values pass through. |
| actionlint on `.github/workflows` | **PASS** | [linters.txt](evidence/linters.txt) | Exit 0. |
| ShellCheck on `scripts/*.sh` and `infra/bootstrap/bootstrap.sh` | **PASS** | [linters.txt](evidence/linters.txt) | Exit 0. |
| TFLint on `infra/terraform` | **PASS** | [linters.txt](evidence/linters.txt) | Exit 0 (bundled `ruleset.terraform` 0.10.0). |
| Checkov on `infra/terraform` | **FAIL (advisory)** | [checkov.txt](evidence/checkov.txt) | 7 passed, 20 failed, 0 skipped. All findings are hardening/feature gaps or documented dev-cost tradeoffs; see below. |
| Secret scan (keys, private keys, client secrets, UUIDs, emails) | **PASS** | [secret-scan.txt](evidence/secret-scan.txt) | No `gsk_` keys, private keys, client secrets, storage keys, SAS tokens, or UUIDs. Only the placeholder address in `terraform.tfvars.example` and the test literal in `test_app.py` matched. |
| README/layout/variables/outputs/workflow completeness audit | **PASS** | [completeness-audit.txt](evidence/completeness-audit.txt) | 24/24 checks pass. |
| `az account show` + provider registration + remote-state bootstrap + OIDC identity | **PASS** | [azure-setup.txt](evidence/azure-setup.txt) | Subscription enabled; 12 resource providers registered; state backend recreated as `sttfstate2380610774` after the first teardown; app registration with legacy **and** immutable-subject federated credentials; Contributor + User Access Administrator + Storage Blob Data Contributor verified. |
| `terraform plan` against real Azure (AAD backend) | **PASS** | [terraform-plan-azure.txt](evidence/terraform-plan-azure.txt) | First run exposed a real `Invalid for_each argument` bug (secret key set derived from an apply-time value); fixed in `locals.tf`. After the fix: 26 to add (default), 22 to add with `llm_provider = "echo"`. |
| Azure deploy + live `/health` on FQDN | **PASS** | [azure-deploy.txt](evidence/azure-deploy.txt), [github-actions.txt](evidence/github-actions.txt) | Local apply added 17 resources; a full GitHub Actions run (`41688133667`) then deployed end-to-end in echo mode. `/health` 200, `/ask` 200, `/boom` 500 on the stable FQDN. |
| 20 × `/boom` + 5xx alert fired + email received | **PASS (alert) / NOT VERIFIED (email)** | [azure-deploy.txt](evidence/azure-deploy.txt), [github-actions.txt](evidence/github-actions.txt) | Alert `alert-http5xx-azureaisvc-dev` fired in both deploy cycles (`2026-11-02T02:08:09Z`, `2026-11-03T17:54:02Z`) with the configured email receiver. Email delivery needs the Azure action-group confirmation link to be clicked by the receiver. |
| `terraform destroy` clean teardown | **PASS** | [azure-deploy.txt](evidence/azure-deploy.txt) | `Destroy complete!` after a transient DNS abort; state empty, `rg-tfstate` deleted, only Azure's free auto-created `NetworkWatcherRG` remains. |
| CI workflow runs (`terraform-apply`) | **PASS** | [github-actions.txt](evidence/github-actions.txt) | Run `41688133667` on `d3a8fbd`: all 12 steps succeeded (OIDC, init, ACR bootstrap, docker build/push, apply, outputs, revision roll, `/health`). Earlier runs exposed and fixed three real CI bugs: missing repo variables, immutable OIDC subject, and lost state-account RBAC after re-bootstrap. |

### CI history

The first `terraform-apply` runs failed at **Azure login (OIDC)** because the
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` repository
variables did not exist. After they were configured, run `41621340867` got past
login but failed at `terraform init` for two independent reasons, both fixed:

1. **Immutable OIDC subject.** GitHub presented
   `repo:farheenfathimaa@118092949/azure-ai-service-infra@1422058546:ref:refs/heads/main`,
   which did not match the legacy `repo:owner/repo:...` credential
   (`AADSTS700213`). `scripts/setup-oidc.sh` / `.ps1` now register both formats.
2. **Lost state RBAC.** Recreating `rg-tfstate` deleted the OIDC service
   principal's `Storage Blob Data Contributor` assignment (bootstrap only granted
   the signed-in user). The role was re-granted and `bootstrap.sh` now accepts
   `CI_PRINCIPAL_ID` to do this automatically.

Run `41622252592` then succeeded, but exposed a latent bug: `container_app_fqdn`
used `latest_revision_fqdn`, which changes on every revision roll, so the smoke
test URL 404'd once the pre-roll revision deactivated. The outputs now use the
stable `ingress[0].fqdn`. Run `41688133667` on `d3a8fbd` passed all 12 steps with
that fix. Raw step-level output: [github-actions.txt](evidence/github-actions.txt).

## Checkov disposition

The 20 findings are **advisory**, not functional failures. They are either
documented cost/dev tradeoffs or features outside this project's scope:

- **Key Vault** (`CKV_AZURE_109`, `_110`, `_189`, `_41`, `_42`): public network
  access is intentionally allowed when private endpoints are off; purge protection
  is intentionally disabled so `destroy` can purge the vault; provider keys have no
  expiry because they are rotated by redeployment. These are documented in the
  README.
- **Azure OpenAI** (`CKV_AZURE_134`, `_236`, `_238`, `_247`, `CKV2_AZURE_22`):
  the app authenticates with the account key, so disabling local auth would break
  it; public networking, managed identity auth, CMK, and DLP are not implemented.
- **ACR Basic SKU** (`CKV_AZURE_139`, `_163`–`_167`, `_233`, `_237`): zone
  redundancy, geo-replication, signed images, quarantine, vulnerability scanning,
  retention, and dedicated endpoints are paid/enterprise features; the stack uses
  Basic for cost. Public networking is tied to `enable_private_endpoints`.
- **Subnets** (`CKV2_AZURE_31`, reported twice): no explicit NSGs are attached.

No code was changed to silence these findings. If any become requirements, they
need separate design/approval (and some add cost).

## What was verified vs. not verified

Verified: unit tests, host-process endpoints, Terraform formatting/validation,
workflow/shell/Terraform linting, secret scan, structural completeness, real
Azure provisioning, the live `/health` `/ask` `/boom` endpoints, the 5xx metric
alert firing, a clean `terraform destroy`, and a full GitHub Actions
`terraform-apply` run (run `41688133667`, all 12 steps).

Not verified: alert **email delivery** (the Azure action-group confirmation link
has not been clicked by the receiver), and `app-ci` / `terraform-plan` runs after
the latest commits (they only trigger on `app/**` changes or pull requests).
Both deployed stacks were torn down after verification, so no URLs remain live.
