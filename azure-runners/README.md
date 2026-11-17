# Azure CI runners (AKS + Actions Runner Controller)

Autoscaling GitHub Actions runners for `potti-org`, paid from Azure credit.
One pod per job, nodes scale from zero, Spot first with an on-demand fallback.

The whole CI system (workflows, both fleets, repository variables, shard
tuning, optimization backlog) is documented in the application repository:
`docs/ci.md`. Keep both documents in sync.

This stack is independent from the OVH root of this repository: its own
provider (`azurerm`) and its own state (Azure Storage). Run every command from
this directory.

## Architecture

- **AKS** (Free tier), France Central.
  - `system` pool: 1 × `Standard_D2ads_v5`, always on. Hosts the ARC controller
    and the scale-set listener.
  - `spot` pool: `Standard_D16ads_v5` Spot, autoscale 0–8. Kubelet static CPU
    manager, ephemeral OS disk on local SSD.
  - `regular` pool: same size, on-demand, autoscale 0–3. Used only when Spot
    cannot be allocated (cluster autoscaler `priority` expander).
- **Runner pod**: 4 CPU (exclusive cores) / 14 GiB, privileged, own `dockerd`.
  Same image as the OVH fleet plus an ARC entrypoint, so the workflows'
  service containers (pgvector, Redis, SFTP) work unchanged. 3 pods per node.
- **Caches**: composer, npm, Playwright browsers and the tool cache live in a
  hostPath shared by the pods of a node. Docker layers are per pod.
- **ACR** (Standard): runner image + pull-through cache for the Docker Hub
  service images (avoids Docker Hub rate limits from the shared egress IP).
  Anonymous pull is on: the runner image must never contain a secret.
- **Network**: no inbound port. Runners only call GitHub, registries, Packagist,
  npm and the Playwright CDN.

## Prerequisites

1. `az login`, Terraform >= 1.6, `kubectl`, `helm` (`brew install helm`).
2. **Quota** (Portal → Quotas → Compute, France Central). Current values are
   too low for the Spot pool:
   - *Total Regional Spot vCPUs*: request 128 (8 nodes × 16).
   - *Standard DADSv5 Family vCPUs*: request ≥ 2 + 48 (system + fallback).
3. **GitHub App** on `potti-org` (org admin):
   - Organization permission *Self-hosted runners: Read and write*.
   - No webhook. Install it on the organisation.
   - Keep the App ID, the installation ID and a private key (`.pem`).

## Deploy

```bash
scripts/bootstrap-state.sh                 # once: state storage + backend.hcl
cp terraform.tfvars.example terraform.tfvars  # set subscription_id
terraform init -backend-config=backend.hcl
terraform apply

# Docker Hub pull-through cache (ACR requires Docker Hub credentials).
# Free Docker Hub account + read-only access token is enough.
KV=$(terraform output -raw key_vault_name)
az keyvault secret set --vault-name "$KV" -n dockerhub-username --value <user>
az keyvault secret set --vault-name "$KV" -n dockerhub-token --value <token>
terraform apply -var dockerhub_cache_enabled=true   # or set it in terraform.tfvars

scripts/build-image.sh ../../potti         # path to the application repo

GITHUB_APP_ID=... \
GITHUB_APP_INSTALLATION_ID=... \
GITHUB_APP_PRIVATE_KEY_FILE=~/Downloads/potti-arc.pem \
scripts/deploy-arc.sh
```

The scale set registers as `potti-ci-azure`. A job targets it with
`runs-on: potti-ci-azure`. The OVH fleet (`[self-hosted, potti-ci]`) is not
affected until a workflow is switched.

## Rollout plan

1. Run a test branch of `application` with `runs-on: potti-ci-azure` and
   compare durations with the OVH fleet.
2. After PR #2413 lands: adapt the CI to the new capacity (more shards,
   time-based sharding, retry of jobs lost to Spot eviction).
3. Switch `laravel-ci.yml` and `marketing-capture.yml`, then retire `ci.tf`.

## Operations

- Nodes and pods: `kubectl get nodes -L kubernetes.azure.com/scalesetpriority`,
  `kubectl -n arc-runners get pods`.
- New runner image (Dockerfile change in `application`): rerun
  `scripts/build-image.sh`, then `scripts/deploy-arc.sh`.
- ARC upgrade: bump `ARC_VERSION`. Major upgrades may need the CRDs reinstalled,
  read the release notes first.
- AKS patches and node images update automatically on Sunday nights.

## Known limits

- A Spot eviction kills the jobs on that node. Rerun the failed jobs until the
  workflow retries them automatically.
- Docker layer cache is per pod: service images are pulled for each job, from
  the ACR cache in the same region.
- The entrypoint still exports `PEST_TASKSET` (first 2 of the pod's cores) for
  compatibility, but since PR #2413 the workflow runs pest unpinned with
  `--processes`, bounded by the pod's 4 exclusive cores.

## Switching the CI to this fleet

`application`'s workflows read repository variables (Settings → Secrets and
variables → Actions → Variables), so no code change is needed:

| Variable | OVH (default) | Azure |
|---|---|---|
| `CI_RUNS_ON` | unset (`["self-hosted","potti-ci"]`) | `["potti-ci-azure"]` |
| `CI_TEST_SHARDS` | unset (5) | e.g. `15` |
| `CI_BROWSER_SHARDS` | unset (3) | e.g. `8` |

Deleting the variables switches back to OVH. Jobs that lose their Spot node
are rerun by `.github/workflows/ci-retry-lost-runners.yml` (active once on
`main`).
