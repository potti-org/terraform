# ARC variant of the Potti CI runner image.
#
# Built FROM the fleet image defined in application/.github/self-hosted-runners
# (same toolchain: PHP 8.4, Composer, Node 24, Playwright deps, private dockerd).
# Only the entrypoint changes: ARC hands each pod a just-in-time runner config,
# so there is no registration loop and no PAT inside the pod.
#
# Build with scripts/build-image.sh (builds the base first, then this layer).
ARG BASE_IMAGE=potti-ci-runner-base:latest
FROM ${BASE_IMAGE}

COPY entrypoint-arc.sh /usr/local/bin/entrypoint-arc.sh
RUN chmod +x /usr/local/bin/entrypoint-arc.sh

ENTRYPOINT ["/usr/local/bin/entrypoint-arc.sh"]
