#!/usr/bin/env python3
"""
Apple Cleanup Web Dashboard — HTTP Server
Serves the web UI and proxies API requests to clean_mac.sh
"""

import http.server
import json
import os
import re
import subprocess
import sys
import urllib.parse
from pathlib import Path

PORT = 8080
WEB_DIR = Path(__file__).parent.resolve()
SCRIPT_PATH = (WEB_DIR.parent / "clean_mac.sh").resolve()

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

_APP_LEFTOVER_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$')
_APP_NAME_RE     = re.compile(r'^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$')
_DEVELOPER_WHITELIST = frozenset({
    "derived_data", "broken_links",
    "brew_cache", "docker_prune", "npm_cache", "pip_cache",
    "device_support", "coresim_caches", "xcode_archives",
    "simctl_unavailable", "pnpm_cache", "yarn_cache",
    "cocoapods_cache", "gradle_cache", "maven_repo",
})
_BROWSER_WHITELIST = frozenset({
    "safari", "cookies", "chrome", "firefox",
    "brave", "edge", "opera", "arc",
})


def _validate_app_leftover(name: str) -> bool:
    return bool(_APP_LEFTOVER_RE.match(name)) and ".." not in name and "/" not in name


def _validate_developer_item(item: str) -> bool:
    return item in _DEVELOPER_WHITELIST


def _validate_browser_key(key: str) -> bool:
    return key in _BROWSER_WHITELIST


def _validate_app_name(name: str) -> bool:
    return bool(_APP_NAME_RE.match(name)) and ".." not in name and "/" not in name


