# Operation Log + History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an append-only operation log to every real deletion and surface it through a CLI history view and a dashboard History tab.

**Architecture:** A shell writer (`oplog_record`) is called from the success branch of `safe_rm`/`safe_rm_contents` and appends tab-separated records to `~/.cache/apple-cleanup/operations.log`. Two CLI flags (`--history`, `--history-json`) read that file. The Python server exposes a read-only `/api/history` route that shells out to `--history-json`, and the dashboard renders it in a new History tab.

**Tech Stack:** Bash 3.2 (clean_mac.sh), Python 3 stdlib (web/server.py), vanilla JS (web/script.js), pytest (tests/).

## Global Constraints

- Bash 3.2 compatible — no `mapfile`, no `declare -A` reliance beyond existing usage, guard empty-array expansion.
- No new runtime dependencies — use existing helpers (`format_bytes`, `json_escape_str`) and standard tools (`wc`, `tail`, `mv`, `date`, `awk`).
- Log file path: `~/.cache/apple-cleanup/operations.log` (same cache dir as the forecast).
- Record format (one line, tab-separated): `epoch\taction\tbytes\tpath\tcategory` where `action` ∈ {`trash`, `delete`}.
- Dry-run records nothing. `APPLE_CLEANUP_NO_OPLOG=1` disables recording. Rotation cap via `APPLE_CLEANUP_OPLOG_MAX_BYTES` (default 5242880).
- New server route is read-only (GET), behind the existing loopback + host check; no new write surface.
- No em dashes in user-facing copy.

---

### Task 1: `oplog_record` writer + rotation

**Files:**
- Modify: `clean_mac.sh` (add helper after `json_escape_str`, ends line 532)
- Test: `tests/test_oplog.py` (create)

**Interfaces:**
- Consumes: `format_bytes` (line 517), `$HOME`.
- Produces:
  - `OPLOG_FILE` — global, set to `$HOME/.cache/apple-cleanup/operations.log`.
  - `oplog_record <action> <bytes> <path> <category>` — appends one sanitized record; no-op under dry-run/opt-out; rotates when oversized. Returns 0 always (never blocks cleanup).

- [ ] **Step 1: Write the failing test**

Create `tests/test_oplog.py`:

```python
import os
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "clean_mac.sh"


def _run_record(home: Path, *args, env_extra=None) -> None:
    """Source clean_mac.sh and call oplog_record directly with isolated HOME."""
    env = dict(os.environ, HOME=str(home))
    if env_extra:
        env.update(env_extra)
    quoted = " ".join(f"'{a}'" for a in args)
    cmd = f'source "{SCRIPT}" >/dev/null 2>&1; oplog_record {quoted}'
    out = subprocess.run(["bash", "-c", cmd], env=env, capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr


def _log_path(home: Path) -> Path:
    return home / ".cache" / "apple-cleanup" / "operations.log"


def test_record_appends_one_line(tmp_path):
    _run_record(tmp_path, "trash", "2048", "/tmp/foo cache", "user_cache")
    lines = _log_path(tmp_path).read_text().splitlines()
    assert len(lines) == 1
    ts, action, size, path, cat = lines[0].split("\t")
    assert action == "trash"
    assert size == "2048"
    assert path == "/tmp/foo cache"
    assert cat == "user_cache"
    assert ts.isdigit()


def test_record_sanitizes_tabs_and_newlines(tmp_path):
    _run_record(tmp_path, "delete", "10", "/tmp/a\tb\nc", "logs")
    lines = _log_path(tmp_path).read_text().splitlines()
    assert len(lines) == 1
    assert lines[0].split("\t")[3] == "/tmp/a b c"


def test_opt_out_writes_nothing(tmp_path):
    _run_record(tmp_path, "trash", "1", "/tmp/x", "logs",
                env_extra={"APPLE_CLEANUP_NO_OPLOG": "1"})
    assert not _log_path(tmp_path).exists()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/test_oplog.py -v`
Expected: FAIL (`oplog_record: command not found` / non-zero return).

- [ ] **Step 3: Write minimal implementation**

In `clean_mac.sh`, immediately after the `json_escape_str` function (after line 532), add:

```bash
# ─── Operation Log ───────────────────────────────────────────────────────────
# Append-only audit trail of real deletions. Paired with trash-first deletion so
# users can see what was removed and whether it is recoverable from Trash.
OPLOG_FILE="$HOME/.cache/apple-cleanup/operations.log"
OPLOG_MAX_BYTES="${APPLE_CLEANUP_OPLOG_MAX_BYTES:-5242880}"

# oplog_record <action> <bytes> <path> <category>
# action: trash (recoverable) | delete (permanent). Never fails the caller.
oplog_record() {
  [ "${APPLE_CLEANUP_NO_OPLOG:-0}" = "1" ] && return 0
  [ "$DRYRUN" = "1" ] && return 0
  local action="$1" bytes="$2" path="$3" category="${4:-}"
  # Keep each record single-line: collapse tabs/newlines in the path to spaces.
  path="${path//$'\t'/ }"
  path="${path//$'\n'/ }"
  local dir; dir="$(dirname "$OPLOG_FILE")"
  mkdir -p "$dir" 2>/dev/null || return 0
  # Rotate: if the log is over the cap, keep the most recent half.
  if [ -f "$OPLOG_FILE" ]; then
    local sz; sz=$(wc -c <"$OPLOG_FILE" 2>/dev/null | tr -d ' ')
    if [ -n "$sz" ] && [ "$sz" -gt "$OPLOG_MAX_BYTES" ] 2>/dev/null; then
      local lines half
      lines=$(wc -l <"$OPLOG_FILE" 2>/dev/null | tr -d ' ')
      half=$(( lines / 2 ))
      [ "$half" -lt 1 ] && half=1
      tail -n "$half" "$OPLOG_FILE" >"$OPLOG_FILE.tmp" 2>/dev/null \
        && mv "$OPLOG_FILE.tmp" "$OPLOG_FILE" 2>/dev/null
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$action" "$bytes" "$path" "$category" \
    >>"$OPLOG_FILE" 2>/dev/null || true
  return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/test_oplog.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add clean_mac.sh tests/test_oplog.py
git commit -m "feat: add oplog_record operation-log writer with rotation"
```

---

### Task 2: Wire `oplog_record` into deletion + category context

**Files:**
- Modify: `clean_mac.sh` — `safe_rm` (success branches ~lines 650, 657, 664), `safe_rm_contents` (success branches ~lines 706, 713, 725), `run_clean` (line 1813)
- Test: `tests/test_oplog.py` (extend)

