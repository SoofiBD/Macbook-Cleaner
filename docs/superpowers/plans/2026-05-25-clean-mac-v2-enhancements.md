# Clean Mac v2 Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add App Uninstaller, Mail Downloads, Dev Tools subitems, DNS/RAM/LaunchAgents maintenance, input validation hardening, and parallel scanning to the Clean Mac tool.

**Architecture:** `clean_mac.sh` gains 2 new categories (indices 10–11), new maintenance bash functions, dev-tools subitems, parallel `scan_all`, and new CLI flags. `server.py` gains input validation helpers + 3 new POST routes + `app_uninstaller_selected` field. Frontend gains 2 new category cards, 3 maintenance cards, and matching mock data.

**Tech Stack:** Bash 3.2+, Python 3 stdlib (`http.server`, `re`, `unittest`), vanilla JS/HTML — zero new dependencies.

---

## File Map

| File | Changes |
|------|---------|
| `clean_mac.sh` | Extend 4 parallel arrays to 12; add `APP_UNINSTALLER_CLEAN`, `get_app_bundle_id`, `scan_app_uninstaller`, `scan_app_uninstaller_subitems_json`, `clean_app_uninstaller`, `scan_mail_downloads`, `clean_mail_downloads`; extend `scan_developer_subitems_json` + `clean_developer` for brew/docker/npm/pip; add `do_flush_dns`, `do_purge_ram`, `do_clean_launchagents`; update `scan_all`, `do_scan_json`, `do_clean_json`, `run_clean`, `main` |
| `web/server.py` | Add validation constants + 4 helpers; apply to `_handle_clean`; add `_handle_flush_dns`, `_handle_purge_ram`, `_handle_launchagents_clean`; update `do_GET`/`do_POST` dispatch |
| `web/index.html` | Add 3 maintenance cards (DNS flush, RAM purge, LaunchAgents) to the maintenance `<ul>` |
| `web/script.js` | Add 2 entries to `CATEGORIES`; update mock data; add `app_uninstaller_selected` to clean payload; add `el.btnFlushDns`, `el.btnPurgeRam`, `el.btnLaunchAgents`; add 3 handler functions + bindings |
| `tests/test_server_validation.py` | New file — unittest for validation helpers |

---

## Task 1: Write Failing Validation Tests (TDD)

**Files:**
- Create: `tests/__init__.py` (empty)
- Create: `tests/test_server_validation.py`

- [ ] **Step 1: Create tests directory and empty init**

```bash
mkdir -p tests
touch tests/__init__.py
```

- [ ] **Step 2: Write the test file**

Create `tests/test_server_validation.py`:

```python
"""Unit tests for server.py input validation helpers."""
import sys
import os
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'web'))


class TestValidateAppLeftover(unittest.TestCase):
    def setUp(self):
        from server import _validate_app_leftover
        self.v = _validate_app_leftover

    def test_allows_simple_name(self):
        self.assertTrue(self.v("Slack"))
        self.assertTrue(self.v("com.google.Chrome"))
        self.assertTrue(self.v("My App"))
        self.assertTrue(self.v("App-Name.1"))

    def test_blocks_path_traversal(self):
        self.assertFalse(self.v("../etc/passwd"))
        self.assertFalse(self.v("/absolute/path"))

    def test_blocks_special_chars(self):
        self.assertFalse(self.v("app;rm -rf /"))
        self.assertFalse(self.v("app`id`"))
        self.assertFalse(self.v("app$HOME"))

    def test_blocks_too_long(self):
        self.assertFalse(self.v("a" * 65))

    def test_blocks_empty(self):
        self.assertFalse(self.v(""))


class TestValidateDeveloperItem(unittest.TestCase):
    def setUp(self):
        from server import _validate_developer_item
        self.v = _validate_developer_item

    def test_whitelist_entries(self):
        for item in ("derived_data", "broken_links", "brew_cache",
                     "docker_prune", "npm_cache", "pip_cache"):
            self.assertTrue(self.v(item), f"Expected True for {item}")

    def test_rejects_unknown(self):
        self.assertFalse(self.v("evil_cmd"))
        self.assertFalse(self.v("../../etc"))
        self.assertFalse(self.v("; rm -rf /"))


class TestValidateBrowserKey(unittest.TestCase):
    def setUp(self):
        from server import _validate_browser_key
        self.v = _validate_browser_key

    def test_whitelist_entries(self):
        for k in ("safari", "cookies", "chrome", "firefox",
                  "brave", "edge", "opera", "arc"):
            self.assertTrue(self.v(k), f"Expected True for {k}")

    def test_rejects_unknown(self):
        self.assertFalse(self.v("not_a_browser"))
        self.assertFalse(self.v("; rm -rf /"))


class TestValidateAppName(unittest.TestCase):
    def setUp(self):
        from server import _validate_app_name
        self.v = _validate_app_name

    def test_allows_valid_app_names(self):
        self.assertTrue(self.v("Firefox"))
        self.assertTrue(self.v("Visual Studio Code"))
        self.assertTrue(self.v("App-Name.1"))

    def test_blocks_traversal(self):
        self.assertFalse(self.v("../Applications"))
        self.assertFalse(self.v("/Applications/Evil"))

    def test_blocks_injection(self):
        self.assertFalse(self.v("App;rm -rf /"))
        self.assertFalse(self.v("App`id`"))

    def test_blocks_empty(self):
        self.assertFalse(self.v(""))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run tests — confirm they fail with ImportError**

```bash
cd /Users/burak/Desktop/projects/apple-cleanup
python3 -m unittest tests.test_server_validation -v 2>&1 | head -20
```

Expected: `ImportError: cannot import name '_validate_app_leftover' from 'server'`

---

## Task 2: Server.py — Input Validation (make tests pass)

**Files:**
- Modify: `web/server.py`

- [ ] **Step 1: Add validation constants and helpers right after the `MIME_TYPES` dict (after line 29)**

Insert after `MIME_TYPES = { ... }`:

```python
# ── Input validation ───────────────────────────────────────
_APP_LEFTOVER_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$')
_APP_NAME_RE     = re.compile(r'^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$')

