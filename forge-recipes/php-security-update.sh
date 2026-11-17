#!/usr/bin/env bash
#
# Laravel Forge recipe - run as root on ANY Forge server (Ubuntu 22.04 / 24.04 / 26.04).
#
# PHP security update for CVE-2026-109618 / CVE-2026-109619 (October 2026 release):
#   1. adds packages.sury.org (Ondřej Surý, same maintainer as the ondrej/php PPA Forge uses;
#      it already carries the fixed builds while the PPA mirror lags)
#   2. for every installed PHP branch: dry-runs the upgrade, refuses it if apt wants to remove
#      anything, then upgrades only the packages already installed for that branch
#   3. keeps session.upload_progress.enabled = Off, restarts queue workers / Horizon
#   4. reverts the temporary Potti mitigation (pm.max_requests = 1, 8M post) once 8.4 is patched
#
# Safe to run several times. Follows https://forge.laravel.com/docs/knowledge-base/php-security-release-october-2026
#
set -uo pipefail

REVERT_TEMP_MITIGATION="${REVERT_TEMP_MITIGATION:-1}"

declare -A FIXED=([8.5]=8.5.12 [8.4]=8.4.27 [8.3]=8.3.36 [8.2]=8.2.35)
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l

say() { printf '\n===== %s\n' "$1"; }
ver_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]; }

[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
CODENAME="$(lsb_release -cs 2>/dev/null)"
echo "$(hostname) - Ubuntu ${CODENAME} - $(date -Is)"

# ---------------------------------------------------------------- 1. package source
say "Package source"
case "$CODENAME" in
  jammy|noble|resolute)
    if [[ ! -f /etc/apt/sources.list.d/sury-php.list ]]; then
      curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
      dpkg -i /tmp/debsuryorg-archive-keyring.deb >/dev/null
      # Trust the key for this repository only, not for every apt source.
      rm -f /etc/apt/trusted.gpg.d/debsuryorg-archive.gpg
      echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ ${CODENAME} main" \
        > /etc/apt/sources.list.d/sury-php.list
      echo "added packages.sury.org for ${CODENAME}"
    else
      echo "packages.sury.org already configured"
    fi
    gpg --show-keys --with-fingerprint /usr/share/keyrings/debsuryorg-archive-keyring.gpg 2>/dev/null \
      | grep -q '1505 8500 A023 5D97 F5D1  0063 B188 E2B6 95BD 4743' \
      && echo "signing key fingerprint OK" \
      || { echo "UNEXPECTED signing key, aborting" >&2; rm -f /etc/apt/sources.list.d/sury-php.list; exit 1; }
    ;;
  *)
    echo "Ubuntu ${CODENAME}: packages.sury.org has no build for it, using the existing PHP source only"
    ;;
esac
apt-get update -qq || echo "WARN: apt-get update reported errors, continuing with cached lists"

