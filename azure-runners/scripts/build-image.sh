#!/usr/bin/env bash
# Build the runner images in ACR (no local Docker needed):
#   1. base  = application/.github/self-hosted-runners/Dockerfile, unchanged
#   2. arc   = base + ARC entrypoint (image/)
# Usage: scripts/build-image.sh [path-to-application-repo]
set -euo pipefail

cd "$(dirname "$0")/.."
APP_REPO="${1:-../../potti}"
BASE_CTX="$APP_REPO/.github/self-hosted-runners"
[ -f "$BASE_CTX/Dockerfile" ] || { echo "no Dockerfile in $BASE_CTX" >&2; exit 1; }

ACR=$(terraform output -raw acr_name)
LOGIN=$(terraform output -raw acr_login_server)
TAG="${TAG:-$(git -C "$APP_REPO" rev-parse --short HEAD)-$(git rev-parse --short HEAD)}"

# The base build fetches from the ondrej/php PPA (Launchpad), which returns
# transient 503s. Retry the whole build a few times before giving up.
for attempt in 1 2 3; do
    az acr build -r "$ACR" -t "potti-ci-runner-base:$TAG" "$BASE_CTX" && break
    [ "$attempt" -eq 3 ] && { echo "base image build failed 3 times" >&2; exit 1; }
    echo "base image build failed (attempt $attempt), retrying in 60s" >&2
    sleep 60
done
az acr build -r "$ACR" -t "potti-ci-runner:$TAG" -t "potti-ci-runner:latest" \
    --build-arg "BASE_IMAGE=$LOGIN/potti-ci-runner-base:$TAG" image

echo "$LOGIN/potti-ci-runner:$TAG"