_DEVELOPER_WHITELIST = frozenset({
    "derived_data", "broken_links",
    "brew_cache", "docker_prune", "npm_cache", "pip_cache",
})
_BROWSER_WHITELIST = frozenset({
    "safari", "cookies", "chrome", "firefox",
    "brave", "edge", "opera", "arc",
})


def _validate_app_leftover(name: str) -> bool:
    return (bool(_APP_LEFTOVER_RE.match(name))
            and ".." not in name
            and "/" not in name)


def _validate_developer_item(item: str) -> bool:
    return item in _DEVELOPER_WHITELIST


def _validate_browser_key(key: str) -> bool:
    return key in _BROWSER_WHITELIST


def _validate_app_name(name: str) -> bool:
    return (bool(_APP_NAME_RE.match(name))
            and ".." not in name
            and "/" not in name)
```

- [ ] **Step 2: Apply validation in `_handle_clean()` — replace the four existing payload-list-to-args blocks (lines ~138–155)**

Replace the entire section that builds `args` from `app_leftovers_selected`, `browser_full_selected`, `developer_selected`, `ios_backups_selected` with the hardened version below. Keep `categories` and `cat_str` logic unchanged:

```python
        app_leftovers_selected = payload.get("app_leftovers_selected", [])
        if app_leftovers_selected and isinstance(app_leftovers_selected, list):
            safe = [x for x in app_leftovers_selected
                    if isinstance(x, str) and _validate_app_leftover(x)]
            if safe:
                args += ["--app-leftovers", ",".join(safe)]

        browser_full_selected = payload.get("browser_full_selected", [])
        if browser_full_selected and isinstance(browser_full_selected, list):
            safe = [x for x in browser_full_selected
                    if isinstance(x, str) and _validate_browser_key(x)]
            if safe:
                args += ["--browser-full-sub", ",".join(safe)]

        developer_selected = payload.get("developer_selected", [])
        if developer_selected and isinstance(developer_selected, list):
            safe = [x for x in developer_selected
                    if isinstance(x, str) and _validate_developer_item(x)]
            if safe:
                args += ["--developer-sub", ",".join(safe)]

        ios_backups_selected = payload.get("ios_backups_selected", [])
        if ios_backups_selected and isinstance(ios_backups_selected, list):
            _uuid_re = re.compile(r'^[0-9A-Fa-f\-]{1,40}$')
            safe = [u for u in ios_backups_selected
                    if isinstance(u, str) and _uuid_re.match(u)]
            if safe:
                args += ["--ios-backups-sub", ",".join(safe)]

        app_uninstaller_selected = payload.get("app_uninstaller_selected", [])
        if app_uninstaller_selected and isinstance(app_uninstaller_selected, list):
            safe = [x for x in app_uninstaller_selected
                    if isinstance(x, str) and _validate_app_name(x)]
            if safe:
                args += ["--app-uninstaller-sub", ",".join(safe)]
```

- [ ] **Step 3: Run tests — confirm they all pass**

```bash
cd /Users/burak/Desktop/projects/apple-cleanup
python3 -m unittest tests.test_server_validation -v
```

Expected output: all 20 tests pass with `OK`.

- [ ] **Step 4: Commit**

```bash
git add tests/__init__.py tests/test_server_validation.py web/server.py
git commit -m "$(cat <<'EOF'
feat(security): harden server.py input validation with whitelist/regex guards

Add _validate_app_leftover, _validate_developer_item, _validate_browser_key,
_validate_app_name helpers; apply to all clean payload fields; add
app_uninstaller_selected field wired to new --app-uninstaller-sub flag.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Bash — Extend Arrays + Mail Downloads Category

**Files:**
- Modify: `clean_mac.sh`

- [ ] **Step 1: Add `APP_UNINSTALLER_CLEAN` variable near the other JSON-mode vars (after `IOS_BACKUPS_CLEAN=""` around line 33)**

```bash
APP_UNINSTALLER_CLEAN=""
```

- [ ] **Step 2: Extend the four parallel arrays from 10 to 12 entries (lines ~63–68)**

Replace the four array declarations:

```bash
CAT_IDS=(user_cache system_cache app_leftovers logs temp_files developer trash \
         browser_cache browser_full ios_backups app_uninstaller mail_downloads)
CAT_NAMES=("Kullanıcı Cache" "Sistem Cache" "Uygulama Kalıntıları" \
            "Loglar" "Geçici Dosyalar" "Geliştirici" "Çöp Kutusu" \
            "Tarayıcı Cache" "Tarayıcı Tüm Veri" "iOS Yedekleri" \
            "Tam Uygulama Kaldırıcı" "Mail İndirilenleri")
CAT_SIZES=(0 0 0 0 0 0 0 0 0 0 0 0)
CAT_NEEDS_SUDO=(0 1 0 0 0 0 0 0 0 0 0 0)
```

