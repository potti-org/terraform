#!/usr/bin/env bash
#
# Laravel Forge recipe - run as root on ANY Forge server (Potti app servers behind the
# OVH load balancer, or directly exposed servers such as regaler).
#
# Installs, for every Forge site on the server:
#   - a reputation blocklist (Spamhaus DROP, FireHOL level1, IPsum level 3, Tor exits): blocked IPs get 444
#   - per-IP rate limits: pages 10 r/s (burst 200), static-looking URLs 50 r/s (burst 1000),
#     auth POSTs 10/min (burst 10) -> 429
#   - PHP2Shell indicator: oversized / malformed PHPSESSID cookie -> 400 (safe for any PHP app)
#   - a daily cron refreshing the lists (/usr/local/sbin/potti-blocklist-update)
#
# Client IP: rules use $remote_addr AFTER each site's realip setup. Behind the Potti LB the
# site already sets `real_ip_header proxy_protocol`; on direct servers $remote_addr is the
# client. Cloudflare edge ranges are exempted from rate limits (they aggregate many users)
# until the site trusts CF-Connecting-IP.
#
# Safe to run several times. Rate limits start in DRY RUN (logged in each site's error log as
# "limiting requests, dry run"); set RATE_LIMIT_ENFORCE=1 and rerun once the logs look clean.
#
set -euo pipefail

RATE_LIMIT_ENFORCE="${RATE_LIMIT_ENFORCE:-0}"

ETC=/etc/nginx/potti
UPDATER=/usr/local/sbin/potti-blocklist-update
HTTP_CONF=/etc/nginx/conf.d/potti-protection.conf
SITE_SNIPPET_NAME=potti-protection.conf
BACKUP="/root/nginx-protection-backup-$(date +%Y%m%d-%H%M%S)"

[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required." >&2; exit 1; }

mkdir -p "$ETC" "$BACKUP"
cp -a /etc/nginx/conf.d "$BACKUP/" 2>/dev/null || true
[[ -f "$ETC/allow-extra.conf" ]] || cat > "$ETC/allow-extra.conf" <<'EOF'
# One IP or CIDR per line: never blocklisted, never rate limited (office, monitoring, partners).
EOF

# ---------------------------------------------------------------- updater
cat > "$UPDATER" <<'PY'
#!/usr/bin/env python3
"""Refresh /etc/nginx/potti/{blocklist,allow,ratelimit-exempt}.conf, then reload nginx.

Keeps the previous lists when a feed fails or the result looks wrong.
"""
import ipaddress, json, os, re, shutil, subprocess, sys, tempfile, urllib.request

ETC = "/etc/nginx/potti"
FEEDS = {
    "spamhaus_drop_v4": "https://www.spamhaus.org/drop/drop_v4.json",
    "spamhaus_drop_v6": "https://www.spamhaus.org/drop/drop_v6.json",
    "firehol_level1": "https://iplists.firehol.org/files/firehol_level1.netset",
    "ipsum_level3": "https://raw.githubusercontent.com/stamparm/ipsum/master/levels/3.txt",
    "tor_exits": "https://check.torproject.org/torbulkexitlist",
}
# Partners that must never be blocklisted or rate limited. Official machine-readable lists are
# fetched daily; the last good copy of each is cached so a provider outage never drops it.
ALLOW_FEEDS = {
    "cloudflare_v4": "https://www.cloudflare.com/ips-v4",
    "cloudflare_v6": "https://www.cloudflare.com/ips-v6",
    "forge": "https://forge.laravel.com/ips-v4.txt",
    "ohdear": "https://ohdear.app/used-ips.json",
    "stripe_webhooks": "https://stripe.com/files/ips/ips_webhooks.txt",
    "svix_webhooks": "https://docs.svix.com/webhook-ips.json",       # Resend, Recall.ai
    "openai_connectors": "https://openai.com/chatgpt-connectors.json",  # ChatGPT MCP clients
    "openai_actions": "https://openai.com/chatgpt-actions.json",
    "googlebot": "https://developers.google.com/static/search/apis/ipranges/googlebot.json",
    "google_services": "https://www.gstatic.com/ipranges/goog.json",  # Gmail Pub/Sub push
    "bingbot": "https://www.bing.com/toolbox/bingbot.json",
}
STATIC_ALLOW = {
    "forge_fallback": ["159.203.150.232", "45.55.124.124", "159.203.150.216", "165.227.248.218", "142.93.78.212"],
    "anthropic_outbound": ["160.79.104.0/21"],              # Claude MCP connectors (platform.claude.com/docs/en/api/ip-addresses)
    "brevo_webhooks": ["1.179.112.0/20", "172.246.240.0/20"],  # help.brevo.com/hc/en-us/articles/15127404548498
    "bridge_webhooks": ["63.32.31.5", "52.215.247.62", "34.249.92.209"],  # third-party list, harmless to allow
}
# Wanted crawlers that IPsum flags (SemrushBot, AS209366).
CRAWLERS = ["85.208.96.0/22", "185.191.171.0/24"]
# Never block or rate limit internal traffic (OVH vRack LB, localhost, Docker, Tailscale).
INTERNAL = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "127.0.0.0/8", "::1/128", "fc00::/7"]
MIN_BLOCKLIST = 5000


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "potti-blocklist-update/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8", "replace")


