#!/usr/bin/env python3
"""
Apple Cleanup Web Dashboard — HTTP Server (v2.0.0)
Serves the web UI and proxies API requests to clean_mac.sh

Security features:
  - Whitelist validation for all sub-item parameters
  - Content-Type enforcement on POST endpoints
  - Request body size limit (1MB)
  - Path traversal prevention for static files
  - Integer coercion for category indices
  - Boolean normalization for scan JSON fields
"""

import glob
import hmac
import http.server
import json
import os
import plistlib
import re
import secrets
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import webbrowser
from pathlib import Path

# Bind to loopback only — this API can delete files and must never be
# reachable from the local network.
HOST = "127.0.0.1"
PORT = 8080
WEB_DIR = Path(__file__).parent.resolve()
SCRIPT_PATH = (WEB_DIR.parent / "clean_mac.sh").resolve()

# Maximum allowed request body size (1 MB)
MAX_BODY_SIZE = 1 * 1024 * 1024  # 1,048,576 bytes

# ── Storage forecast ─────────────────────────────────────────────────────────
# The Bash script is stateless, so disk-usage history lives here. We append a
# snapshot (at most once per hour), keep 90 days, and fit a least-squares line
# to predict when the disk will fill.
HISTORY_FILE = os.path.expanduser("~/.cache/apple-cleanup/usage_history.json")
MAX_HISTORY_DAYS = 90
SNAPSHOT_INTERVAL = 3600           # seconds between recorded snapshots
FORECAST_HORIZON_DAYS = 365        # don't report a forecast beyond a year


def _load_history():
    """Load usage history as a list of (timestamp, used_bytes) tuples."""
    try:
        with open(HISTORY_FILE) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return []
    if not isinstance(data, list):
        return []
    out = []
    for e in data:
        if isinstance(e, (list, tuple)) and len(e) == 2:
            try:
                out.append((float(e[0]), int(e[1])))
            except (ValueError, TypeError):
                continue
    out.sort(key=lambda p: p[0])
    return out


def _save_history(history):
    """Persist usage history; failures are non-fatal."""
    try:
        os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)
        tmp = HISTORY_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump([[t, u] for t, u in history], f)
        os.replace(tmp, HISTORY_FILE)
    except OSError:
        pass


def _record_snapshot(history, used_bytes, now=None):
    """
    Append a snapshot (throttled to once per SNAPSHOT_INTERVAL) and prune to
    MAX_HISTORY_DAYS. Pure function — pass `now` for deterministic tests.
    """
    now = time.time() if now is None else now
    if history and (now - history[-1][0]) < SNAPSHOT_INTERVAL:
        updated = list(history)
    else:
        updated = list(history) + [(now, int(used_bytes))]
    cutoff = now - MAX_HISTORY_DAYS * 86400
    return [(t, u) for t, u in updated if t > cutoff]


def compute_forecast(history, total_bytes, used_bytes):
    """
    Fit a least-squares line to (days, used_bytes) and project days until full.
    Returns days_until_full (None when not enough data / not growing / >1yr),
    the daily growth rate, and history coverage stats.
    """
    result = {
        "days_until_full": None,
        "daily_growth_bytes": 0,
        "history_points": len(history),
        "history_span_days": 0,
    }
    n = len(history)
    if n < 2:
        return result

    ts0 = history[0][0]
    xs = [(t - ts0) / 86400.0 for t, _ in history]   # days since first sample
    ys = [float(u) for _, u in history]
    span = xs[-1]
    result["history_span_days"] = max(0, int(span))
    if span < 1.0:                                    # need at least a day
        return result

    xmean = sum(xs) / n
    ymean = sum(ys) / n
    num = sum((x - xmean) * (y - ymean) for x, y in zip(xs, ys))
    den = sum((x - xmean) ** 2 for x in xs)
    if den == 0:
        return result

    rate = num / den                                  # bytes/day
    result["daily_growth_bytes"] = int(rate)
    if rate <= 0:                                      # stable or shrinking
        return result

    remaining = total_bytes - used_bytes
    days_left = remaining / rate
    if 0 < days_left <= FORECAST_HORIZON_DAYS:
        result["days_until_full"] = max(1, int(days_left))
    return result