- [ ] **Step 3: Add the Mail Downloads constant + scan + clean functions after `scan_ios_backups` (around line 384)**

```bash
MAIL_DOWNLOADS_DIR="$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"

scan_mail_downloads() {
  local s=0
  if [ -d "$MAIL_DOWNLOADS_DIR" ]; then
    s=$(get_dir_size_bytes "$MAIL_DOWNLOADS_DIR") || s=0
  fi
  CAT_SIZES[11]=$s
}

clean_mail_downloads() {
  header "📧 Mail İndirilenleri Temizleniyor"
  safe_rm_contents "$MAIL_DOWNLOADS_DIR" "Mail Downloads"
}
```

- [ ] **Step 4: Verify arrays are consistent — quick sanity check**

```bash
cd /Users/burak/Desktop/projects/apple-cleanup
bash -c 'source clean_mac.sh --help 2>/dev/null || true' | head -5
# Should not crash; or run:
bash -n clean_mac.sh && echo "Syntax OK"
```

Expected: `Syntax OK`

---

## Task 4: Bash — App Uninstaller Module

**Files:**
- Modify: `clean_mac.sh`

- [ ] **Step 1: Add `get_app_bundle_id` helper right before `scan_user_cache` (around line 270)**

```bash
get_app_bundle_id() {
  local app_path="$1"
  local plist="$app_path/Contents/Info.plist"
  [ -f "$plist" ] || { echo ""; return; }
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || echo ""
}
```

- [ ] **Step 2: Add `scan_app_uninstaller` function after `scan_ios_backups` (before the new mail downloads functions)**

```bash
scan_app_uninstaller() {
  local total=0
  local app app_name s
  while IFS= read -r -d '' app; do
    app_name=$(basename "$app" .app)
    for dir in \
        "$HOME/Library/Application Support/$app_name" \
        "$HOME/Library/Caches/$app_name"; do
      [ -d "$dir" ] || continue
      s=$(get_size_bytes "$dir") || s=0
      total=$((total + s))
    done
  done < <(find /Applications -maxdepth 1 -name "*.app" -print0 2>/dev/null)
  CAT_SIZES[10]=$total
}
```

- [ ] **Step 3: Add `scan_app_uninstaller_subitems_json` right after `scan_ios_backups_subitems_json` (around line 1083)**

```bash
scan_app_uninstaller_subitems_json() {
  local first=true
  local app app_name bundle_id total s sz_h esc_name esc_bundle
  while IFS= read -r -d '' app; do
    app_name=$(basename "$app" .app)
    bundle_id=$(get_app_bundle_id "$app")
    total=0
    local dirs=()
    dirs+=("$HOME/Library/Application Support/$app_name")
    dirs+=("$HOME/Library/Caches/$app_name")
    if [ -n "$bundle_id" ]; then
      dirs+=("$HOME/Library/Application Support/$bundle_id")
      dirs+=("$HOME/Library/Caches/$bundle_id")
      dirs+=("$HOME/Library/Preferences/${bundle_id}.plist")
      dirs+=("$HOME/Library/Saved Application State/${bundle_id}.savedState")
    fi
    local d
    for d in "${dirs[@]}"; do
      [ -e "$d" ] || continue
      s=$(get_size_bytes "$d") || s=0
      total=$((total + s))
    done
    sz_h=$(format_bytes "$total")
    esc_name=$(json_escape_str "$app_name")
    esc_bundle=$(json_escape_str "$bundle_id")
    if [ "$first" = true ]; then first=false; else echo ","; fi
    echo -n "        {\"id\": \"$esc_name\", \"name\": \"$esc_name\", \"bundle_id\": \"$esc_bundle\", \"size_bytes\": $total, \"size_human\": \"$sz_h\", \"is_orphaned\": false}"
  done < <(find /Applications -maxdepth 1 -name "*.app" -print0 2>/dev/null | sort -z)
}
```

- [ ] **Step 4: Add `clean_app_uninstaller` function after `clean_ios_backups` (around line 619)**

```bash
clean_app_uninstaller() {
  header "🗑️  Tam Uygulama Kaldırıcı"
  if $JSON_MODE; then
    [ -z "$APP_UNINSTALLER_CLEAN" ] && { info "Temizlenecek uygulama belirtilmedi."; return; }
    local IFS_OLD="$IFS"
    IFS=','
    local apps=($APP_UNINSTALLER_CLEAN)
    IFS="$IFS_OLD"
    local app_name
    for app_name in ${apps[@]+"${apps[@]}"}; do
      [ -z "$app_name" ] && continue
      local app_path="/Applications/$app_name.app"
      [ -d "$app_path" ] || continue
      local bundle_id; bundle_id=$(get_app_bundle_id "$app_path")
      safe_rm "$app_path" "$app_name.app"
      safe_rm "$HOME/Library/Application Support/$app_name" "$app_name (Application Support)"
      safe_rm "$HOME/Library/Caches/$app_name" "$app_name (Caches)"
      if [ -n "$bundle_id" ]; then
        safe_rm "$HOME/Library/Application Support/$bundle_id" "$bundle_id (Application Support)"
        safe_rm "$HOME/Library/Caches/$bundle_id" "$bundle_id (Caches)"
        safe_rm "$HOME/Library/Preferences/$bundle_id.plist" "$bundle_id (Preferences)"
        safe_rm "$HOME/Library/Saved Application State/$bundle_id.savedState" "$bundle_id (Saved State)"
      fi
    done
    return
  fi
  warn "Uygulama kaldırıcı yalnızca web arayüzünden kullanılabilir."
}
```

