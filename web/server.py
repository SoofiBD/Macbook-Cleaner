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

import hmac
import http.server
import json
import os
import plistlib
import re
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import webbrowser
from functools import wraps
from pathlib import Path

# Bind to loopback only — this API can delete files and must never be
# reachable from the local network.
HOST = "127.0.0.1"
PORT = 8080
WEB_DIR = Path(__file__).parent.resolve()


def _get_script_path():
    """Use Homebrew's stable opt path when the launcher provides one."""
    configured = os.environ.get("APPLE_CLEANUP_SCRIPT_PATH")
    if configured:
        return Path(configured).expanduser()
    return (WEB_DIR.parent / "clean_mac.sh").resolve()


SCRIPT_PATH = _get_script_path()

# ── Weekly automatic cleanup (launchd) ───────────────────────────────────────
# A user LaunchAgent that runs the no-sudo safe cleanup once a week. It runs as
# the user with no password prompt, so the agent invokes --clean-safe-json which
# itself filters out any sudo categories (see cat_nosudo_safe_nums in the script).
LAUNCH_AGENT_LABEL = "com.cleanmac.weeklycleanup"
LAUNCH_AGENTS_DIR = Path(os.path.expanduser("~/Library/LaunchAgents"))
LAUNCH_AGENT_PLIST = LAUNCH_AGENTS_DIR / f"{LAUNCH_AGENT_LABEL}.plist"

# Maximum allowed request body size (1 MB)
MAX_BODY_SIZE = 1 * 1024 * 1024  # 1,048,576 bytes

# ── Storage forecast ─────────────────────────────────────────────────────────
# The Bash script is stateless, so disk-usage history lives here. We append a
# snapshot (at most once per hour), keep 90 days, and fit a least-squares line
# to predict when the disk will fill.
HISTORY_FILE = os.path.expanduser("~/.cache/apple-cleanup/usage_history.json")
_history_lock = threading.Lock()
_scan_lock = threading.Lock()
_launch_agent_lock = threading.Lock()
_operation_lock = threading.Lock()
_scan_cache = {"at": 0.0, "data": None}
SCAN_CACHE_SECONDS = 30


def _invalidate_scan_cache():
    with _scan_lock:
        _scan_cache["at"] = 0.0
        _scan_cache["data"] = None
MAX_HISTORY_DAYS = 90
SNAPSHOT_INTERVAL = 3600           # seconds between recorded snapshots
FORECAST_HORIZON_DAYS = 365        # don't report a forecast beyond a year


def _run_process(cmd, *, timeout, cwd=None, env=None):
    """Run argv in its own process group and reap the whole group on timeout."""
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        cwd=cwd,
        env=env,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.communicate(timeout=2)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate()
        raise
    return subprocess.CompletedProcess(cmd, process.returncode, stdout, stderr)


def _exclusive_operation(method):
    """Reject overlapping mutations instead of racing two delete pipelines."""
    @wraps(method)
    def wrapped(self, *args, **kwargs):
        if not _operation_lock.acquire(blocking=False):
            self._send_error_json("Another cleanup operation is already running", 409)
            return None
        try:
            return method(self, *args, **kwargs)
        finally:
            _invalidate_scan_cache()
            _operation_lock.release()
    return wrapped


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
        path = Path(HISTORY_FILE)
        _ensure_private_directory(path.parent)
        _atomic_write(path, lambda f: json.dump(
            [[t, u] for t, u in history], f), binary=False)
    except OSError:
        pass


def _ensure_private_directory(path: Path):
    """Create a user-owned, non-symlink state directory with mode 0700."""
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise OSError(f"unsafe state directory: {path}")
    if hasattr(os, "getuid") and info.st_uid != os.getuid():
        raise OSError(f"state directory is not owned by current user: {path}")
    path.chmod(0o700)