# Per-process CSRF/session token. Regenerated on every server start and
# embedded into the served index.html; destructive endpoints require it.
SESSION_TOKEN = secrets.token_urlsafe(32)
TOKEN_PLACEHOLDER = "__CLEANUP_TOKEN__"

# Loopback host names accepted in the Host / Origin headers. Anything else is
# rejected to defeat DNS-rebinding attacks against the loopback binding.
_LOOPBACK_HOSTS = frozenset({"localhost", "127.0.0.1", "::1", "ip6-localhost"})


def _host_only(value: str) -> str:
    """Strip scheme, port and IPv6 brackets, returning the bare host."""
    if not value:
        return ""
    # Drop scheme (http://host) if present
    if "://" in value:
        value = value.split("://", 1)[1]
    value = value.strip().rstrip("/")
    # Bracketed IPv6 literal, optionally with :port
    if value.startswith("["):
        return value[1:].split("]", 1)[0]
    # host:port — split on the last colon only if it looks like a port
    if value.count(":") == 1:
        value = value.split(":", 1)[0]
    return value


def _is_allowed_host(host_header: str) -> bool:
    """True if the Host header points at a loopback address."""
    return _host_only(host_header) in _LOOPBACK_HOSTS


def _is_allowed_origin(origin_header) -> bool:
    """
    True if the Origin header is absent (non-browser client) or points at a
    loopback address. Blocks cross-site requests from real web pages.
    """
    if not origin_header:
        return True
    if origin_header == "null":
        return False
    return _host_only(origin_header) in _LOOPBACK_HOSTS


def _extra_env_for_clean(payload: dict) -> dict:
    """
    Derive environment overrides for a clean request. Currently exposes the
    dry-run preview mode. Requires a real boolean True (not a truthy string)
    so a stray field can never silently disable real cleaning or enable it.
    """
    env = {}
    if isinstance(payload, dict) and payload.get("dry_run") is True:
        env["APPLE_CLEANUP_DRYRUN"] = "1"
    return env


def _token_matches(token) -> bool:
    """Constant-time comparison of a supplied token against the session token."""
    if not token or not isinstance(token, str):
        return False
    return hmac.compare_digest(token, SESSION_TOKEN)

MIME_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
    ".woff2": "font/woff2",
}

# ── Input Validation ─────────────────────────────────────────────────────────
# Regex for app leftover dir names and app names
_APP_LEFTOVER_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$')
_APP_NAME_RE     = re.compile(r'^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$')
# Homebrew formula/cask tokens are lowercase alphanumerics plus -, _, ., @, /
# (the slash appears in tap-qualified names like "homebrew/cask/foo").
_BREW_NAME_RE    = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._@/-]{0,127}$')

# Developer sub-item whitelist — MUST be 100% in sync with clean_mac.sh
# Corresponds to the case statement in clean_developer() JSON mode
_DEVELOPER_WHITELIST = frozenset({
    "derived_data",        # Xcode DerivedData
    "broken_links",        # Broken symlinks
    "brew_cache",          # Homebrew cache
    "docker_prune",        # Docker system prune
    "npm_cache",           # npm _cacache
    "pip_cache",           # pip cache
    "device_support",      # iOS DeviceSupport
    "coresim_caches",      # CoreSimulator Caches
    "xcode_archives",      # Xcode Archives
    "cocoapods_cache",     # CocoaPods Cache
    "pnpm_cache",          # pnpm Store
    "yarn_cache",          # Yarn Cache
    "gradle_cache",        # Gradle caches
    "maven_repo",          # Maven repository
    "simctl_unavailable",  # Delete unavailable simulators
    "xcode_products",      # Xcode Products
    "simulator_logs",      # Simulator logs
    "simulator_devices",   # Simulator devices
    "font_caches",         # Font caches
    "brew_cleanup",        # Homebrew cleanup command
    "swift_pm_cache",      # Swift package manager cache
    "xcode_logs",          # Xcode logs
    # Extended developer caches (safe, rebuildable)
    "xcode_previews",      # SwiftUI preview data
    "carthage_cache",      # Carthage dependency cache
    "bun_cache",           # Bun package cache
    "deno_cache",          # Deno module cache
    "conda_pkgs",          # Conda package cache
    "uv_cache",            # uv (Python) cache
    "poetry_cache",        # Poetry cache
    "go_modules",          # Go module download cache
    "cargo_registry",      # Rust Cargo registry cache
    "composer_cache",      # PHP Composer cache
    "gradle_wrapper",      # Gradle wrapper distributions
    "sbt_ivy_cache",       # SBT/Ivy cache
    "bazel_cache",         # Bazel build/repo cache
    "flutter_pub_cache",   # Flutter/Pub cache
    "jetbrains_cache",     # JetBrains IDE caches
    "playwright_cache",    # Playwright browser binaries
    "puppeteer_cache",     # Puppeteer browser binaries
    "prisma_cache",        # Prisma engine binaries
    "huggingface_cache",   # HuggingFace model cache (caution: large re-download)
})