def parse(text):
    nets = []
    for line in text.splitlines():
        line = line.split("#")[0].split(";")[0].strip()
        if not line:
            continue
        if line.startswith("{"):
            try:
                line = str(json.loads(line).get("cidr", ""))
            except ValueError:
                continue
            if not line:
                continue
        token = line.split()[0]
        try:
            nets.append(ipaddress.ip_network(token, strict=False))
        except ValueError:
            continue
    return nets


IP_TOKEN = re.compile(r"[0-9A-Fa-f:.]*[.:][0-9A-Fa-f:.]*(?:/[0-9]{1,3})?")


def extract(text):
    """Every IPv4/IPv6 address or CIDR in a text or JSON body (provider formats all differ)."""
    nets = []
    for token in IP_TOKEN.findall(text):
        try:
            nets.append(ipaddress.ip_network(token.strip(".:"), strict=False))
        except ValueError:
            continue
    return nets


def public(net):
    if net.is_private or net.is_reserved or net.is_multicast or net.is_loopback \
            or net.is_link_local or net.is_unspecified:
        return False
    return not any(net.overlaps(ipaddress.ip_network(i)) for i in INTERNAL
                   if ipaddress.ip_network(i).version == net.version)


def collapse(nets):
    v4 = ipaddress.collapse_addresses(n for n in nets if n.version == 4)
    v6 = ipaddress.collapse_addresses(n for n in nets if n.version == 6)
    return list(v4) + list(v6)


def write(path, lines):
    fd, tmp = tempfile.mkstemp(dir=ETC)
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.chmod(tmp, 0o644)
    return tmp


