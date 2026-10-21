#!/usr/bin/env bash
#
# External exposure check. Run from OUTSIDE OVH (laptop, GitHub Actions runner).
#
# Security groups are the only real firewall in front of the app servers, and rules
# added by hand in the OVH console are invisible to `terraform plan` (incident
# 2026-10-21: two "Temporary" rules opened 443 and 49984 to 0.0.0.0/0). This script
# checks what the internet actually sees and exits 1 on any drift.
#
# Requires Linux (bash /dev/tcp + coreutils timeout) and curl >= 7.60.
#

set -uo pipefail

LB_HOST="${LB_HOST:-potti.co}"
APP_HOSTS="${APP_HOSTS:-app-eu-west-par-a-1.potti.co app-eu-west-par-b-1.potti.co}"
# Nothing on an app server may answer the internet directly. 20186 (/up) is open to
# Oh Dear IPs only, so it must be closed from here as well.
APP_CLOSED_PORTS="${APP_CLOSED_PORTS:-22 80 443 631 3306 5432 6379 9000 20184 20185 20186 49984}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"

failures=0

pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }

port_open() {
  timeout "${CONNECT_TIMEOUT}" bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}

http_code() {
  curl -s -o /dev/null -m 15 -w '%{http_code}' "$@" || true
}

echo "== Load balancer (${LB_HOST})"

code="$(http_code "https://${LB_HOST}/up")"
[[ "${code}" == "200" ]] && pass "https /up -> 200" || fail "https /up -> ${code} (expected 200)"

code="$(http_code "http://${LB_HOST}/")"
[[ "${code}" == "301" || "${code}" == "302" ]] && pass "http -> ${code} redirect" || fail "http / -> ${code} (expected redirect to https)"

port_open "${LB_HOST}" 49984 && pass "49984 (IoT) reachable" || fail "49984 (IoT) unreachable on the LB, sensors cannot report"

code="$(http_code -H 'Cookie: PHPSESSID=exposure-check' -F probe=1 "https://${LB_HOST}/")"
[[ "${code}" == "403" ]] && pass "multipart + PHPSESSID blocked (403)" || fail "multipart + PHPSESSID -> ${code} (expected 403, PHP2Shell mitigation missing)"

for path in /.env /.git/HEAD /pdf/tmp/probe; do
  code="$(http_code "https://${LB_HOST}${path}")"
  [[ "${code}" == "403" || "${code}" == "404" ]] && pass "${path} -> ${code}" || fail "${path} -> ${code} (expected 403/404)"
done

for host in ${APP_HOSTS}; do
  echo "== App server ${host}"

  if ! getent hosts "${host}" >/dev/null 2>&1 && ! host "${host}" >/dev/null 2>&1; then
    fail "${host} does not resolve"
    continue
  fi

  for port in ${APP_CLOSED_PORTS}; do
    port_open "${host}" "${port}" && fail "${host}:${port} is reachable from the internet" || pass "${host}:${port} closed"
  done

  # Even with 443 filtered, prove the app does not answer a forged PROXY header.
  code="$(curl -sk -o /dev/null -m 8 -w '%{http_code}' --haproxy-protocol \
    --resolve "${LB_HOST}:443:$(getent hosts "${host}" | awk '{print $1; exit}')" "https://${LB_HOST}/up" || true)"
  [[ "${code}" == "000" ]] && pass "${host} direct https (PROXY header) refused" || fail "${host} direct https answered ${code}"
done

echo
if [[ "${failures}" -gt 0 ]]; then
  echo "${failures} check(s) failed: compare the OVH security groups with rules.tf."
  exit 1
fi
echo "All checks passed."
