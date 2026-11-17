#!/usr/bin/env bash
#
# Interactive PHP security update (CVE-2026-109618 / CVE-2026-109619), to run BY HAND:
#   sudo bash php-security-update-interactive.sh
#
# Every step shows what it found and asks before changing anything. Answer "n" to skip a step.
# Works on any Forge server (Ubuntu 22.04 / 24.04 / 26.04).
#
set -uo pipefail

declare -A FIXED=([8.5]=8.5.12 [8.4]=8.4.27 [8.3]=8.3.36 [8.2]=8.2.35)
KEY_FPR='1505 8500 A023 5D97 F5D1  0063 B188 E2B6 95BD 4743'
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l

bold() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
ok() { printf '   \033[32mOK\033[0m %s\n' "$1"; }
warn() { printf '   \033[33m!!\033[0m %s\n' "$1"; }
ver_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]; }
confirm() {
  local answer
  read -r -p "   -> $1 [o/N] " answer </dev/tty
  [[ "$answer" =~ ^[oOyY]$ ]]
}

[[ $EUID -eq 0 ]] || { echo "Lance avec sudo." >&2; exit 1; }
CODENAME="$(lsb_release -cs 2>/dev/null)"
PHP_BRANCHES=()
for dir in /etc/php/*/; do
  v="$(basename "$dir")"
  command -v "php${v}" >/dev/null && PHP_BRANCHES+=("$v")
done

# ---------------------------------------------------------------- 0. state
bold "Serveur"
echo "   $(hostname) | $(lsb_release -ds 2>/dev/null) (${CODENAME}) | uptime: $(uptime -p)"
echo "   nginx: $(systemctl is-active nginx 2>/dev/null) (au démarrage: $(systemctl is-enabled nginx 2>/dev/null))"
for v in "${PHP_BRANCHES[@]}"; do
  cli="$(php${v} -r 'echo PHP_VERSION;' 2>/dev/null)"
  fpm="$(php-fpm${v} -v 2>/dev/null | head -1 | awk '{print $2}')"
  echo "   PHP ${v}: cli ${cli:-absent} | fpm ${fpm:-absent} ($(systemctl is-active "php${v}-fpm" 2>/dev/null)) | corrigé en ${FIXED[$v]:-AUCUN CORRECTIF}"
done
echo "   sources PHP: $(grep -rlE 'sury|ondrej|setup-php' /etc/apt/sources.list.d/ 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
confirm "Continuer ?" || exit 0

# ---------------------------------------------------------------- 1. package source
bold "1. Dépôt packages.sury.org (Ondřej Surý, mainteneur du PPA ondrej/php utilisé par Forge)"
if [[ -f /etc/apt/sources.list.d/sury-php.list ]]; then
  ok "déjà configuré: $(cat /etc/apt/sources.list.d/sury-php.list)"
elif [[ ! "$CODENAME" =~ ^(jammy|noble|resolute)$ ]]; then
  warn "pas de build packages.sury.org pour ${CODENAME}: on garde la source actuelle"
elif confirm "Ajouter packages.sury.org pour ${CODENAME} ?"; then
  curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb || { warn "téléchargement de la clé impossible"; exit 1; }
  dpkg -i /tmp/debsuryorg-archive-keyring.deb >/dev/null
  rm -f /etc/apt/trusted.gpg.d/debsuryorg-archive.gpg
  fpr="$(gpg --show-keys --with-fingerprint /usr/share/keyrings/debsuryorg-archive-keyring.gpg 2>/dev/null | sed -n '2p' | sed 's/^ *//')"
  echo "   empreinte reçue  : ${fpr}"
  echo "   empreinte attendue: ${KEY_FPR}"
  if [[ "$fpr" != "$KEY_FPR" ]]; then
    warn "EMPREINTE DIFFÉRENTE, arrêt."; exit 1
  fi
  ok "empreinte conforme"
  echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ ${CODENAME} main" \
    > /etc/apt/sources.list.d/sury-php.list
  ok "dépôt ajouté"
fi

