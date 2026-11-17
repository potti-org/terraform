#!/usr/bin/env bash
# Install / upgrade Actions Runner Controller and the potti scale set.
#
# Required env on first run (stored as a Kubernetes secret, never in Terraform
# state): GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID,
# GITHUB_APP_PRIVATE_KEY_FILE (path to the .pem).
#
# Optional env:
#   RUNNER_IMAGE      default <acr>/potti-ci-runner:latest
#   SCALE_SET_NAME    default potti-ci-azure (the `runs-on` value)
#   MAX_RUNNERS       default 24
#   ARC_VERSION       chart version, check
#                     https://github.com/actions/actions-runner-controller/releases
set -euo pipefail

cd "$(dirname "$0")/.."
ORG_URL="${ORG_URL:-https://github.com/potti-org}"
ARC_VERSION="${ARC_VERSION:-0.12.1}"
SCALE_SET_NAME="${SCALE_SET_NAME:-potti-ci-azure}"
MAX_RUNNERS="${MAX_RUNNERS:-24}"
CHARTS=oci://ghcr.io/actions/actions-runner-controller-charts

RG=$(terraform output -raw resource_group)
AKS=$(terraform output -raw aks_name)
LOGIN=$(terraform output -raw acr_login_server)
MIRROR=$(terraform output -raw docker_registry_mirror)
RUNNER_IMAGE="${RUNNER_IMAGE:-$LOGIN/potti-ci-runner:latest}"

az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing
kubectl apply -f k8s/autoscaler-priority.yaml

kubectl create namespace arc-systems --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace arc-runners --dry-run=client -o yaml | kubectl apply -f -

if ! kubectl -n arc-runners get secret arc-github-app > /dev/null 2>&1; then
    : "${GITHUB_APP_ID:?}" "${GITHUB_APP_INSTALLATION_ID:?}" "${GITHUB_APP_PRIVATE_KEY_FILE:?}"
    kubectl -n arc-runners create secret generic arc-github-app \
        --from-literal=github_app_id="$GITHUB_APP_ID" \
        --from-literal=github_app_installation_id="$GITHUB_APP_INSTALLATION_ID" \
        --from-file=github_app_private_key="$GITHUB_APP_PRIVATE_KEY_FILE"
fi

helm upgrade --install arc "$CHARTS/gha-runner-scale-set-controller" \
    --version "$ARC_VERSION" -n arc-systems -f helm/controller-values.yaml --wait

values=$(mktemp)
trap 'rm -f "$values"' EXIT
sed -e "s|__RUNNER_IMAGE__|$RUNNER_IMAGE|" \
    -e "s|__DOCKER_REGISTRY_MIRROR__|$MIRROR|" helm/scale-set-values.yaml > "$values"

helm upgrade --install "$SCALE_SET_NAME" "$CHARTS/gha-runner-scale-set" \
    --version "$ARC_VERSION" -n arc-runners -f "$values" \
    --set githubConfigUrl="$ORG_URL" \
    --set runnerScaleSetName="$SCALE_SET_NAME" \
    --set minRunners=0 --set maxRunners="$MAX_RUNNERS" \
    --wait

kubectl -n arc-systems get pods
