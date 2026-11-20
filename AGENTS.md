# potti-terraform — agent guide

Infrastructure of Potti. Two independent Terraform stacks live here. Read this
file before planning or editing anything.

## Stacks

| Stack | Directory | Provider | State | Purpose |
|---|---|---|---|---|
| Production (OVH) | repo root (`*.tf`) | OpenStack, OVH, Cloudflare | **local** `terraform.tfstate` (git-ignored) | App servers, load balancer, PostgreSQL, Valkey, bastion, DNS. Described in `README.md`. |
| CI runners (Azure) | `azure-runners/` | azurerm | Azure Storage (`backend.hcl`) | AKS + Actions Runner Controller fleet for the `potti-org` GitHub Actions CI. Described in `azure-runners/README.md`. |

Never run Terraform for one stack from the other's directory. The root stack
has no remote backend: its state exists only on the maintainer's machine.

Other directories:

- `forge-recipes/`: shell recipes run on the app servers through Laravel Forge.
- `incidents/`: incident write-ups (date-prefixed Markdown).
- `scripts/`: operational scripts for the OVH stack.

## Safety rules

- `terraform plan` is free. **`terraform apply` and `destroy` need the user's
  explicit go**, every time: both stacks hold live systems (production, CI).
- Secrets never go into Git or Terraform state: `*.tfvars` and `backend.hcl`
  are git-ignored. Azure-side secrets live in Key Vault (Docker Hub token) or in
  a Kubernetes secret (GitHub App key), written by hand.
- Root stack: run through `./apply.sh` (`--plan-only` for a plan), which picks
  up `my_vars.tfvars`.

## CI system

The CI spans two repositories:

- **application** (`potti-org/application`): workflows, runner image
  Dockerfile, shard timings. Full reference: `docs/ci.md` in that repository,
  agent rule `.ai/rules/ci.md`.
- **this repository**: the runner infrastructure, `azure-runners/`. The OVH
  CI VM (`ci.tf`) was deleted on 2026-11-20.

A change to runner capacity, image, entrypoint or caches usually touches both.
The only runner entrypoint is `azure-runners/image/entrypoint-arc.sh`; the
application Dockerfile is the base image (toolchain, no entrypoint).
Keep `docs/ci.md` (application) and `azure-runners/README.md` (here) in sync.
Read `azure-runners/README.md` before changing anything in `azure-runners/`:
it lists the Azure constraints this subscription hits.