**Interfaces:**
- Consumes: `oplog_record` (Task 1), `_CURRENT_CATEGORY` (new global).
- Produces: `_CURRENT_CATEGORY` — global category key set per-category during `run_clean`; defaults to empty.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_oplog.py`:

```python
def test_real_trash_op_records_one_line(tmp_path):
    # Isolated HOME so the manual-mv trash fallback lands in tmp_path/.Trash.
    (tmp_path / ".Trash").mkdir()
    victim = tmp_path / "Library" / "Caches" / "com.example.app"
    victim.mkdir(parents=True)
    (victim / "blob.bin").write_bytes(b"x" * 4096)
    env = dict(os.environ, HOME=str(tmp_path))
    cmd = (f'source "{SCRIPT}" >/dev/null 2>&1; '
           f'safe_rm "{victim}" "Example" >/dev/null 2>&1; true')
    out = subprocess.run(["bash", "-c", cmd], env=env, capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    lines = _log_path(tmp_path).read_text().splitlines()
    assert len(lines) == 1
    assert lines[0].split("\t")[1] in ("trash", "delete")


def test_dry_run_records_nothing(tmp_path):
    victim = tmp_path / "Library" / "Caches" / "com.example.app"
    victim.mkdir(parents=True)
    (victim / "blob.bin").write_bytes(b"x" * 4096)
    env = dict(os.environ, HOME=str(tmp_path), APPLE_CLEANUP_DRYRUN="1")
    cmd = (f'source "{SCRIPT}" >/dev/null 2>&1; '
           f'safe_rm "{victim}" "Example" >/dev/null 2>&1; true')
    subprocess.run(["bash", "-c", cmd], env=env, capture_output=True, text=True, timeout=30)
    assert not _log_path(tmp_path).exists()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/test_oplog.py::test_real_trash_op_records_one_line -v`
Expected: FAIL (no log line written; file missing).

- [ ] **Step 3: Write minimal implementation**

3a. Add the category global. After the existing context vars (lines 620-621, `_CURRENT_NEEDS_SUDO=0` / `_CURRENT_IS_TRASH_EMPTY=0`), add:

```bash
_CURRENT_CATEGORY=""
```

3b. In `safe_rm`, add an `oplog_record` call on each success branch. The direct-rm sudo branch (after line 650 `success ...`), the direct-rm non-sudo branch (after line 657 `success ...`), and the trash branch (after line 664 `success ...`). Insert the matching line inside each `&& { ... }` / `if` success block:

For the two direct-rm branches (use action `delete`):

```bash
        oplog_record "delete" "$sz_b" "$path" "$_CURRENT_CATEGORY"
```

For the trash branch (use action `trash`):

```bash
      oplog_record "trash" "$sz_b" "$path" "$_CURRENT_CATEGORY"
```

3c. In `safe_rm_contents`, the bulk branches operate on a directory whose children were removed; record one summary line per directory using `$sz_b` and `$path`. In the two direct-rm success blocks (after line 706 and line 713 `success ...`) add:

```bash
        oplog_record "delete" "$sz_b" "$path" "$_CURRENT_CATEGORY"
```

In the trash branch, after `if $trashed_any; then` / `success ...` (after line 725) add:

```bash
      oplog_record "trash" "$sz_b" "$path" "$_CURRENT_CATEGORY"
```

(The exclusion-aware path at line 684 delegates to `safe_rm` per child, which already records; do not add a call there.)

3d. Set the category in `run_clean`. Replace the call line `"${fn_map[$real_idx]}"` (line 1826) with:

```bash
      _CURRENT_CATEGORY="$(cat_field "$real_idx" id)"
      "${fn_map[$real_idx]}"
      _CURRENT_CATEGORY=""
```

(`cat_field <idx> id` returns the category key, e.g. `user_cache`; confirm the field name by checking `cat_field` usage near line 487. If the id accessor differs, use `${CAT_IDS[$real_idx]}` instead.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/test_oplog.py -v`
Expected: PASS (all, including the two new tests).

- [ ] **Step 5: Commit**

```bash
git add clean_mac.sh tests/test_oplog.py
git commit -m "feat: record trash/delete operations to the operation log"
```

---

### Task 3: `--history` and `--history-json` CLI flags

**Files:**
- Modify: `clean_mac.sh` — add `do_history` / `do_history_json` (near other JSON fns, after line 1843); register flags in the arg parser (after the `--status-json` case, line 2724)
- Test: `tests/test_oplog.py` (extend)

**Interfaces:**
- Consumes: `OPLOG_FILE` (Task 1), `format_bytes`, `json_escape_str`, `L` (i18n).
- Produces:
  - `--history-json` → JSON array, newest first: `[{"ts":<int>,"action":"trash|delete","bytes":<int>,"size_human":"<str>","path":"<str>","category":"<str>","recoverable":<bool>}]`. Empty log → `[]`.
  - `--history` → human table, newest first. Empty log → a localized "no history" line.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_oplog.py`:

```python
import json


def test_history_json_empty_is_array(tmp_path):
    env = dict(os.environ, HOME=str(tmp_path))
    out = subprocess.run(["bash", str(SCRIPT), "--history-json"],
                         env=env, capture_output=True, text=True, timeout=30)
    assert out.returncode == 0, out.stderr
    assert json.loads(out.stdout) == []


def test_history_json_newest_first_with_fields(tmp_path):
    log = _log_path(tmp_path)
    log.parent.mkdir(parents=True)
    log.write_text(
        "100\ttrash\t2048\t/tmp/old\tuser_cache\n"
        "200\tdelete\t4096\t/tmp/new\tsystem_cache\n"
    )
    env = dict(os.environ, HOME=str(tmp_path))
    out = subprocess.run(["bash", str(SCRIPT), "--history-json"],
                         env=env, capture_output=True, text=True, timeout=30)
    rows = json.loads(out.stdout)
    assert [r["ts"] for r in rows] == [200, 100]  # newest first
    assert rows[0]["action"] == "delete"
    assert rows[0]["recoverable"] is False
    assert rows[1]["recoverable"] is True
    assert rows[0]["bytes"] == 4096
    assert "size_human" in rows[0]
    assert rows[1]["path"] == "/tmp/old"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/test_oplog.py::test_history_json_empty_is_array -v`
Expected: FAIL (unknown flag; non-JSON output or non-zero exit).

- [ ] **Step 3: Write minimal implementation**

3a. Add reader functions near the other JSON output functions (after line 1843, the `─── JSON Output Functions` header):

```bash
do_history_json() {
  echo -n "["
  local first=true
  if [ -f "$OPLOG_FILE" ]; then
    # Reverse to newest-first.
    local rev; rev="$(tail -r "$OPLOG_FILE" 2>/dev/null || tail -n 99999 "$OPLOG_FILE" | sed '1!G;h;$!d')"
    local ts action bytes path category
    while IFS=$'\t' read -r ts action bytes path category; do
      [ -z "$ts" ] && continue
      case "$ts" in *[!0-9]*) continue ;; esac   # skip malformed lines
      local recoverable="false"
      [ "$action" = "trash" ] && recoverable="true"
      local size_h; size_h=$(format_bytes "${bytes:-0}")
      $first || echo -n ","
      first=false
      printf '{"ts":%s,"action":"%s","bytes":%s,"size_human":"%s","path":"%s","category":"%s","recoverable":%s}' \
        "$ts" "$(json_escape_str "$action")" "${bytes:-0}" \
        "$(json_escape_str "$size_h")" "$(json_escape_str "$path")" \
        "$(json_escape_str "$category")" "$recoverable"
    done <<EOF
$rev
EOF
  fi
  echo "]"
}

