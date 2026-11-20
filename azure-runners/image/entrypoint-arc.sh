#!/usr/bin/env bash
#
# ARC runner pod entrypoint (runs as root, pod is privileged).
#
# 1. Boots this pod's private Docker daemon (workflow service containers bind
#    127.0.0.1 inside the job, like on a GitHub-hosted runner).
# 2. Runs exactly one job with the JIT config ARC injects
#    (ACTIONS_RUNNER_INPUT_JITCONFIG), then exits. ARC deletes the pod.
set -euo pipefail

: "${ACTIONS_RUNNER_INPUT_JITCONFIG:?ARC did not inject a JIT config}"

cd /home/runner/actions-runner

# Shared node-level cache (hostPath, see helm/scale-set-values.yaml): composer,
# npm, Playwright browsers and the actions tool cache survive across pods on
# the same node.
CI_CACHE=/opt/ci-cache
mkdir -p "$CI_CACHE"/{composer,npm,ms-playwright,toolcache}
chown runner:runner "$CI_CACHE" "$CI_CACHE"/{composer,npm,ms-playwright,toolcache}

# The kubelet static CPU manager gives this Guaranteed pod an exclusive cpuset.
# PEST_TASKSET must name cores inside it (the workflow falls back to "0,1",
# which would be outside the set on most pods). Policy kept from the former OVH fleet:
# pin pest to the first two allowed cores.
allowed=$(taskset -pc $$ | awk -F': ' '{print $2}')
expand() {
    local IFS=, part
    for part in $1; do
        if [[ $part == *-* ]]; then seq "${part%-*}" "${part#*-}"; else echo "$part"; fi
    done
}
mapfile -t cores < <(expand "$allowed")
if [ "${#cores[@]}" -ge 2 ]; then
    PEST_TASKSET="${cores[0]},${cores[1]}"
else
    PEST_TASKSET="${cores[0]}"
fi

cat > .env <<ENV
COMPOSER_CACHE_DIR=$CI_CACHE/composer
npm_config_cache=$CI_CACHE/npm
PLAYWRIGHT_BROWSERS_PATH=$CI_CACHE/ms-playwright
RUNNER_TOOL_CACHE=$CI_CACHE/toolcache
PEST_TASKSET=$PEST_TASKSET
ENV
chown runner:runner .env

# Docker Hub pulls go through the ACR pull-through cache (no Docker Hub rate
# limit from the shared cluster egress IP). Unset = pull from Docker Hub.
mkdir -p /etc/docker
if [ -n "${DOCKER_REGISTRY_MIRROR:-}" ]; then
    printf '{"registry-mirrors":["%s"]}\n' "$DOCKER_REGISTRY_MIRROR" > /etc/docker/daemon.json
fi

dockerd > /var/log/dockerd.log 2>&1 &

for _ in $(seq 1 60); do
    docker info > /dev/null 2>&1 && break
    sleep 1
done
if ! docker info > /dev/null 2>&1; then
    echo "dockerd failed to start — tail of /var/log/dockerd.log:" >&2
    tail -n 40 /var/log/dockerd.log >&2 || true
    exit 1
fi

# runuser keeps the environment, so the runner sees the JIT config.
exec runuser -u runner -- ./run.sh