def _atomic_write(path: Path, writer, *, binary: bool):
    """Write a private file in-place using an exclusive same-dir temp file."""
    path = Path(path)
    if path.is_symlink():
        raise OSError(f"refusing symlink destination: {path}")
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        mode = "wb" if binary else "w"
        kwargs = {} if binary else {"encoding": "utf-8"}
        with os.fdopen(fd, mode, **kwargs) as handle:
            writer(handle)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


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
        bracket_end = value.find("]")
        if bracket_end != -1:
            return value[1:bracket_end]
        return value[1:]
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
_BUNDLE_ID_RE    = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]{1,254}$')
_PROJECT_IDENTITY_RE = re.compile(
    r'^\d+:\d+:\d+:\d+:\d+:\d+:'
    r'(?:package\.json|Cargo\.toml|Package\.swift|go\.mod|build\.gradle|'
    r'build\.gradle\.kts|pom\.xml|composer\.json|pubspec\.yaml|'
    r'CMakeLists\.txt|main\.tf)$'
)

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
    "ollama_models",       # Ollama local LLM model blobs (re-pulled on next run)
    "lm_studio",           # LM Studio app cache / downloaded models
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
_UUID_RE = re.compile(r'^[0-9A-Fa-f\-]{1,40}$')


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
    return isinstance(name, str) and bool(_APP_LEFTOVER_RE.fullmatch(name)) \
        and ".." not in name and "/" not in name


def _validate_developer_item(item: str) -> bool:
    """Validate a developer sub-item key against the whitelist."""
    return item in _DEVELOPER_WHITELIST


def _validate_browser_key(key: str) -> bool:
    """Validate a browser key against the whitelist."""
    return key in _BROWSER_WHITELIST


def _validate_app_name(name: str) -> bool:
    """Validate an application name for uninstallation."""
    return isinstance(name, str) and bool(_APP_NAME_RE.fullmatch(name)) \
        and ".." not in name and "/" not in name


def _validate_brew_name(name: str) -> bool:
    """Validate a Homebrew formula/cask token for uninstallation."""
    return isinstance(name, str) and bool(_BREW_NAME_RE.fullmatch(name)) \
        and ".." not in name


def _validate_bundle_id(value: str) -> bool:
    return isinstance(value, str) and bool(_BUNDLE_ID_RE.fullmatch(value)) \
        and ".." not in value


_CATEGORY_IDS = (
    "user_cache", "system_cache", "app_leftovers", "logs", "temp_files",
    "developer", "trash", "browser_cache", "browser_full", "ios_backups",
    "app_uninstaller", "mail_downloads", "diagnostic_reports",
    "quicklook_cache", "saved_app_state", "other_trash", "project_artifacts",
)


def _coerce_categories(value):
    """Return unique stable category ids; accept legacy 1..17 inputs."""
    if not isinstance(value, list) or not value or len(value) > 17:
        return None
    categories = []
    seen = set()
    for raw in value:
        if isinstance(raw, bool):
            return None
        if isinstance(raw, str) and raw in _CATEGORY_IDS:
            category = raw
        elif isinstance(raw, int):
            if not 1 <= raw <= len(_CATEGORY_IDS):
                return None
            category = _CATEGORY_IDS[raw - 1]
        elif isinstance(raw, str) and raw.isdigit():
            number = int(raw)
            if not 1 <= number <= len(_CATEGORY_IDS):
                return None
            category = _CATEGORY_IDS[number - 1]
        else:
            return None
        if category in seen:
            return None
        seen.add(category)
        categories.append(category)
    return categories


# Recognized build/dependency artifact directory names. Kept in sync with
# clean_mac.sh _PROJECT_ARTIFACT_NAMES. The shell re-validates that the parent
# holds a project marker before deleting; this is a lightweight first gate.
_PROJECT_ARTIFACT_NAMES = frozenset({
    "node_modules", "target", ".build", "build",
    "vendor", ".dart_tool", ".terraform",
})

def _is_protected_bundle_id(bundle_id: str) -> bool:
    """Fail closed for Apple-owned bundle identifiers."""
    return isinstance(bundle_id, str) and bundle_id.startswith("com.apple.")


def _application_roots():
    """Return application roots at call time (tests may temporarily set HOME)."""
    return (Path("/Applications"), Path(os.path.expanduser("~/Applications")))


