# Azure CI runners (AKS + Actions Runner Controller)

Autoscaling GitHub Actions runners for `potti-org`, paid from Azure credit.
One pod per job, nodes scale from zero, Spot first with an on-demand fallback.

The whole CI system (workflows, runner fleet, repository variables, shard
tuning, optimization backlog) is documented in the application repository:
`docs/ci.md`. This file covers the Azure infrastructure. Keep both in sync.

This stack is independent from the OVH root of this repository: its own
provider (`azurerm`) and its own state (Azure Storage). Run every command from
this directory.

## Architecture

```
GitHub (potti-org) ── job queued for runs-on: potti-ci-azure
        │  (GitHub App potti-arc, long poll, no inbound port)
        ▼
AKS potti-ci-aks (France Central, Free tier)
  system pool ─ 1 × Standard_D2as_v7, always on
  │   arc-systems: ARC controller + potti-ci-azure listener
  │
  spot pool ─ Standard_D16ads_v7 Spot, 0–8 nodes      ┐ cluster autoscaler,
  regular pool ─ same size, on-demand, 0–6 nodes      ┘ priority: spot first
      arc-runners: 1 pod per job, 3 pods per node
        pod: 4 exclusive CPU, 14 GiB, privileged, own dockerd
             /var/lib/docker  → emptyDir (node local disk)
             /opt/ci-cache    → hostPath /var/lib/potti-ci-cache (shared per node)
        │ pulls
        ▼
ACR potticiacr (Standard, anonymous pull)
  potti-ci-runner-base:<tag>  application Dockerfile, unchanged
  potti-ci-runner:<tag|latest> base + entrypoint-arc.sh
  library/redis, pgvector/pgvector, atmoz/sftp  ← Docker Hub pull-through cache
        │ credential set (system identity)
        ▼
Key Vault potti-ci-kv-*: dockerhub-username, dockerhub-token
```

## Files

| Path | Role |
|---|---|
| `versions.tf` | azurerm `~> 4.0`, partial `azurerm` backend (values in `backend.hcl`). |
| `variables.tf` | Sizes, node counts, Docker Hub cache list and switch. |
| `main.tf` | Resource group, ACR + cache rules, Key Vault, AKS, node pools, AcrPull role. |
| `outputs.tf` | Names used by the scripts (`acr_name`, `aks_name`, `key_vault_name`, `docker_registry_mirror`…). |
| `terraform.tfvars` | Local, git-ignored: `subscription_id`, `dockerhub_cache_enabled = true`. |
| `backend.hcl` | Local, git-ignored: state storage account. Written by `bootstrap-state.sh`. |
| `image/Dockerfile` | `FROM` the base image, adds `entrypoint-arc.sh`. |
| `image/entrypoint-arc.sh` | Pod entrypoint: cache dirs, runner `.env`, registry mirror, `dockerd`, then `run.sh` with the JIT config ARC injects. |
| `helm/controller-values.yaml` | ARC controller on the system pool. |
| `helm/scale-set-values.yaml` | Scale set pod spec: image, resources, privileged, volumes, tolerations. Placeholders filled by `deploy-arc.sh`. |
| `k8s/autoscaler-priority.yaml` | Priority expander config: Spot pool before regular pool. |
| `scripts/bootstrap-state.sh` | One-time: state storage account (Entra ID auth, no keys) + `backend.hcl`. |
| `scripts/build-image.sh` | Builds base + ARC images in ACR (`az acr build`, no local Docker). Retries the base build 3 times. |
| `scripts/deploy-arc.sh` | Kube credentials, autoscaler config, GitHub App secret (first run), Helm install of controller and scale set. |

## Constraints of this subscription (learned the hard way)

- **VM sizes**: AKS in France Central only accepts the v7 generation here
  (`Standard_D*as_v7`, `D*ads_v7`, `E*_v7`, `F*_v7`…). v5 sizes are refused.
- **Quotas** (France Central): regional 128 vCPU, Dadsv7 family 350,
  **Spot 3 vCPU** (increase to 128 requested on 2026-11-17). Until Spot is
  raised, every runner node comes from the `regular` pool, so
  `regular_max_nodes` × 16 + 2 must stay ≤ 128.
  Check: `az vm list-usage -l francecentral -o table`.
- **Docker Hub cache rules need credentials**: ACR refuses them otherwise
  (`EnforceCacheRuleAuthentication`). Credentials sit in Key Vault and must
  exist before the cache rules are created (see Deploy).
- **Spot pools**: AKS adds the label and taint
  `kubernetes.azure.com/scalesetpriority=spot`; both are declared in `main.tf`
  to avoid drift. `upgrade_settings.max_surge` is forbidden on Spot pools, and
  must be declared (`10%`, AKS default) on the regular pool.
- **Launchpad** (`ppa:ondrej/php`) returns transient 503s during the base
  image build. `build-image.sh` retries.

## Deploy from scratch

Prerequisites: `az login`, Terraform ≥ 1.6, `kubectl`, `helm`, a Docker Hub
account with a read-only access token, org admin on `potti-org`.