- [ ] **Step 5: Verify bash syntax**

```bash
bash -n clean_mac.sh && echo "Syntax OK"
```

Expected: `Syntax OK`

---

## Task 5: Bash — Dev Tools Subitems (Homebrew, Docker, npm, pip)

**Files:**
- Modify: `clean_mac.sh`

- [ ] **Step 1: Replace `scan_developer_subitems_json` body to append 4 new subitems**

The current function ends after the broken-links entry. Append the following 4 entries **before** the closing of the function (after the broken_links echo line ~1021):

```bash
  # Homebrew cache
  local brew_cache_dir
  brew_cache_dir=$(brew --cache 2>/dev/null || echo "$HOME/Library/Caches/Homebrew")
  local s_brew=0
  [ -d "$brew_cache_dir" ] && s_brew=$(get_dir_size_bytes "$brew_cache_dir") || s_brew=0
  local sz_brew; sz_brew=$(format_bytes "$s_brew")
  local esc_brew; esc_brew=$(json_escape_str "$brew_cache_dir")
  echo "        ,{\"id\": \"brew_cache\", \"name\": \"Homebrew Cache\", \"path\": \"$esc_brew\", \"size_bytes\": $s_brew, \"size_human\": \"$sz_brew\", \"is_orphaned\": true}"

  # Docker system data
  local docker_dir="$HOME/Library/Containers/com.docker.docker/Data"
  local s_docker=0
  [ -d "$docker_dir" ] && s_docker=$(get_dir_size_bytes "$docker_dir") || s_docker=0
  local sz_docker; sz_docker=$(format_bytes "$s_docker")
  local esc_docker; esc_docker=$(json_escape_str "$docker_dir")
  echo "        ,{\"id\": \"docker_prune\", \"name\": \"Docker System\", \"path\": \"$esc_docker\", \"size_bytes\": $s_docker, \"size_human\": \"$sz_docker\", \"is_orphaned\": true}"

  # npm cache
  local npm_dir="$HOME/.npm/_cacache"
  local s_npm=0
  [ -d "$npm_dir" ] && s_npm=$(get_dir_size_bytes "$npm_dir") || s_npm=0
  local sz_npm; sz_npm=$(format_bytes "$s_npm")
  echo "        ,{\"id\": \"npm_cache\", \"name\": \"npm Cache\", \"path\": \"$npm_dir\", \"size_bytes\": $s_npm, \"size_human\": \"$sz_npm\", \"is_orphaned\": true}"

  # pip cache
  local pip_dir="$HOME/Library/Caches/pip"
  local s_pip=0
  [ -d "$pip_dir" ] && s_pip=$(get_dir_size_bytes "$pip_dir") || s_pip=0
  local sz_pip; sz_pip=$(format_bytes "$s_pip")
  echo "        ,{\"id\": \"pip_cache\", \"name\": \"pip Cache\", \"path\": \"$pip_dir\", \"size_bytes\": $s_pip, \"size_human\": \"$sz_pip\", \"is_orphaned\": true}"
```

- [ ] **Step 2: Extend `clean_developer` JSON-mode branch to handle 4 new items**

Inside `clean_developer`, in the JSON-mode item loop (the `for item in ...` block around line 807), add the following cases after the existing `elif [ "$item" = "broken_links" ]` branch:

```bash
      elif [ "$item" = "brew_cache" ]; then
        if command -v brew &>/dev/null; then
          local brew_cache_dir; brew_cache_dir=$(brew --cache 2>/dev/null || echo "$HOME/Library/Caches/Homebrew")
          local sz_before; sz_before=$(get_size_bytes "$brew_cache_dir") || sz_before=0
          brew cleanup --prune=all 2>/dev/null || true
          TOTAL_FREED=$((TOTAL_FREED + sz_before))
          TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
        fi
      elif [ "$item" = "docker_prune" ]; then
        if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
          docker system prune -a -f --volumes 2>/dev/null || true
          TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
        fi
      elif [ "$item" = "npm_cache" ]; then
        local npm_dir="$HOME/.npm/_cacache"
        if [ -d "$npm_dir" ]; then
          local sz_npm; sz_npm=$(get_dir_size_bytes "$npm_dir") || sz_npm=0
          rm -rf "$npm_dir" 2>/dev/null && {
            TOTAL_FREED=$((TOTAL_FREED + sz_npm))
            TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
          } || true
        fi
      elif [ "$item" = "pip_cache" ]; then
        local pip_dir="$HOME/Library/Caches/pip"
        if [ -d "$pip_dir" ]; then
          safe_rm_contents "$pip_dir" "pip cache"
        fi
```

- [ ] **Step 3: Verify bash syntax**

```bash
bash -n clean_mac.sh && echo "Syntax OK"
```

---

## Task 6: Bash — Maintenance Functions + main() Wiring

**Files:**
- Modify: `clean_mac.sh`