def main():
    blocked, failures = [], []
    for name, url in FEEDS.items():
        try:
            nets = parse(fetch(url))
            print(f"{name}: {len(nets)} entries")
            blocked += nets
        except Exception as exc:  # keep going, other feeds still help
            failures.append(name)
            print(f"{name}: FAILED ({exc})", file=sys.stderr)

    allow = [ipaddress.ip_network(i) for i in INTERNAL + CRAWLERS]
    for name, nets in STATIC_ALLOW.items():
        allow += [ipaddress.ip_network(n) for n in nets]
    extra_path = os.path.join(ETC, "allow-extra.conf")
    if os.path.exists(extra_path):
        allow += parse(open(extra_path).read())
    cache_dir = os.path.join(ETC, "allow-cache")
    os.makedirs(cache_dir, exist_ok=True)
    for name, url in ALLOW_FEEDS.items():
        cache = os.path.join(cache_dir, name + ".txt")
        try:
            nets = extract(fetch(url))
            if not nets:
                raise ValueError("no address found")
            with open(cache, "w") as f:
                f.write("\n".join(str(n) for n in nets) + "\n")
            print(f"allow {name}: {len(nets)}")
        except Exception as exc:
            nets = parse(open(cache).read()) if os.path.exists(cache) else []
            print(f"allow {name}: FAILED ({exc}), using cached copy ({len(nets)})", file=sys.stderr)
        allow += nets

    # A parsing mistake must never allow half the internet: drop anything wider than /8 (v4) or /16 (v6).
    keep = [n for n in allow if n.prefixlen >= (8 if n.version == 4 else 16) and not n.is_unspecified]
    blocked = [n for n in collapse([n for n in blocked if public(n)])
               if not any(n.overlaps(k) for k in keep if k.version == n.version)]

    if len(blocked) < MIN_BLOCKLIST:
        print(f"only {len(blocked)} networks (failed feeds: {failures}), keeping previous lists", file=sys.stderr)
        return 1

    files = {
        "blocklist.conf": [f"{n} 1;" for n in blocked],
        "allow.conf": [f"{n} 0;" for n in collapse(keep)],
        "ratelimit-exempt.conf": [f"{n} 1;" for n in collapse(keep)],
    }
    staged = {name: write(os.path.join(ETC, name), lines) for name, lines in files.items()}
    backups = {}
    for name, tmp in staged.items():
        dest = os.path.join(ETC, name)
        if os.path.exists(dest):
            backups[name] = dest + ".prev"
            shutil.copy2(dest, backups[name])
        os.replace(tmp, dest)

    test = subprocess.run(["nginx", "-t"], capture_output=True, text=True)
    if test.returncode != 0:
        print("nginx -t failed, restoring previous lists:\n" + test.stderr, file=sys.stderr)
        for name, prev in backups.items():
            os.replace(prev, os.path.join(ETC, name))
        return 1
    subprocess.run(["systemctl", "reload", "nginx"], check=True)
    print(f"blocklist: {len(blocked)} networks, allowlist: {len(files['allow.conf'])}, failed feeds: {failures or 'none'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod 755 "$UPDATER"

# ---------------------------------------------------------------- http level
[[ -f "$ETC/blocklist.conf" ]] || echo "# filled by $UPDATER" > "$ETC/blocklist.conf"
[[ -f "$ETC/allow.conf" ]] || printf '10.0.0.0/8 0;\n127.0.0.0/8 0;\n' > "$ETC/allow.conf"
[[ -f "$ETC/ratelimit-exempt.conf" ]] || printf '10.0.0.0/8 1;\n127.0.0.0/8 1;\n' > "$ETC/ratelimit-exempt.conf"

cat > "$HTTP_CONF" <<'EOF'
# Managed by Forge recipe "nginx-protection" - do not edit by hand.
# Evaluated lazily, i.e. after each site's realip (PROXY protocol behind the LB).

# Reputation blocklist, refreshed daily. allow.conf comes last so it always wins.
geo $potti_blocked {
    default 0;
    include /etc/nginx/potti/blocklist.conf;
    include /etc/nginx/potti/allow.conf;
}

# No rate limit for internal traffic, Cloudflare edges, Stripe webhooks and allow-extra.
geo $potti_rl_exempt_ip {
    default 0;
    include /etc/nginx/potti/ratelimit-exempt.conf;
}
map $uri $potti_rl_exempt_path {
    default 0;
    ~^/(webhooks|stripe)/ 1;
}
# Static-looking URLs get their own, much looser limit: a page with many images or a fresh
# asset bundle never hits it, yet flooding PHP through missing /anything.png is still capped.
map $uri $potti_is_static {
    default 0;
    "~*\.(css|js|mjs|map|png|jpe?g|gif|svg|webp|avif|ico|bmp|woff2?|ttf|otf|eot|mp4|webm|mp3|pdf)$" 1;
}
map "$potti_rl_exempt_ip$potti_rl_exempt_path" $potti_rl_key {
    default $binary_remote_addr;
    "~1" "";
}
map "$potti_is_static" $potti_dynamic_key {
    default $potti_rl_key;
    1 "";
}
map "$potti_is_static" $potti_static_key {
    default "";
    1 $potti_rl_key;
}
map "$request_method:$uri" $potti_auth_key {
    default "";
    "~^POST:/(auth/)?(login|register|forgot-password|reset-password|two-factor-challenge)$" $potti_rl_key;
}

limit_req_zone $potti_dynamic_key zone=potti_global:20m rate=10r/s;
limit_req_zone $potti_static_key zone=potti_static:20m rate=50r/s;
limit_req_zone $potti_auth_key zone=potti_auth:10m rate=10r/m;

# PHP2Shell indicator (CVE-2026-109619): oversized or malformed PHPSESSID cookie. Real PHP
# session ids are at most 256 chars of [A-Za-z0-9,-], so this never hits a legitimate session,
# whatever the application (Laravel, WordPress...).
map $cookie_PHPSESSID $potti_bad_sessid {
    default 0;
    "~[^A-Za-z0-9,-]" 1;
    "~^.{257,}" 1;
}
EOF

# ---------------------------------------------------------------- every Forge site
if [[ "$RATE_LIMIT_ENFORCE" == "1" ]]; then DRY=off; else DRY=on; fi
SITES=0
for dir in /etc/nginx/forge-conf/*/server; do
  [[ -d "$dir" ]] || continue
  cat > "$dir/$SITE_SNIPPET_NAME" <<EOF
# Managed by Forge recipe "nginx-protection" - do not edit by hand.
if (\$potti_blocked) {
    return 444;
}
if (\$potti_bad_sessid) {
    return 400;
}
limit_req zone=potti_global burst=200 nodelay;
limit_req zone=potti_static burst=1000 nodelay;
limit_req zone=potti_auth burst=10 nodelay;
limit_req_status 429;
limit_req_log_level warn;
limit_req_dry_run $DRY;
EOF
  SITES=$((SITES + 1))
  echo "site snippet: $dir/$SITE_SNIPPET_NAME"
done

cat > /etc/cron.d/potti-blocklist <<EOF
# Managed by Forge recipe "nginx-protection".
$((RANDOM % 60)) 4 * * * root $UPDATER >> /var/log/potti-blocklist.log 2>&1
EOF

# ---------------------------------------------------------------- LDP tracking (Potti servers only)
# Servers that ship the JSON access log to Graylog (conf.d/potti-logging.conf) get extra
# fields per request: rate limit outcome, blocklist hit, malformed PHPSESSID, PHP2Shell block.
# Other servers keep their logs local (light mode), nothing changes for them here.
LOGGING_CONF=/etc/nginx/conf.d/potti-logging.conf
if [[ -f "$LOGGING_CONF" ]] && ! grep -q '"bad_phpsessid"' "$LOGGING_CONF"; then
  cp -a "$LOGGING_CONF" "$BACKUP/"
  # Older runs added a subset of these fields: drop them before adding the full set.
  sed -i '/"rate_limit":/d; /"blocklisted":/d; /"bad_phpsessid":/d; /"php2shell_blocked":/d' "$LOGGING_CONF"
  FIELDS="$(mktemp)"
  {
    echo "    '\"rate_limit\":\"\$limit_req_status\",'"
    echo "    '\"blocklisted\":\"\$potti_blocked\",'"
    echo "    '\"bad_phpsessid\":\"\$potti_bad_sessid\",'"
    [[ -f /etc/nginx/conf.d/php2shell.conf ]] && echo "    '\"php2shell_blocked\":\"\$php2shell_block\",'"
  } > "$FIELDS"
  awk -v f="$FIELDS" '/"request_id":/ { while ((getline line < f) > 0) print line } { print }' "$LOGGING_CONF" > "$FIELDS.conf" \
    && cat "$FIELDS.conf" > "$LOGGING_CONF"
  rm -f "$FIELDS" "$FIELDS.conf"
  echo "LDP tracking fields added to $LOGGING_CONF"
fi

# ---------------------------------------------------------------- apply
if ! nginx -t; then
  echo "nginx -t failed, rolling back" >&2
  rm -f "$HTTP_CONF" /etc/nginx/forge-conf/*/server/"$SITE_SNIPPET_NAME"
  [[ -f "$BACKUP/potti-logging.conf" ]] && cp -a "$BACKUP/potti-logging.conf" "$LOGGING_CONF"
  nginx -t && systemctl reload nginx
  exit 1
fi
systemctl reload nginx

echo "--- first list download"
"$UPDATER" | tee -a /var/log/potti-blocklist.log || echo "updater failed, lists stay empty until next run" >&2

sleep 2
echo "--- summary"
echo "sites protected: $SITES, rate limits: $([[ $DRY == on ]] && echo 'DRY RUN (log only)' || echo ENFORCED)"
wc -l "$ETC"/blocklist.conf "$ETC"/allow.conf | head -2
nginx -T 2>/dev/null | grep -c "potti-protection.conf" | xargs echo "nginx files mentioning potti-protection:"
echo "backup of previous conf.d: $BACKUP"