```bash
scripts/bootstrap-state.sh
cp terraform.tfvars.example terraform.tfvars      # subscription_id, dockerhub_cache_enabled = true
terraform init -backend-config=backend.hcl

# Key Vault first: the Docker Hub cache rules read it at creation
terraform apply -target=azurerm_key_vault.ci -target=azurerm_role_assignment.kv_admin_operator
KV=$(terraform output -raw key_vault_name)
az keyvault secret set --vault-name "$KV" -n dockerhub-username --value <user>
az keyvault secret set --vault-name "$KV" -n dockerhub-token --value <token>
terraform apply

scripts/build-image.sh ../../potti                 # path to the application repo
```

GitHub App (org settings → Developer settings → GitHub Apps):
name `potti-arc`, webhook inactive, organization permission *Self-hosted
runners: Read and write* only, installable on this account only. Install it on
`potti-org`. Keep the App ID, the installation ID (end of the installation URL)
and a private key.

```bash
GITHUB_APP_ID=... \
GITHUB_APP_INSTALLATION_ID=... \
GITHUB_APP_PRIVATE_KEY_FILE=~/Downloads/potti-arc.*.pem \
scripts/deploy-arc.sh
```

Then store the `.pem` in the password manager and delete the download.

Check: `kubectl -n arc-systems get pods` shows the controller and a
`potti-ci-azure-…-listener` pod Running; GitHub lists `potti-ci-azure` under
org Settings → Actions → Runners.

## Repository variables

`application`'s workflows read repository variables (Settings → Secrets and
variables → Actions → Variables):

| Variable | Default in the workflow | Current value |
|---|---|---|
| `CI_RUNS_ON` | `["potti-ci-azure"]` | `["potti-ci-azure"]` |
| `CI_TEST_SHARDS` | 5 | 10 |
| `CI_BROWSER_SHARDS` | 3 | 7 |
| `CI_TEST_PROCESSES` | 3 | 5 |
| `CI_BROWSER_PROCESSES` | 2 | 3 |

There is no other fleet: the OVH CI VM was deleted on 2026-11-20. Jobs that
lose their Spot node are rerun by `.github/workflows/ci-retry-lost-runners.yml` (active once on
`main`).

Capacity check before raising shard counts: concurrent runs × (tests +
browser shards + 2) ≤ `MAX_RUNNERS` (24) and ≤ 3 × available nodes.

## Common changes

| Change | Steps |
|---|---|
| Runner image (Dockerfile in application) | `scripts/build-image.sh ../../potti`. It pushes `:latest`, which new pods use at once. `deploy-arc.sh` is only needed when the pod spec changes. |
| Runner entrypoint (`image/entrypoint-arc.sh`, the only one) | Same as above. |
| Pod CPU / memory | `helm/scale-set-values.yaml` (requests = limits, integer CPU), `deploy-arc.sh`, then `--processes` in the workflow. |
| Node size or count | `variables.tf` (or `terraform.tfvars`), `terraform apply`. Check quota first. |
| Max concurrent runners | `MAX_RUNNERS=… scripts/deploy-arc.sh`. |
| New Docker Hub service image | Add to `dockerhub_cached_repos`, `terraform apply`, before the workflow uses it. |
| ARC version | `ARC_VERSION=… scripts/deploy-arc.sh`. Read the release notes: some upgrades need the CRDs reinstalled. |
| GitHub App key rotation | New key in the App settings, `kubectl -n arc-runners delete secret arc-github-app`, rerun `deploy-arc.sh` with the `GITHUB_APP_*` variables. |
| Docker Hub token rotation | `az keyvault secret set … -n dockerhub-token`. No apply needed. |

## Operations

- Nodes: `kubectl get nodes -L kubernetes.azure.com/scalesetpriority,potti.ci/role`.
- Runner pods: `kubectl -n arc-runners get pods -o wide`.
- Why a pod is Pending: `kubectl -n arc-runners describe pod <pod>` (quota,
  taints, resources).
- Listener logs: `kubectl -n arc-systems logs <potti-ci-azure-…-listener pod>`.
- AKS patches and node images update automatically, Sunday 03:00–07:00.
- Drift check: `terraform plan` must print "No changes".

## Known limits

- A Spot eviction kills the jobs of that node; the retry workflow reruns them.
- Node-level caches (`/var/lib/potti-ci-cache`: composer, npm, Playwright,
  tool cache, `vendor/` snapshots) die with the node: the first job on a new
  node is cold.
- Docker layer cache is per pod: service images are pulled for every job, from
  the ACR cache in the same region.
- Anonymous pull is on for ACR: anyone knowing the registry name can pull the
  runner image and cached public images. The image must never contain a secret.
- The entrypoint still exports `PEST_TASKSET` (first 2 of the pod's cores) for
  compatibility, but since application PR #2413 the workflow runs pest
  unpinned with `--processes`, bounded by the pod's 4 exclusive cores.

## Rollout status

- [x] State storage, Terraform applied, Docker Hub cache, Key Vault.
- [x] Runner image in ACR (`potti-ci-runner:latest`).
- [x] GitHub App created, `deploy-arc.sh` run.
- [x] Every CI run on this fleet since 2026-11-17.
- [ ] Spot quota granted.
- [x] OVH CI VM deleted (2026-11-20). There is no fallback fleet.