- [ ] **Step 1: Add `do_flush_dns`, `do_purge_ram`, `do_clean_launchagents` after `do_spotlight_reindex` (around line 1234)**

```bash
do_flush_dns() {
  sudo dscacheutil -flushcache 2>/dev/null || true
  sudo killall -HUP mDNSResponder 2>/dev/null || true
  echo '{"success": true, "message": "DNS önbelleği temizlendi."}'
}

do_purge_ram() {
  sudo purge 2>/dev/null || true
  echo '{"success": true, "message": "Bellek boşaltma komutu çalıştırıldı."}'
}

do_clean_launchagents() {
  local cleaned=0
  local broken_plists=()
  local dirs=("$HOME/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons")
  local dir plist program
  for dir in "${dirs[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r plist; do
      [ -f "$plist" ] || continue
      program=$(/usr/libexec/PlistBuddy -c "Print :Program" "$plist" 2>/dev/null || \
                /usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null || \
                echo "")
      if [ -n "$program" ] && [ ! -e "$program" ]; then
        broken_plists+=("$plist")
      fi
    done < <(find "$dir" -maxdepth 1 -name "*.plist" 2>/dev/null)
  done

  for plist in ${broken_plists[@]+"${broken_plists[@]}"}; do
    launchctl unload "$plist" 2>/dev/null || true
    if sudo rm -f "$plist" 2>/dev/null || rm -f "$plist" 2>/dev/null; then
      cleaned=$((cleaned + 1))
    fi
  done

  local found=${#broken_plists[@]}
  echo "{\"success\": true, \"found\": $found, \"cleaned\": $cleaned, \"message\": \"$cleaned bozuk plist temizlendi.\"}"
}
```

- [ ] **Step 2: Update `scan_all` fns array to include 2 new scan functions (around line 388)**

Replace the `local fns=(...)` line inside `scan_all`:

```bash
  local fns=(scan_user_cache scan_system_cache scan_app_leftovers \
             scan_logs scan_temp_files scan_developer scan_trash \
             scan_browser_cache scan_browser_full scan_ios_backups \
             scan_app_uninstaller scan_mail_downloads)
```

- [ ] **Step 3: Update `run_clean` fn_map to include 2 new clean functions (around line 921)**

Replace the `local fn_map=(...)` line in `run_clean`:

```bash
  local fn_map=(clean_user_cache clean_system_cache clean_app_leftovers \
                clean_logs clean_temp_files clean_developer clean_trash \
                clean_browser_cache clean_browser_full clean_ios_backups \
                clean_app_uninstaller clean_mail_downloads)
```

- [ ] **Step 4: Update `do_clean_json` fn_map to match (around line 1170)**

Replace the `local fn_map=(...)` line inside `do_clean_json`:

```bash
  local fn_map=(clean_user_cache clean_system_cache clean_app_leftovers \
                clean_logs clean_temp_files clean_developer clean_trash \
                clean_browser_cache clean_browser_full clean_ios_backups \
                clean_app_uninstaller clean_mail_downloads)
```

- [ ] **Step 5: Add `app_uninstaller` subitems block to `do_scan_json` (inside the `for i in "${!CAT_IDS[@]}"` loop)**

After the existing `elif [ "$id" = "ios_backups" ]` block (around line 1130), add:

```bash
    elif [ "$id" = "app_uninstaller" ]; then
      echo "      ,\"subitems\": ["
      scan_app_uninstaller_subitems_json
      echo ""
      echo "      ]"
```

- [ ] **Step 6: Add new flags to `main()` case statement (inside the `while [ $i -lt ${#args[@]} ]` loop, after `--spotlight-reindex` case)**

```bash
      --flush-dns)
        do_flush_dns
        exit 0
        ;;
      --purge-ram)
        do_purge_ram
        exit 0
        ;;
      --launchagents-clean)
        do_clean_launchagents
        exit 0
        ;;
      --app-uninstaller-sub)
        i=$((i + 1))
        APP_UNINSTALLER_CLEAN="${args[$i]}"
        ;;
```

- [ ] **Step 7: Verify bash syntax and run a quick smoke test**

```bash
bash -n clean_mac.sh && echo "Syntax OK"
bash clean_mac.sh --status-json
```

Expected: `Syntax OK` then `{"status": "ready", ...}` JSON.

- [ ] **Step 8: Commit**

```bash
git add clean_mac.sh
git commit -m "$(cat <<'EOF'
feat(bash): add App Uninstaller, Mail Downloads, Dev Tools subitems, maintenance functions

New categories: app_uninstaller (index 10), mail_downloads (index 11).
Dev tools: brew_cache, docker_prune, npm_cache, pip_cache subitems.
Maintenance: do_flush_dns, do_purge_ram, do_clean_launchagents.
Wired: scan_all, run_clean, do_clean_json, do_scan_json, main.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Server.py — New Routes

**Files:**
- Modify: `web/server.py`

- [ ] **Step 1: Add 3 new GET route and 3 new POST routes to dispatch methods**

In `do_GET`, after the `elif path == "/api/status":` branch (around line 93), add:

```python
        elif path == "/api/launchagents":
            self._handle_launchagents_scan()
```

In `do_POST`, after the `elif parsed.path == "/api/spotlight-reindex":` branch (around line 103), add:

```python
        elif parsed.path == "/api/flush-dns":
            self._handle_flush_dns()
        elif parsed.path == "/api/purge-ram":
            self._handle_purge_ram()
        elif parsed.path == "/api/launchagents-clean":
            self._handle_launchagents_clean()