def _is_allowed_app_path(value, require_exists=True) -> bool:
    """Allow only non-symlink .app bundles below a known Applications root."""
    if not isinstance(value, str) or not value or "\x00" in value:
        return False
    path = Path(value)
    if not path.is_absolute() or path.suffix.lower() != ".app":
        return False
    if path.is_symlink():
        return False
    try:
        resolved = path.resolve(strict=require_exists)
    except (OSError, RuntimeError):
        return False
    for root in _application_roots():
        try:
            resolved.relative_to(root.resolve())
            return True
        except (ValueError, OSError):
            continue
    return False


def _iter_application_paths(max_depth=3):
    """Discover real app bundles, including shallow vendor subdirectories."""
    found = []
    for root in _application_roots():
        if not root.is_dir():
            continue
        for dirpath, dirnames, _filenames in os.walk(root, followlinks=False):
            current = Path(dirpath)
            try:
                depth = len(current.relative_to(root).parts)
            except ValueError:
                continue
            if depth >= max_depth:
                dirnames[:] = []
                continue
            keep = []
            for dirname in dirnames:
                candidate = current / dirname
                if candidate.suffix.lower() == ".app":
                    if _is_allowed_app_path(str(candidate)):
                        found.append(str(candidate))
                    # Never descend into an application package: that would
                    # surface its helper apps as independently uninstallable.
                    continue
                if not candidate.is_symlink():
                    keep.append(dirname)
            dirnames[:] = keep
    return sorted(set(found), key=str.casefold)


def _format_bytes(value):
    if value >= 1024 ** 3:
        return f"{value / (1024 ** 3):.1f} GB"
    if value >= 1024 ** 2:
        return f"{value / (1024 ** 2):.1f} MB"
    if value >= 1024:
        return f"{value / 1024:.1f} KB"
    return f"{value} B"


def _normalized_app_name(value):
    return "".join(c.casefold() for c in os.path.splitext(value)[0] if c.isalnum())


def _versionless_app_name(value):
    return _normalized_app_name(re.sub(r"\d+(?:[._-]\d+)*", "", value))


def _cask_match_keys(token):
    """Conservative fallback keys when Homebrew artifact JSON is unavailable."""
    normalized = _normalized_app_name(token)
    keys = {normalized}
    for suffix in ("desktop", "app", "formac", "mac"):
        if normalized.endswith(suffix) and len(normalized) > len(suffix) + 2:
            keys.add(normalized[:-len(suffix)])
    return keys


def _cask_app_artifacts(cask_info):
    """Extract .app artifact basenames from Homebrew's versioned JSON shapes."""
    names = set()
    for artifact in cask_info.get("artifacts", []) if isinstance(cask_info, dict) else []:
        values = []
        if isinstance(artifact, dict) and "app" in artifact:
            raw = artifact["app"]
            values = raw if isinstance(raw, list) else [raw]
        elif isinstance(artifact, list):
            values = artifact
        for value in values:
            if isinstance(value, str) and value.lower().endswith(".app"):
                names.add(os.path.basename(value)[:-4].casefold())
    return names


