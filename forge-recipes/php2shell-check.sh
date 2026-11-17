#!/usr/bin/env bash
#
# Forge recipe - run as root on any Forge server. READ ONLY (except `apt-get update`).
#
# CVE-2026-109618 / CVE-2026-109619 ("PHP2Shell") status for every installed PHP branch:
# running FPM version, fixed version available in apt, and the interim mitigations.
# Fixed releases (php.net, 2026-10-21): 8.5.12, 8.4.27, 8.3.36, 8.2.35. 8.1 and older: no fix.
#

set -uo pipefail

declare -A FIXED=([8.5]=8.5.12 [8.4]=8.4.27 [8.3]=8.3.36 [8.2]=8.2.35)

ver_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]; }
ini() { "$1" -i 2>/dev/null | awk -F' => ' -v k="$2" '$1 == k {print $2; exit}'; }

echo "== $(hostname) - $(date -Is)"
apt-get update -qq >/dev/null 2>&1 || echo "WARN: apt-get update failed, candidates may be stale"

worst=0
for dir in /etc/php/*/; do
  v="$(basename "$dir")"
  fpm="php-fpm${v}"
  command -v "$fpm" >/dev/null || continue

  running="$($fpm -v 2>/dev/null | head -1 | awk '{print $2}')"
  state="$(systemctl is-active "php${v}-fpm" 2>/dev/null)"
  candidate_full="$(apt-cache policy "php${v}-fpm" 2>/dev/null | awk '/Candidate:/ {print $2}')"
  installed_full="$(dpkg-query -W -f='${Version}' "php${v}-fpm" 2>/dev/null)"
  candidate="$(echo "$candidate_full" | cut -d- -f1 | sed 's/^[0-9]*://')"
  fixed="${FIXED[$v]:-none}"
  # Ubuntu/Debian packages backport fixes without bumping the upstream version: trust the changelog.
  distro_pkg=0
  [[ -n "$installed_full" && "$installed_full" != *sury* ]] && distro_pkg=1

  if [[ $distro_pkg -eq 1 ]]; then
    if zgrep -qE 'CVE-2026-10961[89]' "/usr/share/doc/php${v}-fpm/changelog.Debian.gz" 2>/dev/null \
       || zgrep -qE 'CVE-2026-10961[89]' "/usr/share/doc/php${v}-common/changelog.Debian.gz" 2>/dev/null; then
      verdict="PATCHED (distribution backport ${installed_full})"
    elif [[ "$candidate_full" != "$installed_full" ]] && apt-get changelog "php${v}-fpm" 2>/dev/null | grep -qE 'CVE-2026-10961[89]'; then
      verdict="PATCH AVAILABLE (distribution ${candidate_full}): run the upgrade"
      worst=2
    else
      verdict="WAITING for the distribution backport (installed ${installed_full})"
      [[ $worst -lt 1 ]] && worst=1
    fi
  elif [[ "$fixed" == none ]]; then
    verdict="NO UPSTREAM FIX for ${v}: upgrade the branch"
    worst=2
  elif ver_ge "$running" "$fixed"; then
    verdict="PATCHED"
  elif [[ -n "$candidate" ]] && ver_ge "$candidate" "$fixed"; then
    verdict="PATCH AVAILABLE (${candidate}): run the upgrade"
    worst=2
  else
    verdict="WAITING for ${fixed} in apt (candidate ${candidate:-none})"
    [[ $worst -lt 1 ]] && worst=1
  fi

  upload_progress="$(ini "$fpm" session.upload_progress.enabled)"
  post_max="$(ini "$fpm" post_max_size)"
  upload_max="$(ini "$fpm" upload_max_filesize)"
  memory="$(ini "$fpm" memory_limit)"

  echo "-- PHP ${v} (fpm ${state})"
  echo "   running ${running} | fixed ${fixed} | apt candidate ${candidate:-none}"
  echo "   => ${verdict}"
  if [[ "$upload_progress" == "Off" ]]; then
    echo "   mitigation session.upload_progress.enabled: Off (ok)"
  else
    echo "   mitigation session.upload_progress.enabled: ${upload_progress:-?} (SET IT TO 0 until patched)"
    [[ "$verdict" == PATCHED ]] || worst=2
  fi
  echo "   post_max_size ${post_max} | upload_max_filesize ${upload_max} | memory_limit ${memory}"
done

echo "-- nginx"
if [[ -f /etc/nginx/conf.d/php2shell.conf ]]; then
  echo "   multipart + PHPSESSID block: present"
else
  echo "   multipart + PHPSESSID block: absent"
fi
if [[ -f /etc/nginx/conf.d/potti-protection.conf ]]; then
  echo "   reputation blocklist / rate limits: present ($(grep -c . /etc/nginx/potti/blocklist.conf 2>/dev/null || echo 0) networks)"
else
  echo "   reputation blocklist / rate limits: absent"
fi

echo "-- PHP CLI workers still running an old binary (restart Horizon / queues after upgrading)"
stale=0
for pid in $(pgrep -f 'php[0-9.]* .*artisan' 2>/dev/null); do
  if grep -q '(deleted)' "/proc/${pid}/maps" 2>/dev/null; then
    echo "   pid ${pid}: $(tr '\0' ' ' < "/proc/${pid}/cmdline" | cut -c1-120)"
    stale=$((stale + 1))
  fi
done
[[ $stale -eq 0 ]] && echo "   none"

case $worst in
  0) echo "== RESULT: OK" ;;
  1) echo "== RESULT: mitigated, waiting for the patch in apt" ;;
  *) echo "== RESULT: ACTION REQUIRED" ;;
esac
exit 0