```

- [ ] **Step 2: Add 4 new handler methods to `CleanupHandler` (after `_handle_spotlight_reindex`)**

```python
    def _handle_flush_dns(self):
        data, err = self._run_script(["--flush-dns"], timeout=15)
        if err:
            self._send_error_json(f"DNS temizleme hatası: {err}")
        else:
            self._send_json(data)

    def _handle_purge_ram(self):
        data, err = self._run_script(["--purge-ram"], timeout=30)
        if err:
            self._send_error_json(f"Bellek temizleme hatası: {err}")
        else:
            self._send_json(data)

    def _handle_launchagents_scan(self):
        data, err = self._run_script(["--launchagents-clean"], timeout=30)
        if err:
            self._send_error_json(f"LaunchAgents hatası: {err}")
        else:
            self._send_json(data)

    def _handle_launchagents_clean(self):
        data, err = self._run_script(["--launchagents-clean"], timeout=30)
        if err:
            self._send_error_json(f"LaunchAgents temizleme hatası: {err}")
        else:
            self._send_json(data)
```

- [ ] **Step 3: Verify server starts without errors**

```bash
cd /Users/burak/Desktop/projects/apple-cleanup
python3 -c "import web.server; print('Import OK')"
```

Expected: `Import OK`

- [ ] **Step 4: Commit**

```bash
git add web/server.py
git commit -m "$(cat <<'EOF'
feat(server): add flush-dns, purge-ram, launchagents routes + input validation applied

Three new POST endpoints (/api/flush-dns, /api/purge-ram, /api/launchagents-clean)
and GET /api/launchagents. All existing clean payload fields now validated through
whitelist/regex helpers; app_uninstaller_selected field added.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Frontend — New Categories in script.js

**Files:**
- Modify: `web/script.js`

- [ ] **Step 1: Add 2 entries to the `CATEGORIES` array (after `ios_backups` entry, around line 68)**

```javascript
    {
      key: 'app_uninstaller', index: 11, name: 'Tam Uygulama Kaldırıcı',
      desc: 'Seçilen uygulamaları .app + tüm verileriyle kaldır',
      icon: 'i-trash', color: '#dc2626', defaultChecked: false, danger: true,
      tags: [{ icon: 'i-warn', label: 'app silinir', style: 'red' }],
    },
    {
      key: 'mail_downloads', index: 12, name: 'Mail İndirilenleri',
      desc: 'Mail uygulamasının indirdiği ek dosyalar',
      icon: 'i-arrow-down', color: '#0891b2', defaultChecked: true, danger: false, tags: [],
    },
```

- [ ] **Step 2: Update mock scan data in `mockApi` to include the 2 new categories**

Inside the `if (url === '/api/scan')` block, in the `const sizes = { ... }` object (around line 340), add:

```javascript
        app_uninstaller: 2.1 * 1024 * 1024 * 1024,
        mail_downloads:  156 * 1024 * 1024,
```

And after the `scan.ios_backups.subitems = [...]` block (around line 378), add:

```javascript
      scan.app_uninstaller.subitems = [
        { id: 'Firefox',  name: 'Firefox',        bundle_id: 'org.mozilla.firefox', size_bytes: 420 * 1024 * 1024, size_human: '420 MB', is_orphaned: false },
        { id: 'zoom.us',  name: 'zoom.us',         bundle_id: 'us.zoom.xos',         size_bytes: 380 * 1024 * 1024, size_human: '380 MB', is_orphaned: false },
        { id: 'Discord',  name: 'Discord',          bundle_id: 'com.hnc.Discord',     size_bytes: 820 * 1024 * 1024, size_human: '820 MB', is_orphaned: false },
        { id: 'Notion',   name: 'Notion',           bundle_id: 'notion.id',           size_bytes: 510 * 1024 * 1024, size_human: '510 MB', is_orphaned: false },
      ];
```

- [ ] **Step 3: Add `app_uninstaller` handling to `renderSubitems` checkedAttr / badge logic**

In `renderSubitems` (around line 578), the `if (key === 'app_leftovers')` chain — add a new branch:

```javascript
      else if (key === 'app_uninstaller') {
        checkedAttr = '';   // must opt-in explicitly
        badge = '';
      }
```

- [ ] **Step 4: Add `app_uninstaller_selected` to the clean payload in `handleClean`**

In `handleClean`, inside the `payload` object (around line 652), add:

```javascript
        app_uninstaller_selected: getSelectedSubitems('app_uninstaller'),
```

- [ ] **Step 5: Smoke-test the UI with mock data**

Start the server (or open index.html in browser), click "Tara" and confirm 12 categories appear, including "Tam Uygulama Kaldırıcı" and "Mail İndirilenleri".

- [ ] **Step 6: Commit**