# ---------------------------------------------------------------- 2. upgrade every branch
PATCHED_84=0
for dir in /etc/php/*/; do
  v="$(basename "$dir")"
  command -v "php-fpm${v}" >/dev/null || command -v "php${v}" >/dev/null || continue
  say "PHP ${v}"
  fixed="${FIXED[$v]:-}"
  before="$(php${v} -r 'echo PHP_VERSION;' 2>/dev/null)"
  echo "installed ${before:-?} | fixed ${fixed:-none (end of life: move sites to a supported version)}"

  # Interim mitigation stays on for good: Laravel never uses native PHP sessions.
  for sapi in fpm cli; do
    [[ -d "/etc/php/${v}/${sapi}/conf.d" ]] || continue
    ini="/etc/php/${v}/${sapi}/conf.d/99-potti-security.ini"
    grep -q '^session.upload_progress.enabled' "$ini" 2>/dev/null \
      || printf '; CVE-2026-109619: Laravel never uses native PHP sessions.\nsession.upload_progress.enabled = Off\n' >> "$ini"
  done

  if [[ -z "$fixed" ]]; then
    echo "SKIPPED: no upstream fix for PHP ${v}"
    continue
  fi
  if ver_ge "$before" "$fixed"; then
    echo "already patched"
    [[ "$v" == 8.4 ]] && PATCHED_84=1
    continue
  fi

  pkgs="$(dpkg -l "php${v}*" | awk '/^ii/ {print $2}' | tr '\n' ' ')"
  plan="$(apt-get -s install --only-upgrade -o Dpkg::Options::=--force-confold $pkgs 2>&1)"
  if grep -q '^Remv' <<<"$plan"; then
    echo "ABORTED for PHP ${v}: apt wants to remove packages:"; grep '^Remv' <<<"$plan"
    continue
  fi
  candidate="$(apt-cache policy "php${v}-common" | awk '/Candidate:/ {print $2}')"
  echo "candidate ${candidate}, $(grep -c '^Inst' <<<"$plan") package(s) to upgrade"
  if ! ver_ge "$(echo "$candidate" | cut -d- -f1 | sed 's/^[0-9]*://')" "$fixed"; then
    echo "WAITING: ${fixed} is not in apt yet, rerun later"
    continue
  fi

  apt-get install --only-upgrade -y -q -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef $pkgs \
    > "/var/log/php${v}-security-update.log" 2>&1 \
    || { echo "UPGRADE FAILED, see /var/log/php${v}-security-update.log"; tail -15 "/var/log/php${v}-security-update.log"; continue; }

  after="$(php${v} -r 'echo PHP_VERSION;')"
  if command -v "php-fpm${v}" >/dev/null; then
    "php-fpm${v}" -t >/dev/null 2>&1 && systemctl reload "php${v}-fpm" 2>/dev/null || systemctl restart "php${v}-fpm"
    echo "fpm $(php-fpm${v} -v | head -1 | awk '{print $2}') ($(systemctl is-active "php${v}-fpm"))"
  fi
  echo "cli ${after}"
  ver_ge "$after" "$fixed" && [[ "$v" == 8.4 ]] && PATCHED_84=1
done

# ---------------------------------------------------------------- 3. temporary Potti mitigation
if [[ "$REVERT_TEMP_MITIGATION" == "1" && "$PATCHED_84" == "1" ]]; then
  say "Revert temporary mitigation (PHP 8.4 patched)"
  POOL=/etc/php/8.4/fpm/pool.d/www.conf
  if grep -q '^pm.max_requests = 1$' "$POOL" 2>/dev/null; then
    cp -a "$POOL" "/root/www.conf.mitigation-$(date +%Y%m%d-%H%M%S)"
    sed -i '/^pm.max_requests = 1$/d' "$POOL"
    echo "pm.max_requests = 1 removed (spare servers kept at their current values)"
  fi
  INI=/etc/php/8.4/fpm/conf.d/99-potti-security.ini
  if grep -q 'CVE-2026-109618 mitigation' "$INI" 2>/dev/null; then
    sed -i '/CVE-2026-109618 mitigation/,/^upload_max_filesize/d' "$INI"
    echo "post_max_size / upload_max_filesize back to the php.ini values"
  fi
  php-fpm8.4 -t >/dev/null 2>&1 && systemctl reload php8.4-fpm
fi

# ---------------------------------------------------------------- 4. long-running PHP processes
say "Restart long-running PHP processes"
for base in /home/forge/*/; do
  app="${base%/}"; [[ -d "$app/current" ]] && app="$app/current"
  [[ -f "$app/artisan" ]] || continue
  if [[ -d "$app/vendor/laravel/horizon" ]]; then
    (cd "$app" && sudo -u forge php artisan horizon:terminate >/dev/null 2>&1) && echo "horizon:terminate $(basename "${base%/}")"
  fi
  (cd "$app" && sudo -u forge php artisan queue:restart >/dev/null 2>&1) && echo "queue:restart $(basename "${base%/}")"
done
command -v supervisorctl >/dev/null && supervisorctl restart all >/dev/null 2>&1 && sleep 5 \
  && supervisorctl status | awk '{print "  "$1, $2}'

# ---------------------------------------------------------------- 5. summary
say "Summary"
for dir in /etc/php/*/; do
  v="$(basename "$dir")"
  command -v "php-fpm${v}" >/dev/null || continue
  running="$(php-fpm${v} -v 2>/dev/null | head -1 | awk '{print $2}')"
  fixed="${FIXED[$v]:-}"
  up="$(php-fpm${v} -i 2>/dev/null | awk -F' => ' '$1=="session.upload_progress.enabled"{print $2; exit}')"
  if [[ -n "$fixed" ]] && ver_ge "$running" "$fixed"; then state=PATCHED; else state="NOT PATCHED"; fi
  echo "PHP ${v}: fpm ${running} -> ${state} | upload_progress ${up} | max_requests $(php-fpm${v} -tt 2>&1 | awk -F'= ' '/pm.max_requests/{print $2; exit}')"
done
ss -tln 2>/dev/null | grep -q ':20186 ' && curl -s -o /dev/null -w "Potti /up -> %{http_code}\n" http://127.0.0.1:20186/up
exit 0