def discover_applications():
    """Return a fresh, server-authoritative application/cask catalog."""
    app_paths = _iter_application_paths()
    app_sizes = {}
    # Keep argv and command duration bounded on machines with many apps.
    for start in range(0, len(app_paths), 40):
        chunk = app_paths[start:start + 40]
        try:
            res = subprocess.run(
                ["du", "-sk", "--", *chunk], capture_output=True,
                text=True, timeout=20,
            )
            if res.returncode == 0:
                for line in res.stdout.splitlines():
                    parts = line.split("\t", 1)
                    if len(parts) == 2 and parts[0].isdigit():
                        app_sizes[parts[1]] = int(parts[0]) * 1024
        except (OSError, subprocess.SubprocessError):
            pass

    casks = []
    cask_artifacts = {}
    brew = shutil.which("brew")
    if brew:
        try:
            res = subprocess.run(
                [brew, "list", "--cask"], capture_output=True,
                text=True, timeout=15,
            )
            if res.returncode == 0:
                casks = [line.strip() for line in res.stdout.splitlines()
                         if _validate_brew_name(line.strip())]
        except (OSError, subprocess.SubprocessError):
            pass
        if casks:
            try:
                res = subprocess.run(
                    [brew, "info", "--cask", "--json=v2", *casks],
                    capture_output=True, text=True, timeout=30,
                )
                if res.returncode == 0:
                    info = json.loads(res.stdout)
                    for entry in info.get("casks", []):
                        token = entry.get("token") if isinstance(entry, dict) else None
                        if token in casks:
                            for app_name in _cask_app_artifacts(entry):
                                cask_artifacts.setdefault(app_name, token)
            except (OSError, ValueError, subprocess.SubprocessError):
                pass

    cask_candidates = {}
    for cask in casks:
        for key in _cask_match_keys(cask):
            cask_candidates.setdefault(key, []).append(cask)
    processed_casks = set()
    apps = []
    for app_path in app_paths:
        folder_name = Path(app_path).stem
        bundle_id = version = display_name = bundle_name = ""
        try:
            with open(os.path.join(app_path, "Contents", "Info.plist"), "rb") as handle:
                plist = plistlib.load(handle)
            bundle_id = str(plist.get("CFBundleIdentifier", ""))
            version = str(plist.get("CFBundleShortVersionString",
                                    plist.get("CFBundleVersion", "")))
            display_name = str(plist.get("CFBundleDisplayName", ""))
            bundle_name = str(plist.get("CFBundleName", ""))
        except (OSError, ValueError, TypeError, plistlib.InvalidFileException):
            pass

        resolved_name = (display_name or bundle_name or folder_name).removesuffix(".app")
        matched_cask = cask_artifacts.get(folder_name.casefold())
        if not matched_cask:
            candidates = set()
            for key in {_normalized_app_name(folder_name),
                        _versionless_app_name(folder_name)}:
                candidates.update(cask_candidates.get(key, []))
            if len(candidates) == 1:
                matched_cask = candidates.pop()
        if matched_cask:
            processed_casks.add(matched_cask)
        source = "both" if matched_cask else "app_dir"
        size = app_sizes.get(app_path, 0)
        apps.append({
            "target_id": f"app:{app_path}",
            "id": matched_cask or folder_name,
            "name": resolved_name,
            "folder_name": folder_name,
            "path": app_path,
            "size_bytes": size,
            "size_human": _format_bytes(size),
            "source": source,
            "bundle_id": bundle_id,
            "version": version,
            "protected": _is_protected_bundle_id(bundle_id),
        })

    caskroom = Path("/opt/homebrew/Caskroom")
    if not caskroom.exists():
        caskroom = Path("/usr/local/Caskroom")
    for cask in sorted(set(casks) - processed_casks, key=str.casefold):
        cpath = caskroom / cask
        size = 0
        version = ""
        try:
            subdirs = [p for p in cpath.iterdir() if p.is_dir()]
            if subdirs:
                version = subdirs[0].name
            res = subprocess.run(
                ["du", "-sk", "--", str(cpath)], capture_output=True,
                text=True, timeout=10,
            )
            if res.returncode == 0:
                size = int(res.stdout.split()[0]) * 1024
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
        apps.append({
            "target_id": f"cask:{cask}",
            "id": cask,
            "name": " ".join(w.capitalize() for w in re.split("[-_]", cask)),
            "folder_name": "",
            "path": str(cpath),
            "size_bytes": size,
            "size_human": _format_bytes(size),
            "source": "brew_cask",
            "bundle_id": "",
            "version": version,
            "protected": False,
        })
    return sorted(apps, key=lambda item: (item["name"].casefold(), item["target_id"]))


def _validate_project_artifact(path: str) -> bool:
    """Validate a project-artifact path before passing it to the script.

    This is a path-shape check only (home-agnostic, so it is unit-testable with
    arbitrary paths). The runtime $HOME confinement and symlink-target guard are
    enforced by bash _is_valid_project_artifact, which resolves against the real
    home and follows the path before any deletion.
    """
    return (
        isinstance(path, str)
        and path.startswith("/")
        and ".." not in path
        and "," not in path
        and os.path.basename(path.rstrip("/")) in _PROJECT_ARTIFACT_NAMES
    )