do_history() {
  if [ ! -s "$OPLOG_FILE" ]; then
    echo "  $(L no_history)"
    return 0
  fi
  printf "  %-19s  %-9s  %-10s  %-14s  %s\n" "When" "Action" "Size" "Category" "Path"
  local rev; rev="$(tail -r "$OPLOG_FILE" 2>/dev/null || sed '1!G;h;$!d' "$OPLOG_FILE")"
  local ts action bytes path category
  while IFS=$'\t' read -r ts action bytes path category; do
    [ -z "$ts" ] && continue
    case "$ts" in *[!0-9]*) continue ;; esac
    local when; when=$(date -r "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$ts")
    local size_h; size_h=$(format_bytes "${bytes:-0}")
    local tag="$action"
    [ "$action" = "trash" ] && tag="trash↺"
    printf "  %-19s  %-9s  %-10s  %-14s  %s\n" "$when" "$tag" "$size_h" "$category" "$path"
  done <<EOF
$rev
EOF
}
```

3b. Add the `no_history` i18n string. Find the i18n block (the `L()` lookups near line 313, e.g. `en::critical_protected)`) and add an English entry alongside the others:

```bash
    en::no_history)           echo "No cleanup history yet." ;;
```

(If the tool ships other languages in the same block, add a matching key per language following the existing pattern for that block.)

3c. Register the flags in the arg parser. After the `--status-json` case (line 2724-2727), add:

```bash
      --history)
        do_history
        exit 0
        ;;
      --history-json)
        do_history_json
        exit 0
        ;;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/test_oplog.py -v`
Expected: PASS (all). Then sanity-check the human view:
Run: `bash clean_mac.sh --history` → prints the "No cleanup history yet." line on a clean machine, or a table.

- [ ] **Step 5: Commit**

```bash
git add clean_mac.sh tests/test_oplog.py
git commit -m "feat: add --history and --history-json CLI flags"
```

---

### Task 4: `/api/history` server route + dashboard History tab

**Files:**
- Modify: `web/server.py` — add route in `do_GET` (after line 482) + `_handle_history` (near `_handle_status`, line 517)
- Modify: `web/index.html` — add History tab + panel
- Modify: `web/script.js` — fetch + render history
- Test: `tests/test_server_validation.py` (extend)

**Interfaces:**
- Consumes: `--history-json` (Task 3), existing `_run_script`, `_send_json`, `_send_error_json`.
- Produces: `GET /api/history` → the JSON array from `--history-json`.

- [ ] **Step 1: Write the failing test**

Inspect `tests/test_server_validation.py` for the existing helper that starts the server / asserts loopback + token behavior, and follow that exact pattern. Add a test that the route exists and returns a list. Minimal shape (adapt names to the file's existing fixtures):

```python
def test_history_route_returns_list(server_base, session_headers):
    import urllib.request, json
    req = urllib.request.Request(server_base + "/api/history", headers=session_headers)
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = json.loads(resp.read())
    assert isinstance(body, list)