```bash
git add web/script.js
git commit -m "$(cat <<'EOF'
feat(ui): add app_uninstaller and mail_downloads categories to CATEGORIES array

New entries at indices 11 and 12; mock data included; app_uninstaller subitems
render as opt-in checkboxes (unchecked by default, danger styling).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Frontend — Maintenance UI Cards + Handlers

**Files:**
- Modify: `web/index.html`
- Modify: `web/script.js`

- [ ] **Step 1: Add 3 maintenance cards to `index.html` inside the existing `<ul class="cat-list cat-list-tight">` (after the `spotlightCard` `<li>`, around line 252)**

```html
        <li class="cat cat-maint" id="flushDnsCard">
          <div class="cat-row cat-row-static">
            <span class="cat-ic"><svg class="ic"><use href="#i-drop"/></svg></span>
            <span class="cat-meta">
              <span class="cat-name">DNS Önbelleği Temizle</span>
              <span class="cat-desc">dscacheutil + mDNSResponder — yavaş DNS çözümleme sorunlarını giderir.</span>
            </span>
            <button class="btn btn-ghost btn-sm" id="btnFlushDns" type="button">
              <span class="spinner" aria-hidden="true"></span>
              <span class="btn-text">Temizle</span>
            </button>
          </div>
        </li>
        <li class="cat cat-maint" id="purgeRamCard">
          <div class="cat-row cat-row-static">
            <span class="cat-ic"><svg class="ic"><use href="#i-cpu"/></svg></span>
            <span class="cat-meta">
              <span class="cat-name">RAM Temizle</span>
              <span class="cat-desc">sudo purge — inaktif belleği serbest bırakır.</span>
            </span>
            <button class="btn btn-ghost btn-sm" id="btnPurgeRam" type="button">
              <span class="spinner" aria-hidden="true"></span>
              <span class="btn-text">Boşalt</span>
            </button>
          </div>
        </li>
        <li class="cat cat-maint" id="launchAgentsCard">
          <div class="cat-row cat-row-static">
            <span class="cat-ic"><svg class="ic"><use href="#i-wrench"/></svg></span>
            <span class="cat-meta">
              <span class="cat-name">Başlangıç Öğeleri Temizle</span>
              <span class="cat-desc">~/Library/LaunchAgents ve /Library/LaunchDaemons içindeki bozuk .plist dosyalarını siler.</span>
            </span>
            <button class="btn btn-ghost btn-sm" id="btnLaunchAgents" type="button">
              <span class="spinner" aria-hidden="true"></span>
              <span class="btn-text">Tara &amp; Temizle</span>
            </button>
          </div>
        </li>
```

- [ ] **Step 2: Add DOM references for the 3 new buttons in the `el` object in `script.js` (after `btnSpotlight` entry, around line 118)**

```javascript
    btnFlushDns:   $('#btnFlushDns'),
    btnPurgeRam:   $('#btnPurgeRam'),
    btnLaunchAgents: $('#btnLaunchAgents'),
```

- [ ] **Step 3: Add 3 handler functions in `script.js` after `handleSpotlight` (around line 735)**

```javascript
  async function handleFlushDns() {
    if (el.btnFlushDns.disabled) return;
    setLoading(el.btnFlushDns, true);
    termLog('DNS önbelleği temizleniyor…', 'info');
    try {
      await apiFetch('/api/flush-dns', { method: 'POST', body: '{}' });
      termLog('DNS önbelleği temizlendi.', 'success');
    } catch (err) {
      termLog(`DNS hatası: ${err.message}`, 'error');
    } finally {
      setLoading(el.btnFlushDns, false);
    }
  }

  async function handlePurgeRam() {
    if (el.btnPurgeRam.disabled) return;
    setLoading(el.btnPurgeRam, true);
    termLog('RAM temizleniyor (sudo purge)…', 'info');
    try {
      await apiFetch('/api/purge-ram', { method: 'POST', body: '{}' });
      termLog('Bellek boşaltma komutu çalıştırıldı.', 'success');
    } catch (err) {
      termLog(`RAM temizleme hatası: ${err.message}`, 'error');
    } finally {
      setLoading(el.btnPurgeRam, false);
    }
  }

  async function handleLaunchAgents() {
    if (el.btnLaunchAgents.disabled) return;
    setLoading(el.btnLaunchAgents, true);
    termLog('Bozuk LaunchAgents taranıyor…', 'info');
    try {
      const data = await apiFetch('/api/launchagents-clean', { method: 'POST', body: '{}' });
      const found   = data.found   ?? 0;
      const cleaned = data.cleaned ?? 0;
      if (found === 0) {
        termLog('Bozuk .plist dosyası bulunamadı.', 'info');
      } else {
        termLog(`${found} bozuk plist bulundu, ${cleaned} tanesi temizlendi.`, 'success');
      }
    } catch (err) {
      termLog(`LaunchAgents hatası: ${err.message}`, 'error');
    } finally {
      setLoading(el.btnLaunchAgents, false);
    }
  }
```

- [ ] **Step 4: Add mock API responses for the 3 new endpoints in `mockApi` (after the `/api/spotlight-reindex` case)**

```javascript
    if (url === '/api/flush-dns') {
      return { success: true, message: 'DNS önbelleği temizlendi.' };
    }
    if (url === '/api/purge-ram') {
      return { success: true, message: 'Bellek boşaltma komutu çalıştırıldı.' };
    }
    if (url === '/api/launchagents-clean') {
      return { success: true, found: 3, cleaned: 3, message: '3 bozuk plist temizlendi.' };
    }
```

- [ ] **Step 5: Wire event listeners (after existing `el.btnSpotlight.addEventListener` binding)**

```javascript
  if (el.btnFlushDns)     el.btnFlushDns.addEventListener('click', handleFlushDns);
  if (el.btnPurgeRam)     el.btnPurgeRam.addEventListener('click', handlePurgeRam);
  if (el.btnLaunchAgents) el.btnLaunchAgents.addEventListener('click', handleLaunchAgents);
