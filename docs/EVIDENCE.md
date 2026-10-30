# Verification Evidence

**Date:** 2026-10-30 (UTC)
**Repository:** `farheenfathimaa/azure-ai-service-infra`
**Environment:** Ubuntu 26.04, no Docker daemon, no Azure CLI (`az`), no GitHub CLI (`gh`).

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
| Azure CLI (`az`) | **not installed** |
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
| actionlint on `.github/workflows` | **PASS** | [linters.txt](evidence/linters.txt) | Exit 0. |
| ShellCheck on `scripts/*.sh` and `infra/bootstrap/bootstrap.sh` | **PASS** | [linters.txt](evidence/linters.txt) | Exit 0. |
| TFLint on `infra/terraform` | **PASS** | [linters.txt](evidence/linters.txt) | Exit 0 (bundled `ruleset.terraform` 0.10.0). |
| Checkov on `infra/terraform` | **FAIL (advisory)** | [checkov.txt](evidence/checkov.txt) | 7 passed, 20 failed, 0 skipped. All findings are hardening/feature gaps or documented dev-cost tradeoffs; see below. |
| Secret scan (keys, private keys, client secrets, UUIDs, emails) | **PASS** | [secret-scan.txt](evidence/secret-scan.txt) | No `gsk_` keys, private keys, client secrets, storage keys, SAS tokens, or UUIDs. Only the placeholder address in `terraform.tfvars.example` and the test literal in `test_app.py` matched. |
| README/layout/variables/outputs/workflow completeness audit | **PASS** | [completeness-audit.txt](evidence/completeness-audit.txt) | 24/24 checks pass. |
| `az account show` | **NOT RUN** | [azure-verification.txt](evidence/azure-verification.txt) | Azure CLI not installed. |
| Azure deploy + live `/health` on FQDN | **NOT RUN** | [azure-verification.txt](evidence/azure-verification.txt) | No Azure login; no deployment attempted. |
| 20 × `/boom` + 5xx alert fired + email received | **NOT RUN** | [azure-verification.txt](evidence/azure-verification.txt) | No Azure login; alert/email cannot be confirmed. |
| `terraform destroy` clean teardown | **NOT RUN** | [azure-verification.txt](evidence/azure-verification.txt) | No Azure login; destroy not attempted. |
| CI workflow runs (`gh run list`) | **NOT RUN** (`gh`) / **FAIL (expected)** (API) | [github-actions.txt](evidence/github-actions.txt) | `gh` not installed; the public GitHub Actions API was used instead. `terraform-apply` on `f0e2a04` failed at the `Azure login (OIDC)` step. `app-ci` last passed on `d779029`; `terraform-plan` has no runs (no PR). |

### CI failure detail

The pushed `terraform-apply` run (`f0e2a04`) failed at **Azure login (OIDC)**; every
Terraform/build/deploy step was skipped. The job log endpoint requires repository
admin auth (API returned 403), so the exact login message was not retrievable.
This is the expected failure until the `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and
`AZURE_SUBSCRIPTION_ID` repository variables and the matching OIDC federated
credential exist. `app-ci` did not re-run for this push because no `app/**` file
changed; its last run on the initial commit passed.

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

Verified locally: unit tests, host-process endpoints, Terraform formatting and
validation, workflow/shell/Terraform linting, secret scan, and structural
completeness.

Not verified: the Docker image, any live Azure resource, the live `/health`
endpoint, the 5xx alert firing/email delivery, clean `terraform destroy`, and CI
workflow execution. The project should **not** be described as "deployed" based on
this evidence.
