# Operation Log + History — Design

**Date:** 2026-06-19
**Status:** Approved (design)
**Phase:** 1 of 3 (Safety foundation) in the Mole-inspired improvement roadmap

## Background

`apple-cleanup` is a macOS cleanup tool (one `clean_mac.sh`, ~2,886 lines, Bash
3.2 compatible) with a Python web dashboard. After comparing it against the
mature [Mole](https://github.com/tw93/mole) project, most of Mole's safety
patterns already exist here:

- Trash-first deletion (`_trash_item`), with direct `rm` only for sudo paths,
  trash-emptying, and CI mode (`safe_rm`, `safe_rm_contents`, `_should_force_rm`).
- Path protection (`/System`, `/usr`, etc.) and a user exclusion list
  (`APPLE_CLEANUP_EXCLUDE`).
- Dry-run preview (`APPLE_CLEANUP_DRYRUN` / `DRYRUN`).

The one safety capability Mole has and we lack is an **operation log** with a
**history view** — an audit trail of what was removed, when, and how big it was.
This pairs naturally with the existing trash-first behavior: the log can tell
users an item is recoverable from Trash.

## Goals

1. Record every real deletion/trash operation to an append-only log.
2. Let users review that history from the CLI and the web dashboard.

## Non-Goals (YAGNI)

- **No custom "undo from history"** — macOS Trash already provides recovery via
  Finder; a custom undo would duplicate the OS for little gain.
- **No centralized app-protection allowlist** — deferred to Phase 3
  (architecture), since it is a refactor of existing scattered `case` patterns
  rather than a new safety capability.

## Architecture

Two small, independent units with a well-defined interface (the log file
format). The writer knows nothing about the reader; both only share the file
contract below.

### Component 1 — Operation log (writer)

- New helper `oplog_record <action> <bytes> <path> <category>`.
- Called from inside `safe_rm` and `safe_rm_contents`, only on the success
  branch of a real (non-dry-run) operation. One call per logged item.
- Appends to `~/.cache/apple-cleanup/operations.log` (the cache dir already used
  by the storage forecast). Creates the dir/file if missing.
- **Line format** (tab-separated, one operation per line):
  `<epoch_seconds>\t<action>\t<bytes>\t<path>\t<category>`
  - `action` ∈ {`trash`, `delete`} — `trash` means recoverable; `delete` means
    permanent (sudo paths, trash-emptying, CI).
  - `bytes` is the size already computed by the caller (`sz_b`).
  - `path` is the absolute path operated on. Tabs/newlines in paths are
    sanitized to spaces before writing so each record stays single-line.
- **Dry-run:** records nothing (writer is only reached on the real success
  branch).
- **Opt-out:** `APPLE_CLEANUP_NO_OPLOG=1` disables all recording.
- **Rotation:** before appending, if the log exceeds a cap
  (`APPLE_CLEANUP_OPLOG_MAX_BYTES`, default ~5 MB), truncate to the most recent
  half so it cannot grow unbounded. Bash 3.2 compatible (no external deps
  beyond standard `wc`, `tail`, `mv`).

### Component 2 — History view (reader)

- **`--history`**: prints a human-readable table to stdout — most recent first,
  showing relative time, action (recoverable/permanent), human size, category,
  and path. Honors `--lang` like the rest of the tool.
- **`--history-json`**: emits a JSON array of `{ts, action, bytes, size_human,
  path, category, recoverable}` objects, newest first, for the dashboard. Built
  with the existing `json_escape_str` helper (no `jq` dependency), matching the
  pattern of the other `--*-json` flags.
- Both read the same log file; if it is missing or empty, they return an empty
  result (empty table / `[]`) without error.
- Both flags registered in the CLI arg parser alongside the existing
  `--scan-json` / `--status-json` flags.

### Component 3 — Dashboard History tab

- A new **History** tab in `web/index.html`, styled like the existing tabs.
- Frontend (`web/script.js`) fetches via a server endpoint that shells out to
  `clean_mac.sh --history-json`, reusing the existing loopback + session-token
  protected request path (read-only; no new write surface).
- Renders the operations as a list/table: time, action badge
  (recoverable vs permanent), size, category, path. Empty state when no history.
- `web/server.py` gains one read-only route (e.g. `GET /api/history`) following
  the existing JSON-endpoint pattern.

## Data Flow

```
safe_rm / safe_rm_contents (real success)
        │ oplog_record(action, bytes, path, category)
        ▼
~/.cache/apple-cleanup/operations.log   (append; rotate if oversized)
        ▲
        │ read
   ┌────┴─────────────┐
   │                  │
--history         --history-json ──► server.py /api/history ──► dashboard History tab
(human table)     (JSON array)
```

## Error Handling

- Log directory/file creation failure: silently skip recording (never block or
  fail a cleanup because logging failed).
- Reader on missing/empty/corrupt log: treat malformed lines as skipped; output
  empty result rather than erroring.
- Paths containing tabs/newlines: sanitized to spaces at write time so the
  record format stays single-line and parseable.

## Testing

- **Shell-level:** a dry-run produces no new log lines; a real trash op produces
  exactly one well-formed line; `APPLE_CLEANUP_NO_OPLOG=1` suppresses recording;
  rotation truncates when over the cap.
- **Python (`tests/`):** `--history-json` returns valid JSON with expected
  fields; `/api/history` route returns the parsed history and is gated by the
  session token like other endpoints.
- Follows the existing `tests/` layout (`test_clean_mac.py`,
  `test_server_validation.py`).

## File Contract Summary

- **Path:** `~/.cache/apple-cleanup/operations.log`
- **Encoding:** UTF-8, LF line endings
- **Record:** `epoch\taction\tbytes\tpath\tcategory`
- **Order:** append (chronological); readers reverse for newest-first display