bold "2. Mise à jour de la liste des paquets"
if confirm "Lancer apt-get update ?"; then
  apt-get update -q 2>&1 | grep -E '^(Err|W:|E:)' | grep -v 'legacy trusted.gpg' || true
  ok "listes à jour"
fi

# ---------------------------------------------------------------- 3. upgrade each branch
declare -A PATCHED=()
for v in "${PHP_BRANCHES[@]}"; do
  fixed="${FIXED[$v]:-}"
  current="$(php${v} -r 'echo PHP_VERSION;' 2>/dev/null)"
  bold "3. PHP ${v} (installé ${current}, corrigé en ${fixed:-aucun})"
  if [[ -z "$fixed" ]]; then
    warn "PHP ${v} n'a pas de correctif: les sites doivent passer sur 8.2 ou plus récent"; continue
  fi
  if ver_ge "$current" "$fixed"; then
    ok "déjà corrigé"; PATCHED[$v]=1; continue
  fi

  apt-cache policy "php${v}-fpm" 2>/dev/null | sed -n '1,8p' | sed 's/^/   /'
  candidate="$(apt-cache policy "php${v}-common" | awk '/Candidate:/ {print $2}')"
  if ! ver_ge "$(echo "$candidate" | cut -d- -f1 | sed 's/^[0-9]*://')" "$fixed"; then
    warn "le candidat ${candidate} n'est pas encore ${fixed}: relance plus tard"; continue
  fi

  pkgs="$(dpkg -l "php${v}*" | awk '/^ii/ {print $2}' | tr '\n' ' ')"
  plan="$(apt-get -s install --only-upgrade -o Dpkg::Options::=--force-confold $pkgs 2>&1)"
  echo "   simulation:"
  grep -E '^(Inst|Remv)' <<<"$plan" | awk '{print "     " $1, $2, $3, $4}'
  if grep -q '^Remv' <<<"$plan"; then
    warn "apt veut SUPPRIMER des paquets: mise à jour de PHP ${v} annulée"; continue
  fi
  confirm "Mettre à jour ces $(grep -c '^Inst' <<<"$plan") paquets PHP ${v} vers ${candidate} ?" || continue

  apt-get install --only-upgrade -y -q -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef $pkgs \
    > "/var/log/php${v}-security-update.log" 2>&1 \
    || { warn "ÉCHEC, voir /var/log/php${v}-security-update.log"; tail -15 "/var/log/php${v}-security-update.log"; continue; }
  after_cli="$(php${v} -r 'echo PHP_VERSION;')"
  after_fpm="$(php-fpm${v} -v 2>/dev/null | head -1 | awk '{print $2}')"
  php-fpm${v} -t >/dev/null 2>&1 && ok "config FPM valide" || warn "php-fpm${v} -t en erreur"
  echo "   cli ${after_cli} | fpm ${after_fpm:-absent} ($(systemctl is-active "php${v}-fpm" 2>/dev/null))"
  if ver_ge "$after_cli" "$fixed"; then ok "PHP ${v} corrigé"; PATCHED[$v]=1; else warn "PHP ${v} pas à la bonne version"; fi
done

# ---------------------------------------------------------------- 4. upload_progress
bold "4. session.upload_progress.enabled (doit rester Off)"
for v in "${PHP_BRANCHES[@]}"; do
  command -v "php-fpm${v}" >/dev/null || continue
  state="$(php-fpm${v} -i 2>/dev/null | awk -F' => ' '$1=="session.upload_progress.enabled"{print $2; exit}')"
  if [[ "$state" == "Off" ]]; then
    ok "PHP ${v}: Off"
  elif confirm "PHP ${v}: ${state}. Le passer à Off (fichier conf.d/99-potti-security.ini) ?"; then
    printf '; CVE-2026-109619 mitigation: disables only the upload progress tracking, sessions keep working.\nsession.upload_progress.enabled = Off\n' >> "/etc/php/${v}/fpm/conf.d/99-potti-security.ini"
    php-fpm${v} -t >/dev/null 2>&1 && systemctl reload "php${v}-fpm" && ok "PHP ${v}: Off"
  fi
done