class CleanupHandler(http.server.BaseHTTPRequestHandler):
    """Request handler for the Apple Cleanup dashboard."""

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[server] {fmt % args}\n")

    # ── CORS ────────────────────────────────────────────────
    def _cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors_headers()
        self.end_headers()

    # ── Helpers ─────────────────────────────────────────────
    def _send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self._cors_headers()
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_error_json(self, message, status=500):
        self._send_json({"success": False, "error": message}, status)

    def _run_script(self, args, timeout=120):
        """Run clean_mac.sh with given arguments and return parsed JSON."""
        cmd = ["bash", str(SCRIPT_PATH)] + args
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=str(SCRIPT_PATH.parent),
            )
            output = result.stdout.strip()
            if not output:
                return None, result.stderr.strip() or "Script returned no output"
            return json.loads(output), None
        except subprocess.TimeoutExpired:
            return None, "Script timed out"
        except json.JSONDecodeError as e:
            return None, f"Invalid JSON from script: {e}"
        except Exception as e:
            return None, str(e)

    # ── Routes ──────────────────────────────────────────────
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        # API endpoints
        if path == "/api/scan":
            self._handle_scan()
        elif path == "/api/status":
            self._handle_status()
        else:
            self._serve_static(path)

    def do_POST(self):
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
        else:
            self._send_error_json("Not found", 404)

    # ── API Handlers ────────────────────────────────────────
    def _handle_scan(self):
        data, err = self._run_script(["--scan-json"])
        if err:
            self._send_error_json(f"Tarama hatası: {err}")
        else:
            self._send_json(data)

    def _handle_status(self):
        data, err = self._run_script(["--status-json"], timeout=15)
        if err:
            self._send_error_json(f"Durum hatası: {err}")
        else:
            self._send_json(data)

    def _handle_clean(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode("utf-8")
            payload = json.loads(body)
        except (json.JSONDecodeError, ValueError):
            self._send_error_json("Geçersiz JSON gövdesi", 400)
            return

        categories = payload.get("categories", [])
        if not categories or not isinstance(categories, list):
            self._send_error_json("Kategori listesi gerekli", 400)
            return

        cat_str = ",".join(str(c) for c in categories)
        args = ["--clean-json", cat_str]

        app_leftovers_selected = payload.get("app_leftovers_selected", [])
        if app_leftovers_selected and isinstance(app_leftovers_selected, list):
            safe = [x for x in app_leftovers_selected if isinstance(x, str) and _validate_app_leftover(x)]
            if safe:
                args += ["--app-leftovers", ",".join(safe)]

        browser_full_selected = payload.get("browser_full_selected", [])
        if browser_full_selected and isinstance(browser_full_selected, list):
            safe = [x for x in browser_full_selected if isinstance(x, str) and _validate_browser_key(x)]
            if safe:
                args += ["--browser-full-sub", ",".join(safe)]

        developer_selected = payload.get("developer_selected", [])
        if developer_selected and isinstance(developer_selected, list):
            safe = [x for x in developer_selected if isinstance(x, str) and _validate_developer_item(x)]
            if safe:
                args += ["--developer-sub", ",".join(safe)]

        ios_backups_selected = payload.get("ios_backups_selected", [])
        if ios_backups_selected and isinstance(ios_backups_selected, list):
            _uuid_re = re.compile(r'^[0-9A-Fa-f\-]{1,40}$')
            safe_uuids = [u for u in ios_backups_selected if isinstance(u, str) and _uuid_re.match(u)]
            if safe_uuids:
                args += ["--ios-backups-sub", ",".join(safe_uuids)]

        app_uninstaller_selected = payload.get("app_uninstaller_selected", [])
        if app_uninstaller_selected and isinstance(app_uninstaller_selected, list):
            safe = [x for x in app_uninstaller_selected if isinstance(x, str) and _validate_app_name(x)]
            if safe:
                args += ["--app-uninstaller-sub", ",".join(safe)]

        data, err = self._run_script(args)
        if err:
            self._send_error_json(f"Temizleme hatası: {err}")
        else:
            self._send_json(data)

    def _handle_spotlight_reindex(self):
        data, err = self._run_script(["--spotlight-reindex"], timeout=10)
        if err:
            self._send_error_json(f"Spotlight hatası: {err}")
        else:
            self._send_json(data)

    def _handle_flush_dns(self):
        data, err = self._run_script(["--flush-dns"], timeout=15)
        if err:
            self._send_error_json(f"DNS temizleme hatası: {err}")
        else:
            self._send_json(data)

    def _handle_purge_ram(self):
        data, err = self._run_script(["--purge-ram"], timeout=30)
        if err:
            self._send_error_json(f"RAM temizleme hatası: {err}")
        else:
            self._send_json(data)

    def _handle_launchagents_clean(self):
        data, err = self._run_script(["--launchagents-clean"], timeout=30)
        if err:
            self._send_error_json(f"LaunchAgents temizleme hatası: {err}")
        else:
            self._send_json(data)

    def _handle_thin_snapshots(self):
        data, err = self._run_script(["--thin-snapshots-json"], timeout=120)
        if err:
            self._send_error_json(f"Snapshot inceltme hatası: {err}")
        else:
            self._send_json(data)

    # ── Static File Server ──────────────────────────────────
    def _serve_static(self, path):
        if path == "/" or path == "":
            path = "/index.html"

        file_path = (WEB_DIR / path.lstrip("/")).resolve()

        # Security: prevent directory traversal
        if not str(file_path).startswith(str(WEB_DIR)):
            self._send_error_json("Forbidden", 403)
            return

        if not file_path.is_file():
            self._send_error_json("Not found", 404)
            return

        ext = file_path.suffix.lower()
        content_type = MIME_TYPES.get(ext, "application/octet-stream")

        try:
            data = file_path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-cache")
            self._cors_headers()
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            self._send_error_json(f"File read error: {e}")


def main():
    http.server.HTTPServer.allow_reuse_address = True
    server = http.server.HTTPServer(("0.0.0.0", PORT), CleanupHandler)
    print(f"🍎 Apple Cleanup Dashboard")
    print(f"   http://localhost:{PORT}")
    print(f"   Ctrl+C ile durdurabilirsiniz\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n✋ Sunucu durduruldu.")
        server.server_close()


if __name__ == "__main__":
    main()