```

If the suite has no live-server fixture, instead add a unit test asserting `do_GET` routing maps `/api/history` to `_handle_history` (mirror however `/api/status` is currently tested in this file).

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/test_server_validation.py -k history -v`
Expected: FAIL (404 / route not found).

- [ ] **Step 3: Write minimal implementation**

3a. In `web/server.py` `do_GET`, after the `/api/forecast` branch (line 481-482), add:

```python
        elif path == "/api/history":
            self._handle_history()
```

3b. Add the handler next to `_handle_status` (after line 522):

```python
    def _handle_history(self):
        data, err = self._run_script(["--history-json"], timeout=15)
        if err:
            self._send_error_json(f"History error: {err}")
        else:
            self._send_json(data)
```

3c. In `web/index.html`, add a History tab button next to the existing tab buttons and a matching panel. Match the existing tab markup exactly (copy the structure of an existing tab such as the forecast/status tab). Tab button:

```html
<button class="tab-btn" data-tab="history">History</button>
```

Panel:

```html
<section id="tab-history" class="tab-panel" hidden>
  <h2>Cleanup History</h2>
  <p class="muted">What was removed, newest first. Items marked recoverable can be restored from Trash.</p>
  <div id="history-list" class="history-list"></div>
</section>
```

3d. In `web/script.js`, add a loader that fetches `/api/history` (using the same fetch wrapper / session-token header the other GET tabs use, e.g. however `loadStatus()` or `loadForecast()` calls the API) and renders rows. Wire it to run when the History tab is activated, following the existing tab-activation pattern:

```javascript
async function loadHistory() {
  const list = document.getElementById('history-list');
  if (!list) return;
  try {
    const rows = await apiGet('/api/history'); // reuse existing GET helper
    if (!Array.isArray(rows) || rows.length === 0) {
      list.innerHTML = '<p class="muted">No cleanup history yet.</p>';
      return;
    }
    list.innerHTML = rows.map(r => {
      const when = new Date(r.ts * 1000).toLocaleString();
      const badge = r.recoverable
        ? '<span class="badge badge-ok">recoverable</span>'
        : '<span class="badge badge-warn">permanent</span>';
      return `<div class="history-row">
        <span class="history-when">${when}</span>
        ${badge}
        <span class="history-size">${r.size_human}</span>
        <span class="history-cat">${r.category || ''}</span>
        <span class="history-path">${r.path}</span>
      </div>`;
    }).join('');
  } catch (e) {
    list.innerHTML = '<p class="muted">Could not load history.</p>';
  }
}
```

(Replace `apiGet` with the file's actual GET helper name. Call `loadHistory()` from the tab-switch handler when `data-tab === 'history'`, matching how other tabs lazy-load.)

- [ ] **Step 4: Run tests + manual check**

Run: `python3 -m pytest tests/test_server_validation.py -v`
Expected: PASS.
Manual: `python3 web/server.py`, open the dashboard, click History, confirm rows render (or the empty state shows).

- [ ] **Step 5: Commit**

```bash
git add web/server.py web/index.html web/script.js tests/test_server_validation.py
git commit -m "feat: add /api/history route and dashboard History tab"
```

---

## Self-Review

**Spec coverage:**
- Operation log writer → Task 1. ✓
- Wired into safe_rm/safe_rm_contents on real success only, dry-run/opt-out/rotation → Task 1 + Task 2. ✓
- Category in record → Task 2 (`_CURRENT_CATEGORY`). ✓
- `--history` + `--history-json` → Task 3. ✓
- Server `/api/history` (read-only, token/loopback) + History tab → Task 4. ✓
- Tests at each layer → Tasks 1-4. ✓
- Non-goals (no undo, no protection centralization) → not present. ✓

**Placeholder scan:** All steps contain concrete code/commands. Two spots require reading existing code to confirm an accessor name (`cat_field ... id` in Task 2, GET helper name in Task 4); both give an explicit fallback. No TBD/TODO.

**Type consistency:** `OPLOG_FILE`, `oplog_record`, `_CURRENT_CATEGORY`, `do_history`/`do_history_json`, `/api/history`, `_handle_history` are named identically across all tasks. JSON field names (`ts`, `action`, `bytes`, `size_human`, `path`, `category`, `recoverable`) match between Task 3 producer and Task 4 consumer.