# ---------------------------------------------------------------- 5. temporary mitigation
for v in "${PHP_BRANCHES[@]}"; do
  POOLS=(/etc/php/${v}/fpm/pool.d/*.conf)
  INI="/etc/php/${v}/fpm/conf.d/99-potti-security.ini"
  has_pool="$(grep -l '^pm.max_requests = 1$' "${POOLS[@]}" 2>/dev/null)"
  has_ini="$(grep -l 'CVE-2026-109618 mitigation' "$INI" 2>/dev/null)"
  [[ -n "$has_pool$has_ini" ]] || continue
  bold "5. PHP ${v} : mitigation temporaire (pm.max_requests = 1, post_max_size 8M)"
  [[ -n "$has_pool" ]] && echo "   pools: $(echo "$has_pool" | xargs -n1 basename | tr '\n' ' ')"
  if [[ "${PATCHED[$v]:-0}" != 1 ]]; then
    warn "PHP ${v} n'est pas corrigé: on GARDE la mitigation"; continue
  fi
  confirm "PHP ${v} corrigé: retirer la mitigation temporaire ?" || continue
  for pool in $has_pool; do
    cp -a "$pool" "/root/$(basename "$pool").${v}.mitigation-$(date +%Y%m%d-%H%M%S)"
    sed -i '/^pm.max_requests = 1$/d' "$pool"
  done
  [[ -n "$has_ini" ]] && sed -i '/CVE-2026-109618 mitigation/,/^upload_max_filesize/d' "$INI"
  php-fpm${v} -t >/dev/null 2>&1 && systemctl reload "php${v}-fpm"
  echo "   post_max_size: $(php-fpm${v} -i 2>/dev/null | awk -F' => ' '$1=="post_max_size"{print $2; exit}')"
  ok "mitigation retirée pour PHP ${v} (upload_progress reste Off)"
done

# ---------------------------------------------------------------- 6. long-running processes
bold "6. Processus PHP longs (Horizon, queues, daemons)"
supervisorctl status 2>/dev/null | awk '{print "   " $1, $2, $3, $4}'
if confirm "Redémarrer Horizon / les queues / supervisor (inutile si tu rebootes juste après) ?"; then
  for base in /home/forge/*/; do
    app="${base%/}"; [[ -d "$app/current" ]] && app="$app/current"
    [[ -f "$app/artisan" ]] || continue
    [[ -d "$app/vendor/laravel/horizon" ]] && (cd "$app" && sudo -u forge php artisan horizon:terminate >/dev/null 2>&1)
    (cd "$app" && sudo -u forge php artisan queue:restart >/dev/null 2>&1)
    echo "   $(basename "${base%/}"): workers relancés"
  done
  supervisorctl restart all >/dev/null 2>&1; sleep 5
  supervisorctl status 2>/dev/null | awk '{print "   " $1, $2}'
fi

# ---------------------------------------------------------------- 7. summary + reboot
bold "7. Bilan"
for v in "${PHP_BRANCHES[@]}"; do
  fpm="$(php-fpm${v} -v 2>/dev/null | head -1 | awk '{print $2}')"
  fixed="${FIXED[$v]:-}"
  if [[ -n "$fixed" && -n "$fpm" ]] && ver_ge "$fpm" "$fixed"; then ok "PHP ${v}: fpm ${fpm} CORRIGÉ"; else warn "PHP ${v}: fpm ${fpm:-absent} NON CORRIGÉ"; fi
done
echo "   au démarrage: nginx $(systemctl is-enabled nginx 2>/dev/null) | supervisor $(systemctl is-enabled supervisor 2>/dev/null) | filebeat $(systemctl is-enabled filebeat 2>/dev/null)"
for v in "${PHP_BRANCHES[@]}"; do echo "                 php${v}-fpm $(systemctl is-enabled "php${v}-fpm" 2>/dev/null)"; done
systemctl is-enabled nginx >/dev/null 2>&1 || warn "nginx NE redémarrera PAS au boot (systemctl enable nginx si tu veux qu'il revienne)"

if confirm "Redémarrer le serveur maintenant ?"; then
  echo "   reboot dans 5 s (Ctrl+C pour annuler)"; sleep 5; systemctl reboot
fi
