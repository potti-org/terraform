#!/usr/bin/env bash
#
# Laravel Forge recipe - run as root on every app server.
#
# Exposes Laravel's /up on a dedicated plain HTTP port so that:
#   - the OpenStack load balancer health monitor (monitor_port on pool members)
#   - Oh Dear (direct checks on app-<az>-<n>.potti.co)
# can check the application itself, not just that nginx accepts connections.
#
# Only /up is served on this port, everything else returns 404.
# Who can reach the port is enforced by OpenStack security groups (see rules.tf).
#
# Safe to run several times.
#

set -euo pipefail

SITE="potti.co"
PORT="20186"                                   # must match local.health_check_port in locals.tf
CONF_NAME="potti-health-check"
SITE_CONF="/etc/nginx/sites-available/${SITE}"
CONF="/etc/nginx/sites-available/${CONF_NAME}"
LINK="/etc/nginx/sites-enabled/${CONF_NAME}"

# Site root: zero-downtime deployments use current/, classic ones do not.
if [[ -d "/home/forge/${SITE}/current" ]]; then
  ROOT="/home/forge/${SITE}/current/public"
else
  ROOT="/home/forge/${SITE}/public"
fi

# Reuse the PHP-FPM socket of the real site, so /up goes through the same pool.
FASTCGI_PASS="$(grep -hoE 'fastcgi_pass[[:space:]]+[^;]+' "${SITE_CONF}" | head -n1 | awk '{print $2}' || true)"
if [[ -z "${FASTCGI_PASS}" ]]; then
  FASTCGI_PASS="unix:$(ls -1 /var/run/php/php*-fpm.sock | sort -V | tail -n1)"
fi

echo "Site root:    ${ROOT}"
echo "PHP-FPM:      ${FASTCGI_PASS}"
echo "Listen port:  ${PORT}"

cat > "${CONF}" <<NGINX
# Managed by Forge recipe "nginx-health-check" - do not edit by hand.
server {
    listen ${PORT};
    listen [::]:${PORT};
    server_name _;

    root ${ROOT};
    access_log off;

    location = /up {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$realpath_root/index.php;

        # Make Laravel see the request as a normal https://${SITE} request,
        # so host checks and forced-HTTPS middleware do not answer 400/301.
        fastcgi_param HTTP_HOST ${SITE};
        fastcgi_param SERVER_NAME ${SITE};
        fastcgi_param HTTPS on;

        fastcgi_pass ${FASTCGI_PASS};
        fastcgi_connect_timeout 2s;
        fastcgi_read_timeout 3s;
    }

    location / {
        return 404;
    }
}
NGINX

ln -sf "${CONF}" "${LINK}"

if ! nginx -t; then
  echo "nginx config test failed, removing ${CONF_NAME}" >&2
  rm -f "${LINK}" "${CONF}"
  exit 1
fi

systemctl reload nginx

# Forge enables ufw with only 22/80/443 open. Without this rule the LB would
# mark every member down. Source filtering is done by OpenStack security groups.
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow "${PORT}/tcp" comment "LB + Oh Dear health check"
fi

# Self-test
sleep 1
STATUS="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/up" || true)"
echo "GET http://127.0.0.1:${PORT}/up -> ${STATUS}"
if [[ "${STATUS}" != "200" ]]; then
  echo "Health check endpoint does not answer 200, DO NOT apply the Terraform monitor change yet." >&2
  exit 1
fi

OTHER="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/" || true)"
echo "GET http://127.0.0.1:${PORT}/ -> ${OTHER} (expected 404)"