# Browser key whitelist — MUST be 100% in sync with clean_mac.sh
# Corresponds to browser_keys array in clean_browser_full()
_BROWSER_WHITELIST = frozenset({
    "safari",    # ~/Library/Safari
    "cookies",   # ~/Library/Cookies
    "chrome",    # ~/Library/Application Support/Google/Chrome
    "firefox",   # ~/Library/Application Support/Firefox
    "brave",     # ~/Library/Application Support/BraveSoftware
    "edge",      # ~/Library/Application Support/Microsoft Edge
    "opera",     # ~/Library/Application Support/com.operasoftware.Opera
    "arc",       # ~/Library/Application Support/Arc
})


_SESSION_RE = re.compile(r"^[0-9A-Fa-f-]{8,40}$|^[0-9]{1,10}-[0-9]{1,12}$")


def _validate_session_id(s) -> bool:
    """Validate a restore-session id: UUID-ish or pid-timestamp fallback."""
    return isinstance(s, str) and bool(_SESSION_RE.match(s))


def _validate_item_ids(lst) -> bool:
    """Validate a list of restore item ids: non-empty list of non-negative ints."""
    if not isinstance(lst, list) or not lst:
        return False
    return all(isinstance(x, int) and not isinstance(x, bool) and x >= 0 for x in lst)


def _validate_app_leftover(name: str) -> bool:
    """Validate an app leftover directory name (no traversal, no injection)."""
    return bool(_APP_LEFTOVER_RE.match(name)) and ".." not in name and "/" not in name


def _validate_developer_item(item: str) -> bool:
    """Validate a developer sub-item key against the whitelist."""
    return item in _DEVELOPER_WHITELIST


def _validate_browser_key(key: str) -> bool:
    """Validate a browser key against the whitelist."""
    return key in _BROWSER_WHITELIST


def _validate_app_name(name: str) -> bool:
    """Validate an application name for uninstallation."""
    return bool(_APP_NAME_RE.match(name)) and ".." not in name and "/" not in name


def _validate_brew_name(name: str) -> bool:
    """Validate a Homebrew formula/cask token for uninstallation."""
    return bool(_BREW_NAME_RE.match(name)) and ".." not in name


# Recognized build/dependency artifact directory names. Kept in sync with
# clean_mac.sh _PROJECT_ARTIFACT_NAMES. The shell re-validates that the parent
# holds a project marker before deleting; this is a lightweight first gate.
_PROJECT_ARTIFACT_NAMES = frozenset({
    "node_modules", "target", ".build", "build",
    "vendor", ".dart_tool", ".terraform",
})


def _validate_project_artifact(path: str) -> bool:
    """Validate a project-artifact path before passing it to the script."""
    return (
        isinstance(path, str)
        and path.startswith("/")
        and ".." not in path
        and os.path.basename(path.rstrip("/")) in _PROJECT_ARTIFACT_NAMES
    )


def _normalize_bool_fields(data: dict) -> dict:
    """
    Recursively normalize boolean string fields in scan JSON.
    Converts string "true"/"false" to Python bool True/False.
    Also ensures needs_sudo is always a proper bool.
    """
    if not isinstance(data, dict):
        return data

    for key, value in data.items():
        if isinstance(value, str):
            if value.lower() == "true":
                data[key] = True
            elif value.lower() == "false":
                data[key] = False
        elif isinstance(value, dict):
            _normalize_bool_fields(value)
        elif isinstance(value, list):
            for item in value:
                if isinstance(item, dict):
                    _normalize_bool_fields(item)
    return data


