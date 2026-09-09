"""Read-only, bounded home-directory inventory; never trusts an index or cache."""
import hashlib
import os
from pathlib import Path
import stat
import time
from collections import defaultdict

LARGE_BYTES = 100 * 1024 * 1024
MAX_ENTRIES = 100_000
MAX_HASH_BYTES = 2 * 1024 ** 3
MAX_RESULTS = 200
SKIP_DIRS = {"Library", "node_modules", "vendor", "__pycache__"}
BUNDLE_SUFFIXES = (".app", ".photoslibrary", ".photolibrary", ".bundle")


def _identity(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns,
            info.st_ctime_ns)


def _current(path, identity):
    try:
        info = os.lstat(path)
        return stat.S_ISREG(info.st_mode) and _identity(info) == identity
    except OSError:
        return False


def _digest(path, identity, deadline, budget):
    # Do not follow a file replaced by a symlink, or block on a replaced FIFO.
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode) or _identity(info) != identity:
            raise OSError("File changed before hashing")
        digest = hashlib.sha256()
        remaining = identity[2]
        while remaining:
            if time.monotonic() >= deadline:
                raise TimeoutError("Scan time limit reached")
            if budget[0] <= 0:
                raise TimeoutError("Content read limit reached")
            block = handle.read(min(1024 * 1024, budget[0], remaining))
            if not block:
                raise OSError("File truncated while hashing")
            remaining -= len(block)
            budget[0] -= len(block)
            digest.update(block)
        if _identity(os.fstat(handle.fileno())) != identity or not _current(path, identity):
            raise OSError("File changed while hashing")
        return digest.hexdigest()


def scan_files(kind, home=None, *, timeout=20, max_entries=MAX_ENTRIES,
               max_hash_bytes=MAX_HASH_BYTES, large_bytes=LARGE_BYTES):
    """Scan visible personal files, excluding app data, bundles and symlinks.

    Results are re-statted before returning. Hashing is size-prefiltered and
    hard links are counted once. Limits and unreadable/changed files are explicit.
    """
    if kind not in {"large", "duplicates"}:
        raise ValueError("Unknown file scan kind")
    root = Path(home) if home is not None else Path.home()
    deadline = time.monotonic() + timeout
    candidates = []
    seen = set()
    errors = 0
    visited = 0
    reason = None

    def walk_error(_error):
        nonlocal errors
        errors += 1

    for directory, dirs, files in os.walk(root, followlinks=False, onerror=walk_error):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.')
                         and d not in SKIP_DIRS and not d.lower().endswith(BUNDLE_SUFFIXES)
                         and not os.path.islink(os.path.join(directory, d)))
        visited += 1
        for name in sorted(files):
            visited += 1
            if visited > max_entries or time.monotonic() >= deadline:
                reason = "Scan time or entry limit reached"
                break
            if name.startswith('.') or name.endswith('.icloud'):
                continue
            path = os.path.join(directory, name)
            try:
                info = os.lstat(path)
                if not stat.S_ISREG(info.st_mode) or info.st_size == 0:
                    continue
                # macOS dataless iCloud placeholders must not trigger downloads.
                if getattr(info, "st_flags", 0) & 0x40000000:
                    continue
                inode = (info.st_dev, info.st_ino)
                if inode in seen:
                    continue
                seen.add(inode)
                if kind == "duplicates" or info.st_size >= large_bytes:
                    candidates.append((path, _identity(info)))
            except OSError:
                errors += 1
        if reason or visited > max_entries or time.monotonic() >= deadline:
            reason = reason or "Scan time or entry limit reached"
            break

    def record(item):
        path, identity = item
        return {"path": path, "name": os.path.basename(path), "size_bytes": identity[2]}

    groups = []
    if kind == "duplicates":
        by_size = defaultdict(list)
        for item in candidates:
            by_size[item[1][2]].append(item)
        budget = [max_hash_bytes]
        for size in sorted(by_size):
            items = by_size[size]
            if len(items) < 2:
                continue
            by_hash = defaultdict(list)
            for item in items:
                if size > budget[0]:
                    reason = reason or "Content read limit reached"
                    continue
                try:
                    digest = _digest(*item, deadline, budget)
                    by_hash[digest].append(item)
                except TimeoutError as exc:
                    reason = str(exc)
                    break
                except OSError:
                    errors += 1
            groups.extend((digest, matches) for digest, matches in by_hash.items()
                          if len(matches) > 1)
            if time.monotonic() >= deadline or budget[0] <= 0:
                reason = reason or "Scan time or content read limit reached"
                break

    # Discard files removed or changed since enumeration/hash verification.
    current = []
    for item in candidates:
        if _current(*item):
            current.append(item)
        else:
            errors += 1
    live = {path for path, _ in current}
    results = []
    if kind == "large":
        results = [record(item) for item in sorted(current, key=lambda x: (-x[1][2], x[0]))]
    else:
        for digest, items in groups:
            files = [record(item) for item in items if item[0] in live]
            if len(files) > 1:
                results.append({"sha256": digest, "files": files,
                                "duplicate_bytes": files[0]["size_bytes"] * (len(files) - 1)})
        results.sort(key=lambda group: -group["duplicate_bytes"])
    return {"success": True, "kind": kind, "results": results[:MAX_RESULTS],
            "partial": bool(reason or errors), "limit_reason": reason,
            "skipped_errors": errors, "truncated": len(results) > MAX_RESULTS,
            "result_count": len(results), "scanned_files": len(seen),
            "root": str(root), "large_min_bytes": large_bytes,
            "scope": "Visible personal files; excludes hidden folders, Library, app/photo bundles, dependency folders, symlinks and cloud placeholders."}
