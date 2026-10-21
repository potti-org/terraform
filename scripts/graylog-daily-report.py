#!/usr/bin/env python3
"""Daily Potti log digest from Graylog (OVH Logs Data Platform).

Read-only. Prints one JSON document on stdout comparing the last 24h with the
previous 24h, for security (blocklist, rate limit, PHP2Shell IOCs, SSH) and
health (5xx, latency, PHP-FPM, Laravel errors, PostgreSQL).

Credentials come from GRAYLOG_CLIENT_ID / GRAYLOG_CLIENT_SECRET (OVH IAM service
account, OAuth2 client_credentials). They are never printed.

Usage: GRAYLOG_CLIENT_ID=... GRAYLOG_CLIENT_SECRET=... ./graylog-daily-report.py [--hours 24]
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import os
import re
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

API = "https://gra2.logs.ovh.com/api"
TOKEN_URL = "https://www.ovh.com/auth/oauth2/token"

STREAMS = {
    "app": "695f9c1f6985e9c96272325b",
    "laravel": "695b7f556985e9c9626b8a3b",
    "lb": "695f96fd2cba1c0a989d5f1d",
    "postgres": "695f96d42cba1c0a989d5ee9",
    "bastion": "695f9b236985e9c962723144",
    "valkey": "695f96e22cba1c0a989d5efb",
}

ACCESS = "fields_log_type:nginx_access"
FPM_LOG = 'log_file_path:"/var/log/php8.4-fpm.log"'
SLOW_LOG = 'log_file_path:"/var/log/php8.4-fpm-slow.log"'
NGINX_ERR = 'log_file_path:"/var/log/nginx/potti.co-error.log"'
AUTH_LOG = 'log_file_path:"/var/log/auth.log"'
BLOCKLIST_LOG = 'log_file_path:"/var/log/potti-blocklist.log"'
PHP2SHELL_LOG = 'log_file_path:"/var/log/nginx/php2shell-blocked.log"'

_token: str | None = None


def token() -> str:
    global _token
    if _token:
        return _token
    cid = os.environ.get("GRAYLOG_CLIENT_ID")
    secret = os.environ.get("GRAYLOG_CLIENT_SECRET")
    if not cid or not secret:
        sys.exit("GRAYLOG_CLIENT_ID / GRAYLOG_CLIENT_SECRET are not set")
    body = urllib.parse.urlencode({
        "grant_type": "client_credentials", "client_id": cid,
        "client_secret": secret, "scope": "all",
    }).encode()
    with urllib.request.urlopen(urllib.request.Request(TOKEN_URL, data=body), timeout=30) as r:
        _token = json.load(r)["access_token"]
    return _token


def call(method: str, path: str, payload: dict | None = None) -> dict:
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(API + path, data=data, method=method, headers={
        "Authorization": f"Bearer {token()}", "Accept": "application/json",
        "Content-Type": "application/json", "X-Requested-By": "potti-daily-report",
    })
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Graylog {method} {path.split('?')[0]} -> HTTP {e.code}") from None


class Window:
    def __init__(self, start: dt.datetime, end: dt.datetime):
        self.start, self.end = start, end

    def timerange(self) -> dict:
        return {"type": "absolute", "from": iso(self.start), "to": iso(self.end)}


def iso(t: dt.datetime) -> str:
    return t.strftime("%Y-%m-%dT%H:%M:%S.000Z")


def count(stream: str, query: str, w: Window) -> int:
    qs = urllib.parse.urlencode({
        "query": query or "*", "from": iso(w.start), "to": iso(w.end),
        "limit": 0, "filter": f"streams:{STREAMS[stream]}",
    })
    return int(call("GET", f"/search/universal/absolute?{qs}").get("total_results", 0))


def messages(stream: str, query: str, w: Window, fields: str, limit: int) -> list[dict]:
    qs = urllib.parse.urlencode({
        "query": query or "*", "from": iso(w.start), "to": iso(w.end), "limit": limit,
        "fields": fields, "filter": f"streams:{STREAMS[stream]}", "sort": "timestamp:desc",
    })
    return [m["message"] for m in call("GET", f"/search/universal/absolute?{qs}").get("messages", [])]


def pivot(stream: str, query: str, w: Window, group_by: list[str] | None = None, limit: int = 10,
          percentiles: tuple[float, ...] = (), latency_field: str | None = None) -> list[dict]:
    """Aggregation through the views API (LDP has no legacy terms/stats endpoints)."""
    series = [{"type": "count", "id": "count"}]
    for p in percentiles:
        series.append({"type": "percentile", "id": f"p{int(p)}", "field": latency_field, "percentile": float(p)})
    if latency_field:
        series.append({"type": "avg", "id": "avg", "field": latency_field})
    st = {
        "id": "st", "type": "pivot", "name": "st", "timerange": w.timerange(),
        "query": {"type": "elasticsearch", "query_string": query or "*"},
        "streams": [STREAMS[stream]], "series": series,
        "row_groups": [{"type": "values", "field": f, "limit": limit} for f in (group_by or [])],
        "column_groups": [], "rollup": True, "filter": None,
        "sort": [{"type": "series", "field": "count", "direction": "Descending"}],
    }
    body = {
        "id": secrets.token_hex(12), "parameters": [],
        "queries": [{"id": str(uuid.uuid4()), "timerange": w.timerange(),
                     "query": {"type": "elasticsearch", "query_string": ""}, "search_types": [st]}],
    }
    res = call("POST", "/views/search/sync?timeout=90000", body)
    result = next(iter(res["results"].values()))
    if result.get("errors"):
        raise RuntimeError(f"pivot failed: {result['errors'][0].get('description', '')[:200]}")
    rows = []
    for row in result["search_types"]["st"].get("rows", []):
        if row.get("source") not in ("leaf", "non-leaf") and group_by:
            continue
        out = {"key": " | ".join(row["key"])} if row["key"] else {}
        for v in row["values"]:
            val = v["value"]
            out[v["key"][-1]] = round(val, 3) if isinstance(val, float) else val
        rows.append(out)
    rows.sort(key=lambda r: r.get("count", 0), reverse=True)
    return rows[:limit] if group_by else rows


def normalize(text: str) -> str:
    text = re.sub(r"\b\d{1,3}(?:\.\d{1,3}){3}\b", "<ip>", text)
    text = re.sub(r"\b[0-9a-f]{8}-[0-9a-f-]{27}\b", "<uuid>", text)
    text = re.sub(r"/releases/\d+/", "/releases/<n>/", text)
    text = re.sub(r"\b\d+\b", "<n>", text)
    return text[:220]


def top_normalized(lines: list[str], n: int = 10) -> list[dict]:
    c = collections.Counter(normalize(line) for line in lines if line)
    return [{"pattern": k, "count": v} for k, v in c.most_common(n)]


def summarize_logins(rows: list[dict]) -> list[dict]:
    """Group sshd 'Accepted' lines by host, method, user and source IP."""
    c = collections.Counter()
    for m in rows:
        line = m.get("message", "")
        hit = re.search(r"(\S+) sshd\[\d+\]: Accepted (\S+) for (\S+) from (\S+)", line)
        c[" ".join(hit.groups()) if hit else line[:120]] += 1
    return [{"login": k, "count": v} for k, v in c.most_common(15)]


def both(fn, cur: Window, prev: Window) -> dict:
    return {"last_24h": fn(cur), "previous_24h": fn(prev)}


def section(name: str, builder, errors: list) -> dict | None:
    try:
        return builder()
    except Exception as e:  # one broken query must not kill the whole digest
        errors.append(f"{name}: {e}")
        return None


def build(hours: int) -> dict:
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    cur = Window(now - dt.timedelta(hours=hours), now)
    prev = Window(now - dt.timedelta(hours=2 * hours), now - dt.timedelta(hours=hours))
    errors: list[str] = []

    def c(stream, query):
        return lambda w: count(stream, query, w)

    report: dict = {
        "generated_at": iso(now),
        "window": {"from": iso(cur.start), "to": iso(cur.end), "compared_with_from": iso(prev.start)},
    }

    report["stream_volume"] = section("stream_volume", lambda: {
        s: both(c(s, "*"), cur, prev) for s in STREAMS
    }, errors)

    def traffic():
        overall = pivot("app", ACCESS, cur, percentiles=(50, 95, 99), latency_field="nginx_request_time_num")
        prev_overall = pivot("app", ACCESS, prev, percentiles=(95,), latency_field="nginx_request_time_num")
        paths = pivot("app", ACCESS, cur, ["nginx_path"], 40, (95,), "nginx_request_time_num")
        return {
            "overall": overall[0] if overall else {},
            "overall_previous_24h": prev_overall[0] if prev_overall else {},
            "by_status": pivot("app", ACCESS, cur, ["nginx_status_int"], 15),
            "by_server": pivot("app", ACCESS, cur, ["source"], 5, (95,), "nginx_request_time_num"),
            "by_host": pivot("app", ACCESS, cur, ["nginx_host"], 10),
            "slowest_paths_p95": sorted(
                [r for r in paths if r.get("count", 0) >= 20], key=lambda r: r.get("p95") or 0, reverse=True)[:10],
            "requests_over_5s": both(c("app", f"{ACCESS} AND nginx_request_time_num:>5"), cur, prev),
            "top_paths_over_5s": pivot("app", f"{ACCESS} AND nginx_request_time_num:>5", cur, ["nginx_path"], 10),
        }

    report["traffic"] = section("traffic", traffic, errors)

    def server_errors():
        q = f"{ACCESS} AND nginx_status_int:>=500 AND NOT nginx_status_int:444"
        return {
            "count_5xx": both(c("app", q), cur, prev),
            "by_status": pivot("app", q, cur, ["nginx_status_int"], 10),
            "top_paths": pivot("app", q, cur, ["nginx_path"], 10),
            "by_server": pivot("app", q, cur, ["source"], 5),
        }

    report["server_errors"] = section("server_errors", server_errors, errors)

    def protection():
        blocked = f"{ACCESS} AND nginx_blocklisted:1"
        limited = f"{ACCESS} AND _exists_:nginx_rate_limit AND NOT nginx_rate_limit:PASSED"
        bad_sess = f"{ACCESS} AND nginx_bad_phpsessid:1"
        php2shell = f"{ACCESS} AND nginx_php2shell_blocked:1"
        return {
            "blocklist_444": {
                "count": both(c("app", blocked), cur, prev),
                "top_ips": pivot("app", blocked, cur, ["nginx_ip"], 10),
                "top_countries": pivot("app", blocked, cur, ["nginx_ip_country_code"], 10),
                "top_paths": pivot("app", blocked, cur, ["nginx_path"], 10),
            },
            "rate_limit_dry_run": {
                "by_status": pivot("app", f"{ACCESS} AND _exists_:nginx_rate_limit", cur, ["nginx_rate_limit"], 10),
                "would_be_limited": both(c("app", limited), cur, prev),
                "top_ips": pivot("app", limited, cur, ["nginx_ip", "nginx_ip_country_code"], 15),
                "top_paths": pivot("app", limited, cur, ["nginx_path"], 10),
                "top_user_agents": pivot("app", limited, cur, ["nginx_user_agent"], 5),
            },
            "bad_phpsessid_400": {
                "count": both(c("app", bad_sess), cur, prev),
                "top_ips": pivot("app", bad_sess, cur, ["nginx_ip", "nginx_ip_country_code"], 10),
            },
            "php2shell_multipart_block": {
                "count": both(c("app", php2shell), cur, prev),
                "top_ips": pivot("app", php2shell, cur, ["nginx_ip", "nginx_ip_country_code"], 10),
                "legacy_log_lines": both(c("app", PHP2SHELL_LOG), cur, prev),
                "legacy_log_samples": [m.get("message", "")[:220] for m in
                                       messages("app", PHP2SHELL_LOG, cur, "message", 10)],
            },
            "blocklist_updater": {
                "log_lines": count("app", BLOCKLIST_LOG, cur),
                "last_lines": [m.get("message", "")[:220] for m in
                               messages("app", BLOCKLIST_LOG, cur, "message,source", 6)],
            },
            "client_errors_4xx_top_ips": pivot(
                "app", f"{ACCESS} AND nginx_status_int:[400 TO 443]", cur, ["nginx_ip", "nginx_ip_country_code"], 10),
            "probe_404_top_paths": pivot("app", f"{ACCESS} AND nginx_status_int:404", cur, ["nginx_path"], 15),
            "top_ips_all_traffic": pivot("app", ACCESS, cur, ["nginx_ip", "nginx_ip_country_code"], 10),
            "top_countries_all_traffic": pivot("app", ACCESS, cur, ["nginx_ip_country_code"], 10),
        }

    report["protection"] = section("protection", protection, errors)

    def php_fpm():
        fpm_lines = [m.get("message", "") for m in
                     messages("app", f"{FPM_LOG} AND NOT message:NOTICE", cur, "message,source", 1500)]
        slow_scripts = collections.Counter()
        for line in fpm_lines:
            m = re.search(r'request: "([A-Z]+ [^"]+)"\) executing too slow', line)
            if m:
                slow_scripts[m.group(1)] += 1
        slow_frames = collections.Counter(
            normalize(m.get("message", "")).split("] ", 1)[-1]
            for m in messages("app", SLOW_LOG, cur, "message", 3000)
            if "/vendor/" not in m.get("message", "") and "[0x" in m.get("message", "")
        )
        return {
            "max_children_reached": both(c("app", f'{FPM_LOG} AND message:"reached pm.max_children"'), cur, prev),
            "max_children_by_server": pivot("app", f'{FPM_LOG} AND message:"reached pm.max_children"', cur, ["source"], 5),
            "max_children_samples": [m.get("source", "") + " " + m.get("message", "")[:160] for m in
                                     messages("app", f'{FPM_LOG} AND message:"reached pm.max_children"', cur, "message,source", 10)],
            "crashes_signal": both(c("app", f'{FPM_LOG} AND message:"exited on signal"'), cur, prev),
            "crash_samples": [m.get("message", "")[:200] for m in
                              messages("app", f'{FPM_LOG} AND message:"exited on signal"', cur, "message", 10)],
            "executing_too_slow": both(c("app", f'{FPM_LOG} AND message:"executing too slow"'), cur, prev),
            "slow_requests_by_route": [{"request": k, "count": v} for k, v in slow_scripts.most_common(10)],
            "slowlog_top_app_frames": [{"frame": k, "count": v} for k, v in slow_frames.most_common(12)],
            "other_warnings": top_normalized(
                [line for line in fpm_lines if "executing too slow" not in line and "reached pm.max_children" not in line], 8),
        }

    report["php_fpm"] = section("php_fpm", php_fpm, errors)

    def nginx_errors():
        lines = [m.get("message", "") for m in messages("app", NGINX_ERR, cur, "message", 2000)]
        cleaned = [re.sub(r"^\S+ \S+ \[(\w+)\] \d+#\d+: \*\d+ ", r"[\1] ", line) for line in lines]
        return {"count": both(c("app", NGINX_ERR), cur, prev), "top_patterns": top_normalized(cleaned, 10)}

    report["nginx_error_log"] = section("nginx_error_log", nginx_errors, errors)

    def ssh():
        def block(stream):
            base = f"{AUTH_LOG} AND " if stream == "app" else ""
            accepted = messages(stream, f'{base}message:"Accepted"', cur, "message,source", 500)
            return {
                "failed_password": both(c(stream, f'{base}message:"Failed password"'), cur, prev),
                "invalid_user": both(c(stream, f'{base}message:"Invalid user"'), cur, prev),
                "accepted_logins": summarize_logins(accepted),
                "sudo_commands": [m.get("message", "")[:200] for m in
                                  messages(stream, f'{base}message:"COMMAND="', cur, "message", 15)],
            }
        return {"app_servers": block("app"), "bastion": block("bastion")}

    report["ssh"] = section("ssh", ssh, errors)

    def laravel():
        err = messages("laravel", "level:<=3", cur, "message,exception,file,line,team_id,source", 1000)
        warn = messages("laravel", "level:4", cur, "message", 1000)
        sqlstate = messages("laravel", "message:SQLSTATE OR exception:*QueryException*", cur, "message", 300)
        return {
            "errors": both(c("laravel", "level:<=3"), cur, prev),
            "warnings": both(c("laravel", "level:4"), cur, prev),
            "top_errors": top_normalized([
                (m.get("exception", "") + " " + m.get("message", "")).strip() for m in err], 12),
            "top_warnings": top_normalized([m.get("message", "") for m in warn], 8),
            "sqlstate": both(c("laravel", "message:SQLSTATE"), cur, prev),
            "sqlstate_patterns": top_normalized([m.get("message", "") for m in sqlstate], 8),
            "errors_by_team": pivot("laravel", "level:<=3 AND _exists_:team_id", cur, ["team_id"], 8),
        }

    report["laravel"] = section("laravel", laravel, errors)

    def postgres():
        q_err = "message:(ERROR OR FATAL OR PANIC) AND NOT message:_aiven"
        lines = [re.sub(r"^\[\d+-\d+\] pid=\d+,", "", m.get("message", ""))
                 for m in messages("postgres", q_err, cur, "message", 1000)]
        return {
            "errors": both(c("postgres", q_err), cur, prev),
            "top_error_patterns": top_normalized(lines, 10),
            "deadlocks": count("postgres", 'message:"deadlock detected"', cur),
            "too_many_connections": count("postgres", 'message:"too many" AND message:connections', cur),
            "lock_waits": count("postgres", 'message:"still waiting for"', cur),
            "slow_statements_logged": count("postgres", 'message:"duration:"', cur),
            "slow_statement_samples": [m.get("message", "")[:300] for m in
                                       messages("postgres", 'message:"duration:"', cur, "message", 5)],
        }

    report["postgres"] = section("postgres", postgres, errors)
    report["query_errors"] = errors
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--hours", type=int, default=24)
    args = parser.parse_args()
    json.dump(build(args.hours), sys.stdout, ensure_ascii=False, indent=1, default=str)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