def _validate_project_artifact_selection(value) -> bool:
    """Validate the path plus scan-time filesystem identity transport shape."""
    return (
        isinstance(value, dict)
        and set(value) == {"path", "identity"}
        and _validate_project_artifact(value.get("path"))
        and isinstance(value.get("identity"), str)
        and _PROJECT_IDENTITY_RE.fullmatch(value["identity"]) is not None
    )


def _normalize_bool_fields(data: dict) -> dict:
    """
    Recursively normalize boolean string fields in scan JSON.
    Converts string "true"/"false" to Python bool True/False.
    Also ensures needs_sudo is always a proper bool.

    NOTE: Mutates `data` in-place. Pass a copy if the original must be preserved.
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

    def setup(self):
        super().setup()
        self.connection.settimeout(30)

    # ── Security headers ────────────────────────────────────
    def _security_headers(self):
        # No wildcard CORS: the dashboard is served same-origin, so cross-origin
        # reads must stay blocked. These headers harden the responses further.
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'"
        )

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
        # Surface the failure on the server console/log too — handlers swallow
        # errors into JSON, so without this an API failure leaves no trace.
        sys.stderr.write(f"[ERROR {status}] {self.path}: {message}\n")
        sys.stderr.flush()
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
        """Run clean_mac.sh with given arguments and return parsed JSON.

        The script may exit non-zero while still emitting valid JSON on
        stdout (e.g. a partially-failed cleanup that still reports its
        results).  We therefore always try to parse stdout first and
        only fall back to the exit-code / stderr error when stdout is
        empty or not valid JSON.
        """
        cmd = ["bash", str(SCRIPT_PATH)] + args
        run_env = dict(os.environ)
        # Never inherit test-only permanent-delete controls into dashboard
        # cleanup processes. The web API intentionally exposes no equivalent.
        run_env.pop("APPLE_CLEANUP_FORCE_RM", None)
        run_env.pop("APPLE_CLEANUP_TEST_MODE", None)
        if env_extra:
            run_env.update(env_extra)
        # The dashboard is English-only. Do not let the parent shell's locale
        # or APPLE_CLEANUP_LANG setting produce mixed-language API messages.
        run_env["APPLE_CLEANUP_LANG"] = "en"
        try:
            result = _run_process(
                cmd,
                timeout=timeout,
                cwd=str(SCRIPT_PATH.parent),
                env=run_env,
            )
            output = result.stdout.strip()
            if not output:
                err_msg = result.stderr.strip() or f"Script execution failed with exit code {result.returncode}"
                if not result.stderr.strip():
                    sys.stderr.write(f"[ERROR] {cmd} exited {result.returncode} with no output\n")
                return None, err_msg

            try:
                parsed = json.loads(output)
            except json.JSONDecodeError as e:
                # stdout contained something but it wasn't valid JSON.
                if result.returncode != 0:
                    err_msg = result.stderr.strip() or f"Script failed (exit {result.returncode})"
                    return None, err_msg
                return None, f"Invalid JSON from script: {e}"

            # Normalize boolean fields (Bash outputs JSON bool literals,
            # but this ensures consistency even if format changes)
            if isinstance(parsed, dict):
                _normalize_bool_fields(parsed)

            return parsed, None
        except subprocess.TimeoutExpired:
            return None, "Script timed out"
        except Exception as e:
            sys.stderr.write(f"[ERROR] _run_script: {e}\n")
            return None, "Internal script error"

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
        elif path == "/api/schedule-status":
            self._handle_schedule_status()
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
        elif parsed.path == "/api/schedule-weekly":
            self._handle_schedule_weekly()
        else:
            self._send_error_json("Not found", 404)

    # ── API Handlers ────────────────────────────────────────
    def _handle_scan(self):
        # Scanning walks many large cache/log trees with `du`; on fuller or
        # slower machines this easily exceeds the default 120s. Give it room
        # so a legitimately slow scan doesn't surface as a server error.
        with _scan_lock:
            now = time.monotonic()
            if (_scan_cache["data"] is not None
                    and now - _scan_cache["at"] < SCAN_CACHE_SECONDS):
                self._send_json(_scan_cache["data"])
                return
            data, err = self._run_script(["--scan-json"], timeout=600)
            if not err:
                _scan_cache["data"] = data
                _scan_cache["at"] = time.monotonic()
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

    @_exclusive_operation
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
        with _history_lock:
            history = _record_snapshot(_load_history(), usage.used)
            _save_history(history)
        data = compute_forecast(history, usage.total, usage.used)
        data["success"] = True
        data["total_bytes"] = usage.total
        data["used_bytes"] = usage.used
        data["free_bytes"] = usage.free
        self._send_json(data)

    @_exclusive_operation
    def _handle_clean(self):
        payload, err = self._read_json_body()
        if err:
            self._send_error_json(err, 400)
            return

        safe_cats = _coerce_categories(payload.get("categories"))
        if safe_cats is None:
            self._send_error_json(
                "categories must contain unique stable category ids", 400
            )
            return

        cat_str = ",".join(safe_cats)
        args = ["--clean-ids-json", cat_str]

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
            safe_uuids = [u for u in ios_backups_selected
                         if isinstance(u, str) and _UUID_RE.match(u)]
            if safe_uuids:
                args += ["--ios-backups-sub", ",".join(safe_uuids)]

        # App uninstaller sub-items
        app_uninstaller_selected = payload.get("app_uninstaller_selected", [])
        if app_uninstaller_selected and isinstance(app_uninstaller_selected, list):
            safe = [x for x in app_uninstaller_selected
                    if isinstance(x, str) and _validate_app_name(x)]
            if safe:
                args += ["--app-uninstaller-sub", ",".join(safe)]

        # Project artifact sub-items. The shell revalidates the scan-time
        # device/inode tuple immediately before moving the target to Trash.
        project_artifacts_selected = payload.get("project_artifacts_selected", [])
        if project_artifacts_selected and isinstance(project_artifacts_selected, list):
            selected = [x for x in project_artifacts_selected
                        if _validate_project_artifact_selection(x)]
            safe = [x["path"] for x in selected]
            identities = [x["identity"] for x in selected]
            if safe:
                args += ["--project-artifact-sub", ",".join(safe)]
                args += ["--project-artifact-identities", ",".join(identities)]

        data, err = self._run_script(args, env_extra=_extra_env_for_clean(payload))
        if err:
            self._send_error_json(f"Clean error: {err}")
        else:
            self._send_json(data)

    @_exclusive_operation
    def _handle_spotlight_reindex(self):
        data, err = self._run_script(["--spotlight-reindex"], timeout=45)
        if err:
            self._send_error_json(f"Spotlight Indexing Failure: {err}")
        else:
            self._send_json(data)

    @_exclusive_operation
    def _handle_flush_dns(self):
        data, err = self._run_script(["--flush-dns"], timeout=15)
        if err:
            self._send_error_json(f"DNS flush error: {err}")
        else:
            self._send_json(data)

    @_exclusive_operation
    def _handle_purge_ram(self):
        data, err = self._run_script(["--purge-ram"], timeout=30)
        if err:
            self._send_error_json(f"RAM purge error: {err}")
        else:
            self._send_json(data)

    @_exclusive_operation
    def _handle_launchagents_clean(self):
        data, err = self._run_script(["--launchagents-clean"], timeout=30)
        if err:
            self._send_error_json(f"LaunchAgents clean error: {err}")
        else:
            self._send_json(data)

    @_exclusive_operation
    def _handle_thin_snapshots(self):
        data, err = self._run_script(["--thin-snapshots-json"], timeout=120)
        if err:
            self._send_error_json(f"Snapshot thinning error: {err}")
        else:
            self._send_json(data)

    # ── Weekly automatic cleanup (launchd) ──────────────────
    def _handle_schedule_status(self):
        """Report whether the weekly cleanup LaunchAgent is installed."""
        self._send_json({
            "enabled": LAUNCH_AGENT_PLIST.exists(),
            "label": LAUNCH_AGENT_LABEL,
            "plist_path": str(LAUNCH_AGENT_PLIST),
        })

    @_exclusive_operation
    def _handle_schedule_weekly(self):
        """Enable/disable the weekly cleanup by writing/removing a LaunchAgent."""
        payload, err = self._read_json_body()
        if err:
            self._send_error_json(err, 400)
            return
        enable = payload.get("enabled")
        if not isinstance(enable, bool):
            self._send_error_json("enabled must be a boolean", 400)
            return
        try:
            with _launch_agent_lock:
                if enable:
                    self._install_weekly_agent()
                    self._send_json({"enabled": True, "plist_path": str(LAUNCH_AGENT_PLIST)})
                else:
                    self._remove_weekly_agent()
                    self._send_json({"enabled": False})
        except Exception as e:
            sys.stderr.write(f"[ERROR] schedule-weekly: {e}\n")
            self._send_error_json("Schedule update failed")

    def _install_weekly_agent(self):
        """Write the .plist and (best-effort) load it into launchd."""
        _ensure_private_directory(LAUNCH_AGENTS_DIR)
        plist = {
            "Label": LAUNCH_AGENT_LABEL,
            # Runs the script's own no-sudo safe cleanup; the script decides
            # which categories are safe to clean unattended.
            "ProgramArguments": ["/bin/bash", str(SCRIPT_PATH), "--clean-safe-json"],
            # Sunday 03:00 weekly.
            "StartCalendarInterval": {"Weekday": 0, "Hour": 3, "Minute": 0},
            "RunAtLoad": False,
            "ProcessType": "Background",
            "StandardOutPath": os.path.expanduser(
                "~/.cache/apple-cleanup/weekly-cleanup.log"),
            "StandardErrorPath": os.path.expanduser(
                "~/.cache/apple-cleanup/weekly-cleanup.log"),
        }
        _ensure_private_directory(Path(os.path.expanduser("~/.cache/apple-cleanup")))
        _atomic_write(
            LAUNCH_AGENT_PLIST,
            lambda handle: plistlib.dump(plist, handle),
            binary=True,
        )
        # Reload so changes take effect now; ignore failures (e.g. headless).
        subprocess.run(["launchctl", "unload", str(LAUNCH_AGENT_PLIST)],
                       capture_output=True, timeout=15)
        subprocess.run(["launchctl", "load", str(LAUNCH_AGENT_PLIST)],
                       capture_output=True, timeout=15)

    def _remove_weekly_agent(self):
        """Unload and delete the LaunchAgent plist if present."""
        if LAUNCH_AGENT_PLIST.exists():
            subprocess.run(["launchctl", "unload", str(LAUNCH_AGENT_PLIST)],
                           capture_output=True, timeout=15)
            LAUNCH_AGENT_PLIST.unlink()

    def _run_cmd(self, cmd, timeout=60):
        try:
            res = _run_process(cmd, timeout=timeout)
            return res.returncode == 0, res.stdout, res.stderr
        except subprocess.TimeoutExpired:
            return False, "", "Command timed out"
        except Exception as e:
            return False, "", str(e)

    def _handle_apps(self):
        try:
            self._send_json({"success": True, "apps": discover_applications()})
        except Exception as e:
            sys.stderr.write(f"[ERROR] _handle_apps: {e}\n")
            self._send_error_json("Failed to list applications", 500)

    @_exclusive_operation
    def _handle_uninstall(self):
        payload, err = self._read_json_body()
        if err:
            self._send_error_json(err, 400)
            return

        target_id = payload.get("target_id")
        if not isinstance(target_id, str) or not target_id:
            self._send_error_json("target_id is required", 400)
            return

        # Never trust the browser's cached name/source/path.  Rediscover the
        # catalog immediately before deleting and resolve one exact target.
        try:
            matches = [item for item in discover_applications()
                       if item["target_id"] == target_id]
        except Exception as exc:
            sys.stderr.write(f"[ERROR] uninstall rediscovery: {exc}\n")
            self._send_error_json("Could not verify the application target", 500)
            return
        if len(matches) != 1:
            self._send_error_json(
                "Application changed since the scan; refresh the list and try again",
                409,
            )
            return
        target = matches[0]
        if target.get("protected"):
            self._send_error_json("This macOS application is protected", 403)
            return

        source = target["source"]
        app_id = target["id"]
        app_path = target["path"] if source in ("app_dir", "both") else ""
        bundle_id = target.get("bundle_id", "")
        if app_path and not _is_allowed_app_path(app_path):
            self._send_error_json("Application path failed safety validation", 409)
            return
        if source in ("brew_cask", "both") and not _validate_brew_name(app_id):
            self._send_error_json("Homebrew package failed safety validation", 409)
            return

        details = []

        # Homebrew MUST run first. `brew uninstall --cask` expects the .app
        # bundle to still exist; if clean_mac.sh deletes it first, the cask
        # uninstall fails. So: brew first, then residual-file cleanup.
        if source in ("brew_cask", "both"):
            brew = shutil.which("brew")
            if not brew:
                self._send_error_json("Homebrew is no longer available", 409)
                return
            # Homebrew's cask metadata knows app-specific support files that a
            # generic bundle-id matcher cannot.  `--zap` is appropriate here
            # because the UI explicitly confirms removal of associated data.
            cmd = [brew, "uninstall", "--cask", "--zap", "--", app_id]
            ok, out, err_out = self._run_cmd(cmd, timeout=180)
            if not ok:
                reason = (err_out or out or "unknown Homebrew error").strip()
                self._send_error_json(f"Homebrew cask uninstallation failed: {reason}")
                return
            details.append("Homebrew cask uninstalled successfully.")

        # Then run clean_mac.sh to remove any remaining .app bundle and clean
        # exact-name/bundle-id leftovers.  The explicit path avoids comma/name
        # parsing and remains valid as identity even if brew just removed it.
        if app_path:
            args = ["--clean-json", "11", "--app-uninstaller-path", app_path]
            if _validate_bundle_id(bundle_id):
                args += ["--app-uninstaller-bundle-id", bundle_id]
            data, script_err = self._run_script(args, timeout=180)
            if script_err:
                self._send_error_json(f"Application cleanup failed: {script_err}")
                return
            if not isinstance(data, dict) or data.get("success") is not True:
                errors = data.get("errors", []) if isinstance(data, dict) else []
                messages = [entry.get("message", "") for entry in errors
                            if isinstance(entry, dict) and entry.get("message")]
                reason = "; ".join(messages) or "one or more files could not be removed"
                self._send_error_json(f"Application cleanup failed: {reason}")
                return
            if os.path.lexists(app_path):
                self._send_error_json(
                    "The application bundle is still present (permission denied or app in use)"
                )
                return
            details.append("Application and exact associated files moved to Trash.")

        self._send_json({
            "success": True,
            "message": "Uninstalled successfully.",
            "details": " ".join(details),
        })

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
            self.send_header("Cache-Control", "no-store, must-revalidate")
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


def _bind_server():
    """Bind the dashboard server, falling back to the next port if 8080 is
    already taken by another app. The frontend uses relative URLs, so it works
    on whatever port the page was actually served from. Returns the bound
    server and updates the global PORT to match."""
    global PORT
    # ThreadingHTTPServer keeps the dashboard responsive while a long scan or
    # cleanup runs; a plain single-threaded HTTPServer freezes for the whole
    # operation and looks like the server has died.
    http.server.ThreadingHTTPServer.allow_reuse_address = True
    last_err = None
    for candidate in range(PORT, PORT + 10):
        try:
            server = http.server.ThreadingHTTPServer((HOST, candidate), CleanupHandler)
            PORT = candidate
            return server
        except OSError as e:
            last_err = e
            continue
    raise SystemExit(
        f"ERROR: could not start the server — ports {PORT}-{PORT + 9} are all "
        f"in use ({last_err}). Quit the app using one of those ports and try again."
    )


def main():
    server = _bind_server()
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
