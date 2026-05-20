#!/usr/bin/env python3
"""
Apple Cleanup Web Dashboard — HTTP Server
Serves the web UI and proxies API requests to clean_mac.sh
"""

import http.server
import json
import os
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
        data, err = self._run_script(["--clean-json", cat_str])
        if err:
            self._send_error_json(f"Temizleme hatası: {err}")
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