class CleanupHandler(http.server.BaseHTTPRequestHandler):
    """Request handler for the Apple Cleanup dashboard."""

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[server] {fmt % args}\n")

    # ── Security headers ────────────────────────────────────
    def _security_headers(self):
        # No wildcard CORS: the dashboard is served same-origin, so cross-origin
        # reads must stay blocked. These headers harden the responses further.
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")

    def do_OPTIONS(self):
        # Same-origin only; no CORS preflight is honoured.
        self.send_response(204)
        self._security_headers()
        self.end_headers()

    def _require_loopback_host(self) -> bool:
        """Reject requests whose Host header is not a loopback address."""
        if _is_allowed_host(self.headers.get("Host", "")):
            return True
        self._send_error_json("Forbidden host", 403)
        return False

    def _require_csrf(self) -> bool:
        """Enforce Origin and session-token checks on state-changing requests."""
        if not _is_allowed_origin(self.headers.get("Origin")):
            self._send_error_json("Cross-origin request blocked", 403)
            return False
        if not _token_matches(self.headers.get("X-Cleanup-Token")):
            self._send_error_json("Missing or invalid session token", 403)
            return False
        return True

    # ── Helpers ─────────────────────────────────────────────
    def _send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self._security_headers()
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_error_json(self, message, status=500):
        self._send_json({"success": False, "error": message}, status)

    def _read_json_body(self) -> tuple:
        """
        Read and parse JSON from POST body with Content-Type and size checks.
        Returns (payload_dict, None) on success or (None, error_message) on failure.
        """
        # Content-Type validation
        content_type = self.headers.get("Content-Type", "")
        if "application/json" not in content_type:
            return None, "Content-Type must be application/json"

        # Body size check
        try:
            length = int(self.headers.get("Content-Length", 0))
        except (ValueError, TypeError):
            return None, "Invalid Content-Length header"

        if length <= 0:
            return None, "Empty request body"

        if length > MAX_BODY_SIZE:
            return None, f"Request body too large (max {MAX_BODY_SIZE} bytes)"

        # Read and parse
        try:
            body = self.rfile.read(length).decode("utf-8")
            payload = json.loads(body)
        except json.JSONDecodeError:
            return None, "Invalid JSON body"
        except UnicodeDecodeError:
            return None, "Request body must be UTF-8 encoded"

        if not isinstance(payload, dict):
            return None, "JSON body must be an object"

        return payload, None

    def _run_script(self, args, timeout=120, env_extra=None):
        """Run clean_mac.sh with given arguments and return parsed JSON."""
        cmd = ["bash", str(SCRIPT_PATH)] + args
        run_env = dict(os.environ)
        if env_extra:
            run_env.update(env_extra)
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=str(SCRIPT_PATH.parent),
                env=run_env,
            )
            output = result.stdout.strip()
            if not output:
                return None, result.stderr.strip() or "Script returned no output"
            parsed = json.loads(output)

            # Normalize boolean fields (Bash outputs JSON bool literals,
            # but this ensures consistency even if format changes)
            if isinstance(parsed, dict):
                _normalize_bool_fields(parsed)

            return parsed, None
        except subprocess.TimeoutExpired:
            return None, "Script timed out"
        except json.JSONDecodeError as e:
            return None, f"Invalid JSON from script: {e}"
        except Exception as e:
            return None, str(e)

    # ── Routes ──────────────────────────────────────────────
    def do_GET(self):
        if not self._require_loopback_host():
            return
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        # API endpoints
        if path == "/api/scan":
            self._handle_scan()
        elif path == "/api/status":
            self._handle_status()
        elif path == "/api/apps":
            self._handle_apps()
        elif path == "/api/forecast":
            self._handle_forecast()
        elif path == "/api/history":
            self._handle_history()
        elif path == "/api/operations":
            self._handle_operations()
        else:
            self._serve_static(path)

    def do_POST(self):
        if not self._require_loopback_host():
            return
        if not self._require_csrf():
            return
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/clean":
            self._handle_clean()
        elif parsed.path == "/api/spotlight-reindex":
            self._handle_spotlight_reindex()
        elif parsed.path == "/api/flush-dns":
            self._handle_flush_dns()
        elif parsed.path == "/api/purge-ram":
            self._handle_purge_ram()
        elif parsed.path == "/api/launchagents-clean":
            self._handle_launchagents_clean()
        elif parsed.path == "/api/thin-snapshots":
            self._handle_thin_snapshots()
        elif parsed.path == "/api/uninstall":
            self._handle_uninstall()
        elif parsed.path == "/api/restore":
            self._handle_restore()
        else:
            self._send_error_json("Not found", 404)

    # ── API Handlers ────────────────────────────────────────
    def _handle_scan(self):
        data, err = self._run_script(["--scan-json"])
        if err:
            self._send_error_json(f"Scan error: {err}")
        else:
            self._send_json(data)

    def _handle_status(self):
        data, err = self._run_script(["--status-json"], timeout=15)
        if err:
            self._send_error_json(f"Status error: {err}")
        else:
            self._send_json(data)

    def _handle_history(self):
        data, err = self._run_script(["--history-json"], timeout=15)
        if err:
            self._send_error_json(f"History error: {err}")
        else:
            self._send_json(data)

    def _handle_operations(self):
        data, err = self._run_script(["--ops-json"], timeout=30)
        if err:
            self._send_error_json(f"Operations error: {err}")
        else:
            self._send_json(data)

    def _handle_restore(self):
        payload, err = self._read_json_body()
        if err:
            return self._send_error_json(err, 400)
        if "session_id" in payload:
            if not _validate_session_id(payload["session_id"]):
                return self._send_error_json("invalid session_id", 400)
            args = ["--restore-session", payload["session_id"]]
        elif "item_ids" in payload:
            if not _validate_item_ids(payload["item_ids"]):
                return self._send_error_json("invalid item_ids", 400)
            args = ["--restore-items", ",".join(str(i) for i in payload["item_ids"])]
        else:
            return self._send_error_json("session_id or item_ids required", 400)
        data, err = self._run_script(args, timeout=60)
        if err:
            self._send_error_json(f"Restore error: {err}")
        else:
            self._send_json(data)

    def _handle_forecast(self):
        try:
            usage = shutil.disk_usage("/")
        except OSError as e:
            self._send_error_json(f"Disk usage error: {e}")
            return
        history = _record_snapshot(_load_history(), usage.used)
        _save_history(history)
        data = compute_forecast(history, usage.total, usage.used)
        data["success"] = True
        data["total_bytes"] = usage.total
        data["used_bytes"] = usage.used
        data["free_bytes"] = usage.free
        self._send_json(data)

    def _handle_clean(self):
        payload, err = self._read_json_body()
        if err:
            self._send_error_json(err, 400)
            return

        categories = payload.get("categories", [])
        if not categories or not isinstance(categories, list):
            self._send_error_json("Category list required", 400)
            return

        # Integer coercion: frontend may send strings like "3" instead of 3
        safe_cats = []
        for c in categories:
            try:
                safe_cats.append(int(c))
            except (ValueError, TypeError):
                pass  # Skip invalid entries silently
        if not safe_cats:
            self._send_error_json("No valid category indices provided", 400)
            return

        cat_str = ",".join(str(c) for c in safe_cats)
        args = ["--clean-json", cat_str]

        # App leftovers sub-items
        app_leftovers_selected = payload.get("app_leftovers_selected", [])
        if app_leftovers_selected and isinstance(app_leftovers_selected, list):
            safe = [x for x in app_leftovers_selected
                    if isinstance(x, str) and _validate_app_leftover(x)]
            if safe:
                args += ["--app-leftovers", ",".join(safe)]

        # Browser full sub-items
        browser_full_selected = payload.get("browser_full_selected", [])
        if browser_full_selected and isinstance(browser_full_selected, list):
            safe = [x for x in browser_full_selected
                    if isinstance(x, str) and _validate_browser_key(x)]
            if safe:
                args += ["--browser-full-sub", ",".join(safe)]

        # Developer sub-items
        developer_selected = payload.get("developer_selected", [])
        if developer_selected and isinstance(developer_selected, list):
            safe = [x for x in developer_selected
                    if isinstance(x, str) and _validate_developer_item(x)]
            if safe:
                args += ["--developer-sub", ",".join(safe)]

        # iOS backups sub-items
        ios_backups_selected = payload.get("ios_backups_selected", [])
        if ios_backups_selected and isinstance(ios_backups_selected, list):
            _uuid_re = re.compile(r'^[0-9A-Fa-f\-]{1,40}$')
            safe_uuids = [u for u in ios_backups_selected
                         if isinstance(u, str) and _uuid_re.match(u)]
            if safe_uuids:
                args += ["--ios-backups-sub", ",".join(safe_uuids)]

        # App uninstaller sub-items
        app_uninstaller_selected = payload.get("app_uninstaller_selected", [])
        if app_uninstaller_selected and isinstance(app_uninstaller_selected, list):
            safe = [x for x in app_uninstaller_selected
                    if isinstance(x, str) and _validate_app_name(x)]
            if safe:
                args += ["--app-uninstaller-sub", ",".join(safe)]

        # Project artifact sub-items (paths validated; comma-separated)
        project_artifacts_selected = payload.get("project_artifacts_selected", [])
        if project_artifacts_selected and isinstance(project_artifacts_selected, list):
            safe = [x for x in project_artifacts_selected
                    if _validate_project_artifact(x)]
            if safe:
                args += ["--project-artifact-sub", ",".join(safe)]

        data, err = self._run_script(args, env_extra=_extra_env_for_clean(payload))
        if err:
            self._send_error_json(f"Clean error: {err}")
        else:
            self._send_json(data)

    def _handle_spotlight_reindex(self):
        data, err = self._run_script(["--spotlight-reindex"], timeout=45)
        if err:
            self._send_error_json(f"Spotlight Indexing Failure: {err}")
        else:
            self._send_json(data)

    def _handle_flush_dns(self):
        data, err = self._run_script(["--flush-dns"], timeout=15)
        if err:
            self._send_error_json(f"DNS flush error: {err}")
        else:
            self._send_json(data)

    def _handle_purge_ram(self):
        data, err = self._run_script(["--purge-ram"], timeout=30)
        if err:
            self._send_error_json(f"RAM purge error: {err}")
        else:
            self._send_json(data)

    def _handle_launchagents_clean(self):
        data, err = self._run_script(["--launchagents-clean"], timeout=30)
        if err:
            self._send_error_json(f"LaunchAgents clean error: {err}")
        else:
            self._send_json(data)

    def _handle_thin_snapshots(self):
        data, err = self._run_script(["--thin-snapshots-json"], timeout=120)
        if err:
            self._send_error_json(f"Snapshot thinning error: {err}")
        else:
            self._send_json(data)

    def _run_cmd(self, cmd, timeout=60):
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            return res.returncode == 0, res.stdout, res.stderr
        except subprocess.TimeoutExpired:
            return False, "", "Command timed out"
        except Exception as e:
            return False, "", str(e)

    def _handle_apps(self):
        try:
            # We will scan and aggregate installed applications.
            # 1. Glob /Applications/*.app and ~/Applications/*.app
            app_paths = glob.glob("/Applications/*.app") + glob.glob(os.path.expanduser("~/Applications/*.app"))
            app_sizes = {}
            if app_paths:
                try:
                    res = subprocess.run(["du", "-sk"] + app_paths, capture_output=True, text=True, timeout=10)
                    if res.returncode == 0:
                        for line in res.stdout.splitlines():
                            parts = line.split('\t')
                            if len(parts) == 2:
                                app_sizes[parts[1]] = int(parts[0]) * 1024
                except Exception:
                    pass

            # 2. Gather Homebrew casks
            casks = []
            if subprocess.run(["which", "brew"], capture_output=True).returncode == 0:
                try:
                    res = subprocess.run(["brew", "list", "--cask"], capture_output=True, text=True, timeout=10)
                    if res.returncode == 0:
                        casks = [line.strip() for line in res.stdout.splitlines() if line.strip()]
                except Exception:
                    pass

            caskroom = "/opt/homebrew/Caskroom" if os.path.exists("/opt/homebrew/Caskroom") else "/usr/local/Caskroom"

            # Helper for formatting bytes
            def format_bytes(b):
                if b >= 1024*1024*1024:
                    return f"{b / (1024*1024*1024):.1f} GB"
                elif b >= 1024*1024:
                    return f"{b / (1024*1024):.1f} MB"
                elif b >= 1024:
                    return f"{b / 1024:.1f} KB"
                else:
                    return f"{b} B"

            def clean_name(n):
                return "".join(c.lower() for c in os.path.splitext(n)[0] if c.isalnum())

            def format_display_name(cask_id):
                return " ".join(word.capitalize() for word in cask_id.replace("-", " ").replace("_", " ").split())

            cask_set = set(casks)
            cask_norm = {clean_name(c): c for c in casks}

            apps_list = []
            processed_casks = set()

            # Process app paths
            for path in app_paths:
                basename = os.path.basename(path)
                name = os.path.splitext(basename)[0]
                norm = clean_name(name)
                size = app_sizes.get(path, 0)

                bundle_id = ""
                version = ""
                display_name = ""
                bundle_name = ""
                plist_path = os.path.join(path, "Contents", "Info.plist")
                if os.path.exists(plist_path):
                    try:
                        with open(plist_path, 'rb') as f:
                            plist = plistlib.load(f)
                            bundle_id = plist.get("CFBundleIdentifier", "")
                            version = plist.get("CFBundleShortVersionString", plist.get("CFBundleVersion", ""))
                            display_name = plist.get("CFBundleDisplayName", "")
                            bundle_name = plist.get("CFBundleName", "")
                    except Exception:
                        pass

                resolved_name = display_name or bundle_name or name
                if resolved_name.endswith('.app'):
                    resolved_name = resolved_name[:-4]

                # Special cleanups for premium visual aesthetics
                if resolved_name == "zoom.us":
                    resolved_name = "Zoom"
                elif resolved_name == "Code":
                    resolved_name = "Visual Studio Code"

                source = "app_dir"
                # Only pair an app with a cask on an exact normalized-name
                # match. Substring matching mislabels unrelated apps as
                # "both", which would change what /api/uninstall deletes.
                matched_cask = cask_norm.get(norm)

                if matched_cask:
                    source = "both"
                    processed_casks.add(matched_cask)

                apps_list.append({
                    "id": matched_cask or name,
                    "name": resolved_name,
                    "folder_name": name,
                    "path": path,
                    "size_bytes": size,
                    "size_human": format_bytes(size),
                    "source": source,
                    "bundle_id": bundle_id,
                    "version": version
                })

            # Process remaining casks
            for cask in cask_set - processed_casks:
                cpath = os.path.join(caskroom, cask)
                size = 0
                version = ""
                if os.path.exists(cpath):
                    try:
                        subdirs = [d for d in os.listdir(cpath) if os.path.isdir(os.path.join(cpath, d))]
                        if subdirs:
                            version = subdirs[0]
                        res = subprocess.run(["du", "-sk", cpath], capture_output=True, text=True, timeout=5)
                        if res.returncode == 0:
                            size = int(res.stdout.split()[0]) * 1024
                    except Exception:
                        pass
                apps_list.append({
                    "id": cask,
                    "name": format_display_name(cask),
                    "folder_name": "",
                    "path": cpath,
                    "size_bytes": size,
                    "size_human": format_bytes(size),
                    "source": "brew_cask",
                    "bundle_id": "",
                    "version": version
                })

            apps_list.sort(key=lambda x: x["name"].lower())
            self._send_json({"success": True, "apps": apps_list})
        except Exception as e:
            self._send_error_json(f"Failed to list applications: {e}", 500)

    def _handle_uninstall(self):
        payload, err = self._read_json_body()
        if err:
            self._send_error_json(err, 400)
            return

        app_id = payload.get("id")
        source = payload.get("source")
        folder_name = payload.get("folder_name")

        if not app_id or not isinstance(app_id, str):
            self._send_error_json("id is required", 400)
            return
        if not source or source not in ("brew_cask", "brew", "app_dir", "both"):
            self._send_error_json("Invalid source parameter", 400)
            return

        # Sanitize application name to prevent injection/traversal
        clean_target = folder_name if (folder_name and isinstance(folder_name, str)) else app_id
        if source in ("app_dir", "both"):
            if not _validate_app_name(clean_target):
                self._send_error_json("Invalid application name format", 400)
                return
        # Validate the Homebrew token too — it is passed to `brew uninstall`.
        if source in ("brew", "brew_cask", "both"):
            if not _validate_brew_name(app_id):
                self._send_error_json("Invalid Homebrew package name format", 400)
                return

        success = True
        msg = ""
        details = []

        # If source in ("app_dir", "both"), we run clean_mac.sh FIRST
        # to capture the bundle ID, delete the app, and clean leftovers.
        if source in ("app_dir", "both"):
            # Run clean_mac.sh category 10 (app_uninstaller)
            data, script_err = self._run_script(["--clean-json", "10", "--app-uninstaller-sub", clean_target])
            if script_err:
                success = False
                msg = f"Leftovers cleanup failed: {script_err}"
            else:
                details.append("Application files and leftovers deleted successfully.")

        # If source is ("brew_cask", "both"), run brew uninstall --cask
        if source in ("brew_cask", "both") and success:
            # `--` terminates option parsing so a package token can never be
            # interpreted by brew as a flag.
            cmd = ["brew", "uninstall", "--cask", "--", app_id]
            ok, out, err_out = self._run_cmd(cmd)
            if not ok:
                success = False
                msg = f"Homebrew cask uninstallation failed: {err_out or out}"
            else:
                details.append("Homebrew cask uninstalled successfully.")

        elif source == "brew" and success:
            cmd = ["brew", "uninstall", "--", app_id]
            ok, out, err_out = self._run_cmd(cmd)
            if not ok:
                success = False
                msg = f"Homebrew formula uninstallation failed: {err_out or out}"
            else:
                details.append("Homebrew formula uninstalled successfully.")

        if success:
            self._send_json({
                "success": True,
                "message": "Uninstalled successfully.",
                "details": " ".join(details)
            })
        else:
            self._send_error_json(msg or "Uninstallation failed.")

    # ── Static File Server ──────────────────────────────────
    def _serve_static(self, path):
        if path == "/" or path == "":
            path = "/index.html"

        file_path = (WEB_DIR / path.lstrip("/")).resolve()

        # Security: prevent directory traversal. Compare against the resolved
        # web dir using path semantics so a sibling like "<dir>_evil" can't pass.
        if file_path != WEB_DIR and WEB_DIR not in file_path.parents:
            self._send_error_json("Forbidden", 403)
            return

        if not file_path.is_file():
            self._send_error_json("Not found", 404)
            return

        ext = file_path.suffix.lower()
        content_type = MIME_TYPES.get(ext, "application/octet-stream")

        try:
            data = file_path.read_bytes()
            # Inject the per-session token into the dashboard so the frontend
            # can authenticate destructive requests.
            if file_path.name == "index.html":
                data = data.replace(
                    TOKEN_PLACEHOLDER.encode("utf-8"),
                    SESSION_TOKEN.encode("utf-8"),
                )
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-cache")
            self._security_headers()
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            self._send_error_json(f"File read error: {e}")


def _open_browser():
    """Open the dashboard in the default browser once the server is up.

    Disabled by exporting APPLE_CLEANUP_OPEN_BROWSER=0 (useful when running
    headless or from a terminal where a browser pop-up is unwanted).
    """
    if os.environ.get("APPLE_CLEANUP_OPEN_BROWSER", "1") == "0":
        return
    try:
        webbrowser.open(f"http://localhost:{PORT}/")
    except Exception:
        pass  # Browser launch is best-effort; the server still runs.


def main():
    http.server.HTTPServer.allow_reuse_address = True
    server = http.server.HTTPServer((HOST, PORT), CleanupHandler)
    print(f"🍎 Apple Cleanup Dashboard v2.0.0")
    print(f"   http://localhost:{PORT}  (loopback only)")
    print(f"   Press Ctrl+C to stop\n")
    # Open the browser shortly after the server starts accepting connections.
    threading.Timer(1.0, _open_browser).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n✋ Server stopped.")
        server.server_close()


if __name__ == "__main__":
    main()