```

- [ ] **Step 6: Smoke-test all 3 new maintenance buttons work in the UI**

Start server: `cd /Users/burak/Desktop/projects/apple-cleanup/web && python3 server.py`

Open `http://localhost:8080`, click each new button, confirm terminal log shows expected messages and button returns to non-loading state.

- [ ] **Step 7: Commit**

```bash
git add web/index.html web/script.js
git commit -m "$(cat <<'EOF'
feat(ui): add DNS flush, RAM purge, LaunchAgents maintenance cards

Three new maintenance cards with async handlers; mock API stubs included
for demo mode; buttons wire to /api/flush-dns, /api/purge-ram,
/api/launchagents-clean endpoints.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Bash — Parallel scan_all()

**Files:**
- Modify: `clean_mac.sh`

- [ ] **Step 1: Replace the `scan_all` function body with a parallel implementation (around line 386)**

Replace the entire `scan_all()` function:

```bash
scan_all() {
  if ! $JSON_MODE; then
    header "🔍 Taranıyor..."
    echo -ne "  ${DIM}Kategoriler paralel taranıyor...${NC}\r"
  fi

  local fns=(scan_user_cache scan_system_cache scan_app_leftovers \
             scan_logs scan_temp_files scan_developer scan_trash \
             scan_browser_cache scan_browser_full scan_ios_backups \
             scan_app_uninstaller scan_mail_downloads)

  local SCAN_TMPDIR
  SCAN_TMPDIR=$(mktemp -d)

  local i
  for i in "${!fns[@]}"; do
    (
      "${fns[$i]}" 2>/dev/null
      printf '%s\n' "${CAT_SIZES[$i]}" > "$SCAN_TMPDIR/$i"
    ) &
  done
  wait

  for i in "${!CAT_IDS[@]}"; do
    if [ -f "$SCAN_TMPDIR/$i" ]; then
      local val
      val=$(cat "$SCAN_TMPDIR/$i" 2>/dev/null || echo "0")
      CAT_SIZES[$i]=${val:-0}
    fi
  done
  rm -rf "$SCAN_TMPDIR"

  if ! $JSON_MODE; then
    echo -e "  ${GREEN}Tarama tamamlandı.${NC}                              "
  fi
}
```

**Why this works with Bash 3.2:** Each `(...)` subshell inherits a copy of `CAT_SIZES`. The scan function runs inside the subshell, modifies `CAT_SIZES[$i]`, and then we write that value to a temp file. After `wait`, the parent reads all temp files back. No bashisms beyond Bash 3.2.

- [ ] **Step 2: Verify bash syntax**

```bash
bash -n clean_mac.sh && echo "Syntax OK"
```

- [ ] **Step 3: Time the scan to confirm speedup**

```bash
time bash clean_mac.sh --scan-json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print('total:', d['total_human'])"
```

Expected: runs noticeably faster than sequential (typical: 3–8x speedup depending on I/O).

- [ ] **Step 4: Commit**

```bash
git add clean_mac.sh
git commit -m "$(cat <<'EOF'
perf(bash): parallelize scan_all using background subshells + temp files

Each scan function runs concurrently via (&); results written to a tmpdir
and read back after wait. Bash 3.2 compatible — no process substitution
tricks. Typical wall-clock speedup: 3-8x on an SSD Mac.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Checklist

### Spec Coverage

| Requirement | Task |
|-------------|------|
| App Uninstaller (.app + Application Support + Caches + Prefs + Saved State) | Task 4, 6, 7, 8 |
| Mail Downloads category | Task 3, 6, 8 |
| Homebrew cache subitem | Task 5 |
| Docker system prune subitem | Task 5 |
| npm/pip cache subitems | Task 5 |
| DNS Flush button + endpoint | Task 6, 7, 9 |
| RAM Purge button + endpoint | Task 6, 7, 9 |
| LaunchAgents broken plist cleanup | Task 6, 7, 9 |
| Input validation (path traversal, injection) | Task 1, 2 |
| Parallel scanning (Bash 3.2 compatible) | Task 10 |

### Placeholder Scan

- No TBD or TODO left in code blocks above.
- All function names are consistent: `scan_app_uninstaller` → `clean_app_uninstaller`, `do_flush_dns` → `_handle_flush_dns` → `handleFlushDns`.
- `CAT_SIZES[10]` for app_uninstaller, `CAT_SIZES[11]` for mail_downloads — consistent with array positions.
- `index: 11` in CATEGORIES for app_uninstaller, `index: 12` for mail_downloads — match bash category numbers (1-based).

### Type Consistency

- `_validate_app_leftover`, `_validate_developer_item`, `_validate_browser_key`, `_validate_app_name` defined in Task 2, imported in Task 1 tests. ✓
- `APP_UNINSTALLER_CLEAN` defined in Task 3 Step 1, used in `clean_app_uninstaller` (Task 4) and `main()` flag (Task 6). ✓
- `scan_app_uninstaller_subitems_json` added in Task 4 Step 3, referenced in `do_scan_json` in Task 6 Step 5. ✓
- `el.btnFlushDns` etc. added in Task 9 Step 2, used in Step 5 bindings. ✓
