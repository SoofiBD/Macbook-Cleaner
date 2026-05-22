# Clean Mac Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add iOS Backup scanning/cleanup, async Spotlight re-indexing, hardened security filter, and matching web UI cards to the Clean Mac tool.

**Architecture:** Shell script gains a new 10th category (`ios_backups`) plus a fire-and-forget `--spotlight-reindex` flag. Server.py routes the new POST endpoint and new payload field. Frontend adds a category card and a maintenance section outside the grid.

**Tech Stack:** Bash 3.2+, Python 3 stdlib (http.server), vanilla JS/HTML/CSS — no new dependencies.

---

## File Map

| File | Change |
|------|--------|
| `clean_mac.sh` | +arrays entry, +4 functions, +2 flags, update scan_all/run_clean/do_scan_json/do_clean_json/main |
| `web/server.py` | +1 endpoint, +ios_backups_selected handling in _handle_clean |
| `web/index.html` | +1 category card, +1 maintenance section |
| `web/style.css` | +maintenance section & btn-maintenance styles |
| `web/script.js` | +CATEGORY_MAP entry, +ios_backups subitem rendering, +Spotlight handler |

---

## Task 1: Shell — Extend arrays and add iOS Backups scan/clean

**Files:**
- Modify: `clean_mac.sh`

- [ ] **Step 1: Add `IOS_BACKUPS_CLEAN` variable near the other JSON-mode vars (line ~29)**

After the line `DEVELOPER_CLEAN=""`, add:
```bash
IOS_BACKUPS_CLEAN=""
```

- [ ] **Step 2: Extend the four parallel arrays to 10 entries**

Replace the four array declarations (lines ~62-67):
```bash
CAT_IDS=(user_cache system_cache app_leftovers logs temp_files developer trash browser_cache browser_full ios_backups)
CAT_NAMES=("Kullanıcı Cache" "Sistem Cache" "Uygulama Kalıntıları" \
            "Loglar" "Geçici Dosyalar" "Geliştirici" "Çöp Kutusu" \
            "Tarayıcı Cache" "Tarayıcı Tüm Veri" "iOS Yedekleri")
CAT_SIZES=(0 0 0 0 0 0 0 0 0 0)
CAT_NEEDS_SUDO=(0 1 0 0 0 0 0 0 0 0)
```

- [ ] **Step 3: Add `scan_ios_backups` function after `scan_browser_full`**

```bash
scan_ios_backups() {
  local backup_dir="$HOME/Library/MobileSync/Backup"
  local s=0
  if [ -d "$backup_dir" ]; then
    s=$(get_dir_size_bytes "$backup_dir") || s=0
  fi
  CAT_SIZES[9]=$s
}
```

- [ ] **Step 4: Add `scan_ios_backups_subitems_json` after `scan_browser_full_subitems_json`**

```bash
scan_ios_backups_subitems_json() {
  local backup_dir="$HOME/Library/MobileSync/Backup"
  [ -d "$backup_dir" ] || return
  local first=true
  local item base s sz_h mod_date esc_base esc_path esc_name display_name
  while IFS= read -r -d '' item; do
    [ -d "$item" ] || continue
    base=$(basename "$item")
    s=$(get_size_bytes "$item") || s=0
    [ "$s" -le 0 ] && continue
    sz_h=$(format_bytes "$s")
    mod_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$item" 2>/dev/null || echo "Bilinmiyor")
    display_name="$base ($mod_date)"
    esc_base=$(json_escape_str "$base")
    esc_path=$(json_escape_str "$item")
    esc_name=$(json_escape_str "$display_name")
    if [ "$first" = true ]; then
      first=false
    else
      echo ","
    fi
    echo -n "        {\"id\": \"$esc_base\", \"name\": \"$esc_name\", \"path\": \"$esc_path\", \"size_bytes\": $s, \"size_human\": \"$sz_h\", \"is_orphaned\": true}"
  done < <(find "$backup_dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)
}
```

- [ ] **Step 5: Add `clean_ios_backups` function after `clean_browser_full`**

```bash
clean_ios_backups() {
  header "📱 iOS Yedekleri Temizleniyor"
  local backup_dir="$HOME/Library/MobileSync/Backup"

  if $JSON_MODE; then
    if [ -z "$IOS_BACKUPS_CLEAN" ]; then
      info "Temizlenecek yedek belirtilmedi, atlanıyor."
      return
    fi
    local IFS_OLD="$IFS"
    IFS=','
    local clean_uuids=($IOS_BACKUPS_CLEAN)
    IFS="$IFS_OLD"
    local uuid
    for uuid in ${clean_uuids[@]+"${clean_uuids[@]}"}; do
      local full_path="$backup_dir/$uuid"
      if [ -d "$full_path" ]; then
        safe_rm "$full_path" "iOS Yedeği: $uuid"
      fi
    done
    return
  fi

  # Interactive CLI Mode
  if [ ! -d "$backup_dir" ]; then
    info "iOS yedekleri bulunamadı."
    return
  fi

  echo ""
  local item base sz_b sz_h mod_date idx=1
  local backup_paths=()
  local backup_names=()
  while IFS= read -r -d '' item; do
    [ -d "$item" ] || continue
    base=$(basename "$item")
    sz_b=$(get_size_bytes "$item") || sz_b=0
    sz_h=$(format_bytes "$sz_b")
    mod_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$item" 2>/dev/null || echo "Bilinmiyor")
    printf "  ${GREEN}%-3d${NC}  %-40s  %-8s  %s\n" "$idx" "$base" "$sz_h" "$mod_date"
    backup_paths+=("$item")
    backup_names+=("$base")
    idx=$((idx + 1))
  done < <(find "$backup_dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)

  if [ "${#backup_paths[@]}" -eq 0 ]; then
    info "Temizlenecek iOS yedeği bulunamadı."
    return
  fi

  echo ""
  echo -ne "  Numara girin (boşlukla), ${BOLD}all${NC} veya ${BOLD}none${NC}: "
  local selection; read -r selection

  if [ "$selection" = "none" ] || [ -z "$selection" ]; then
    info "iOS yedekleri atlandı."
    return
  fi

  local indices=()
  if [ "$selection" = "all" ]; then
    local j; for j in "${!backup_paths[@]}"; do indices+=("$((j+1))"); done
  else
    read -ra indices <<< "$selection"
  fi

  for num in ${indices[@]+"${indices[@]}"}; do
    local real_idx=$((num - 1))
    if [ "$real_idx" -ge 0 ] && [ "$real_idx" -lt "${#backup_paths[@]}" ]; then
      safe_rm "${backup_paths[$real_idx]}" "iOS Yedeği: ${backup_names[$real_idx]}"
    fi
  done
}
```

- [ ] **Step 6: Update `scan_all` to include `scan_ios_backups`**

Replace:
```bash
  local fns=(scan_user_cache scan_system_cache scan_app_leftovers \
             scan_logs scan_temp_files scan_developer scan_trash \
             scan_browser_cache scan_browser_full)
```
With:
```bash
  local fns=(scan_user_cache scan_system_cache scan_app_leftovers \
             scan_logs scan_temp_files scan_developer scan_trash \
             scan_browser_cache scan_browser_full scan_ios_backups)
```

- [ ] **Step 7: Update `fn_map` in `run_clean` to include `clean_ios_backups`**

Replace:
```bash
  local fn_map=(clean_user_cache clean_system_cache clean_app_leftovers \
                clean_logs clean_temp_files clean_developer clean_trash \
                clean_browser_cache clean_browser_full)
```
With:
```bash
  local fn_map=(clean_user_cache clean_system_cache clean_app_leftovers \
                clean_logs clean_temp_files clean_developer clean_trash \
                clean_browser_cache clean_browser_full clean_ios_backups)
```

- [ ] **Step 8: Update `do_scan_json` to emit ios_backups subitems**

Inside `do_scan_json`, after the `elif [ "$id" = "browser_full" ]` block (around line ~993), add:
```bash
    elif [ "$id" = "ios_backups" ]; then
      echo "      ,\"subitems\": ["
      scan_ios_backups_subitems_json
      echo ""
      echo "      ]"
    fi
```

- [ ] **Step 9: Update `fn_map` in `do_clean_json` to include `clean_ios_backups`**

Replace the `fn_map` inside `do_clean_json` (same pattern as run_clean):
```bash
  local fn_map=(clean_user_cache clean_system_cache clean_app_leftovers \
                clean_logs clean_temp_files clean_developer clean_trash \
                clean_browser_cache clean_browser_full clean_ios_backups)
```

- [ ] **Step 10: Add `--ios-backups-sub` flag in `main` argument parser**

After the `--developer-sub` case block, add:
```bash
      --ios-backups-sub)
        i=$((i + 1))
        IOS_BACKUPS_CLEAN="${args[$i]}"
        ;;
```

- [ ] **Step 11: Verify JSON output**

Run:
```bash
cd /Users/burak/Desktop/projects/apple-cleanup
bash clean_mac.sh --scan-json | python3 -m json.tool | grep -A5 '"ios_backups"'
```
Expected: `"ios_backups"` key present with `size_bytes`, `size_human`, `subitems` fields.

- [ ] **Step 12: Commit**

```bash
git add clean_mac.sh
git commit -m "feat(shell): add ios_backups category (#10) with scan/clean/JSON functions"
```

---

## Task 2: Shell — Spotlight re-indexing

**Files:**
- Modify: `clean_mac.sh`

- [ ] **Step 1: Add `do_spotlight_reindex` function after `do_status_json`**

```bash
do_spotlight_reindex() {
  (sudo mdutil -i off / 2>/dev/null
   sudo mdutil -i on  / 2>/dev/null
   sudo mdutil -E    / 2>/dev/null) &
  echo '{"success": true, "status": "started", "message": "Spotlight yeniden indeksleme arka planda başlatıldı."}'
}
```

- [ ] **Step 2: Add `--spotlight-reindex` flag in `main` argument parser**

After the `--status-json` case, add:
```bash
      --spotlight-reindex)
        do_spotlight_reindex
        exit 0
        ;;
```

- [ ] **Step 3: Verify**

Run:
```bash
bash clean_mac.sh --spotlight-reindex
```
Expected output (immediately, no hang):
```json
{"success": true, "status": "started", "message": "Spotlight yeniden indeksleme arka planda başlatıldı."}
```

- [ ] **Step 4: Commit**

```bash
git add clean_mac.sh
git commit -m "feat(shell): add --spotlight-reindex async flag"
```

---

## Task 3: Shell — Harden `is_app_installed` security filter

**Files:**
- Modify: `clean_mac.sh`

- [ ] **Step 1: Replace the `case` pattern in `is_app_installed`**

Current code (lines ~244-248):
```bash
  case "$dir_name" in
    Apple|com.apple.*|Google|com.google.*|Microsoft|com.microsoft.*|Adobe|com.adobe.*|Helper|CrashReporter|MobileSync|SyncServices|Oracle|com.oracle.*|Homebrew)
      return 0
      ;;
  esac
```

Replace with:
```bash
  case "$dir_name" in
    Apple|com.apple.*|com.google.*|com.microsoft.*|com.adobe.*|\
    com.oracle.*|Homebrew|\
    Helper|CrashReporter|MobileSync|SyncServices|\
    Audio|Fonts|Compositions|ColorSync|Spelling|Dictionaries|\
    AddressBook|Calendars|Mail|Messages|Safari|\
    CallHistoryDB|CallHistoryTransactions|CloudDocs|Dock|\
    iCloud|Knowledge|Network|VirtualMachines|DiskImages|\
    "Input Methods"|"Keyboard Layouts"|"Final Cut"|"Final Cut Pro X")
      return 0
      ;;
  esac
```

Also update `scan_app_leftovers` skip list to match. Find the line:
```bash
      com.apple.*|Apple|MobileSync|SyncServices|CrashReporter) continue ;;
```
Replace with:
```bash
      com.apple.*|Apple|MobileSync|SyncServices|CrashReporter|\
      Audio|Fonts|Compositions|ColorSync|Spelling|Dictionaries|\
      AddressBook|Calendars|Mail|Messages|Safari|\
      CallHistoryDB|CallHistoryTransactions|CloudDocs|Dock|\
      iCloud|Knowledge|Network|VirtualMachines|DiskImages) continue ;;
```

And the same in `clean_app_leftovers` interactive CLI mode (second identical skip block):
```bash
      com.apple.*|Apple|MobileSync|SyncServices|CrashReporter|\
      Audio|Fonts|Compositions|ColorSync|Spelling|Dictionaries|\
      AddressBook|Calendars|Mail|Messages|Safari|\
      CallHistoryDB|CallHistoryTransactions|CloudDocs|Dock|\
      iCloud|Knowledge|Network|VirtualMachines|DiskImages) continue ;;
```

- [ ] **Step 2: Verify scan_app_leftovers_subitems_json also uses the updated filter**

`scan_app_leftovers_subitems_json` has its own skip line (line ~858):
```bash
      com.apple.*|Apple|MobileSync|SyncServices|CrashReporter) continue ;;
```
Replace with:
```bash
      com.apple.*|Apple|MobileSync|SyncServices|CrashReporter|\
      Audio|Fonts|Compositions|ColorSync|Spelling|Dictionaries|\
      AddressBook|Calendars|Mail|Messages|Safari|\
      CallHistoryDB|CallHistoryTransactions|CloudDocs|Dock|\
      iCloud|Knowledge|Network|VirtualMachines|DiskImages) continue ;;
```

- [ ] **Step 3: Verify**

Run:
```bash
bash clean_mac.sh --scan-json | python3 -m json.tool | python3 -c "
import json, sys
d = json.load(sys.stdin)
items = d['scan']['app_leftovers'].get('subitems', [])
print('Total app_leftovers subitems:', len(items))
protected = [i for i in items if i['name'] in ['Audio','Fonts','Compositions']]
print('Protected dirs leaked (should be 0):', len(protected))
"
```
Expected: `Protected dirs leaked: 0`

- [ ] **Step 4: Commit**

```bash
git add clean_mac.sh
git commit -m "fix(shell): harden is_app_installed to protect Apple system dirs (Audio, Fonts, etc.)"
```

---

## Task 4: server.py — ios_backups payload + Spotlight endpoint

**Files:**
- Modify: `web/server.py`

- [ ] **Step 1: Add `ios_backups_selected` extraction in `_handle_clean`**

After the `developer_selected` block (around line ~144), add:
```python
        ios_backups_selected = payload.get("ios_backups_selected", [])
        if ios_backups_selected and isinstance(ios_backups_selected, list):
            args += ["--ios-backups-sub", ",".join(str(x) for x in ios_backups_selected)]
```

- [ ] **Step 2: Add Spotlight route in `do_POST`**

Replace:
```python
    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/clean":
            self._handle_clean()
        else:
            self._send_error_json("Not found", 404)
```
With:
```python
    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/clean":
            self._handle_clean()
        elif parsed.path == "/api/spotlight-reindex":
            self._handle_spotlight_reindex()
        else:
            self._send_error_json("Not found", 404)
```

- [ ] **Step 3: Add `_handle_spotlight_reindex` method after `_handle_clean`**

```python
    def _handle_spotlight_reindex(self):
        data, err = self._run_script(["--spotlight-reindex"], timeout=10)
        if err:
            self._send_error_json(f"Spotlight hatası: {err}")
        else:
            self._send_json(data)
```

- [ ] **Step 4: Verify with curl (server must be running)**

Start server in background: `cd web && python3 server.py &`

```bash
curl -s -X POST http://localhost:8080/api/spotlight-reindex \
  -H "Content-Type: application/json" -d '{}' | python3 -m json.tool
```
Expected:
```json
{"success": true, "status": "started", "message": "Spotlight yeniden indeksleme arka planda başlatıldı."}
```

Stop server: `kill %1`

- [ ] **Step 5: Commit**

```bash
git add web/server.py
git commit -m "feat(server): add /api/spotlight-reindex endpoint and ios_backups_selected routing"
```

---

## Task 5: index.html — iOS Backups card + Maintenance section

**Files:**
- Modify: `web/index.html`

- [ ] **Step 1: Add iOS Backups card inside `#cardsGrid` after the `browser_full` card**

After the closing `</div>` of the `browser_full` card (before `</div>` that closes `.cards-grid`), add:
```html
        <!-- Card: ios_backups -->
        <div class="category-card card-enter card-danger" data-category="ios_backups" data-index="10" role="listitem">
          <div class="card-top">
            <div style="display:flex;align-items:center;gap:14px">
              <div class="card-icon-wrap" aria-hidden="true">📱</div>
              <div class="card-info">
                <div class="card-name">iOS Yedekleri</div>
                <div class="card-desc">iPhone/iPad MobileSync yedekleri</div>
                <div class="card-warn-label">Silmeden önce kontrol edin!</div>
              </div>
            </div>
            <label class="toggle-switch">
              <input type="checkbox" aria-label="iOS Yedekleri seç">
              <span class="toggle-slider"></span>
            </label>
          </div>
          <div class="card-meta">
            <div class="card-size">
              <span class="size-badge" data-size="ios_backups">— Taranmadı</span>
            </div>
          </div>
        </div>
```

- [ ] **Step 2: Add Maintenance section between `</main>` and `<!-- ═══ Action Buttons ═══ -->`**

```html
    <!-- ═══ Maintenance Section ═══ -->
    <section class="maintenance-section" aria-label="Sistem bakım araçları">
      <div class="maintenance-header">
        <span class="maintenance-icon" aria-hidden="true">🔧</span>
        <div>
          <div class="maintenance-title">Sistem Bakımı</div>
          <div class="maintenance-subtitle">Temizlik dışı onarım araçları — seçim gerektirmez</div>
        </div>
      </div>
      <div class="maintenance-cards">
        <div class="maintenance-card" id="spotlightCard">
          <div class="maintenance-card-left">
            <span class="maintenance-card-icon" aria-hidden="true">🔦</span>
            <div class="maintenance-card-info">
              <div class="maintenance-card-name">Spotlight İndeksini Yenile</div>
              <div class="maintenance-card-desc">
                Disk alanının yanlış gösterilmesi (hayalet veri) sorununu çözer.
                Arka planda çalışır, birkaç dakika sürebilir. macOS yeniden tarar.
              </div>
            </div>
          </div>
          <button class="btn-maintenance" id="btnSpotlight" type="button">
            <span class="spinner" aria-hidden="true"></span>
            <span class="btn-text">🔦 Yenile</span>
          </button>
        </div>
      </div>
    </section>
```

- [ ] **Step 3: Commit**

```bash
git add web/index.html
git commit -m "feat(ui): add iOS Backups card (#10) and Spotlight maintenance section"
```

---

## Task 6: style.css — Maintenance section styles

**Files:**
- Modify: `web/style.css`

- [ ] **Step 1: Append maintenance section styles at the end of the file**

```css
/* ── Maintenance Section ────────────────────────────────── */
.maintenance-section {
  margin-bottom: 24px;
  background: var(--bg-card);
  backdrop-filter: blur(20px) saturate(1.6);
  -webkit-backdrop-filter: blur(20px) saturate(1.6);
  border: 1px solid var(--bg-glass-border);
  border-radius: var(--radius);
  padding: 20px 24px;
  box-shadow: var(--shadow-card);
}

.maintenance-header {
  display: flex;
  align-items: center;
  gap: 14px;
  margin-bottom: 16px;
}

.maintenance-icon {
  font-size: 1.5rem;
  line-height: 1;
}

.maintenance-title {
  font-size: 1rem;
  font-weight: 700;
  color: var(--text-primary);
}

.maintenance-subtitle {
  font-size: .8rem;
  color: var(--text-tertiary);
  margin-top: 2px;
}

.maintenance-cards {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.maintenance-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 16px 18px;
  background: var(--bg-glass);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  transition: background var(--duration) var(--ease),
              border-color var(--duration) var(--ease);
}

.maintenance-card:hover {
  background: var(--bg-card-hover);
  border-color: var(--border-hover);
}

.maintenance-card-left {
  display: flex;
  align-items: center;
  gap: 14px;
  flex: 1;
  min-width: 0;
}

.maintenance-card-icon {
  font-size: 1.5rem;
  line-height: 1;
  flex-shrink: 0;
}

.maintenance-card-info {
  min-width: 0;
}

.maintenance-card-name {
  font-size: .95rem;
  font-weight: 600;
  color: var(--text-primary);
  margin-bottom: 3px;
}

.maintenance-card-desc {
  font-size: .8rem;
  color: var(--text-secondary);
  line-height: 1.5;
}

.btn-maintenance {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 10px 20px;
  background: var(--bg-glass);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-primary);
  font-family: var(--font);
  font-size: .85rem;
  font-weight: 600;
  cursor: pointer;
  transition: all var(--duration) var(--ease);
  flex-shrink: 0;
  white-space: nowrap;
  position: relative;
  overflow: hidden;
}

.btn-maintenance:hover:not(:disabled) {
  background: var(--accent);
  border-color: var(--accent);
  color: #fff;
  box-shadow: 0 4px 16px var(--accent-glow);
  transform: translateY(-1px);
}

.btn-maintenance:disabled {
  opacity: .5;
  cursor: not-allowed;
  transform: none;
}

.btn-maintenance.loading .btn-text {
  opacity: 0;
}

.btn-maintenance.loading .spinner {
  opacity: 1;
}

.btn-maintenance .spinner {
  opacity: 0;
  position: absolute;
  left: 50%;
  top: 50%;
  transform: translate(-50%, -50%);
}

@media (max-width: 600px) {
  .maintenance-card {
    flex-direction: column;
    align-items: flex-start;
  }
  .btn-maintenance {
    width: 100%;
    justify-content: center;
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add web/style.css
git commit -m "feat(styles): add maintenance section and btn-maintenance styles"
```

---

## Task 7: script.js — CATEGORY_MAP, subitem rendering, Spotlight handler

**Files:**
- Modify: `web/script.js`

- [ ] **Step 1: Add `ios_backups` to `CATEGORY_MAP`**

In the `CATEGORY_MAP` object, after `browser_full`, add:
```javascript
    ios_backups:   { index: 10, name: 'iOS Yedekleri (MobileSync)' },
```

- [ ] **Step 2: Add `ios_backups` subitem rendering case in `handleScan`**

In the `checkedAttr` logic block inside `handleScan`, add a case for `ios_backups`. Current block:
```javascript
              let checkedAttr = '';
              if (key === 'app_leftovers') {
                checkedAttr = sub.is_orphaned ? 'checked' : '';
              } else if (key === 'developer') {
                checkedAttr = 'checked';
              } else if (key === 'browser_full') {
                checkedAttr = '';
              }
```
Replace with:
```javascript
              let checkedAttr = '';
              if (key === 'app_leftovers') {
                checkedAttr = sub.is_orphaned ? 'checked' : '';
              } else if (key === 'developer') {
                checkedAttr = 'checked';
              } else if (key === 'browser_full') {
                checkedAttr = '';
              } else if (key === 'ios_backups') {
                checkedAttr = '';
              }
```

- [ ] **Step 3: Add `ios_backups` badge in the `badgeHtml` block**

Current block:
```javascript
              let badgeHtml = '';
              if (key === 'app_leftovers') {
                const label = sub.is_orphaned ? 'Kalıntı' : 'Yüklü';
                const cls = sub.is_orphaned ? 'orphaned' : 'installed';
                badgeHtml = `<span class="subitem-badge ${cls}">${label}</span>`;
              }
```
Replace with:
```javascript
              let badgeHtml = '';
              if (key === 'app_leftovers') {
                const label = sub.is_orphaned ? 'Kalıntı' : 'Yüklü';
                const cls = sub.is_orphaned ? 'orphaned' : 'installed';
                badgeHtml = `<span class="subitem-badge ${cls}">${label}</span>`;
              } else if (key === 'ios_backups') {
                badgeHtml = `<span class="subitem-badge orphaned">Yedek</span>`;
              }
```

- [ ] **Step 4: Add `ios_backups_selected` to the clean payload**

In `handleClean`, after `const developerSelected = getSelectedSubitems('developer');`, add:
```javascript
      const iosBackupsSelected = getSelectedSubitems('ios_backups');
```

In the `apiFetch` body, after `developer_selected: developerSelected,`, add:
```javascript
          ios_backups_selected: iosBackupsSelected,
```

- [ ] **Step 5: Add `handleSpotlightReindex` function before the Card Toggle section**

```javascript
  /* ── Spotlight Reindex ──────────────────────────────────── */
  async function handleSpotlightReindex() {
    const btn = $('#btnSpotlight');
    if (!btn || btn.disabled) return;
    btn.classList.add('loading');
    btn.disabled = true;
    termLog('Spotlight yeniden indeksleme tetikleniyor…', 'info');
    try {
      await apiFetch('/api/spotlight-reindex', { method: 'POST', body: '{}' });
      termLog('Spotlight indeksleme arka planda başlatıldı. Birkaç dakika sürebilir.', 'success');
    } catch (err) {
      termLog(`Spotlight hatası: ${err.message}`, 'error');
    } finally {
      btn.classList.remove('loading');
      btn.disabled = false;
    }
  }
```

- [ ] **Step 6: Wire up the Spotlight button after the existing button handlers**

After `btnClean.addEventListener('click', handleClean);`, add:
```javascript
  const btnSpotlight = $('#btnSpotlight');
  if (btnSpotlight) {
    btnSpotlight.addEventListener('click', handleSpotlightReindex);
  }
```

- [ ] **Step 7: Update `cards` query to pick up the new card**

The existing `const cards = $$('.category-card');` query is dynamic — it runs at page load and picks up all cards including the new `ios_backups` card. No change needed here.

- [ ] **Step 8: Verify in browser**

Start server: `cd web && python3 server.py`
Open: `http://localhost:8080`

Check:
1. Cards grid shows 10 cards including "iOS Yedekleri" with 📱 icon
2. Maintenance section appears below the grid with "🔦 Yenile" button
3. Click "🔍 Tara" — iOS Backups card shows a size badge, subitems appear with "Yedek" badge
4. Click "🔦 Yenile" — button shows spinner briefly, terminal logs success message
5. Select ios_backups subitems → click "🧹 Temizle" → confirm → ios_backups detail chip appears in results

- [ ] **Step 9: Commit**

```bash
git add web/script.js
git commit -m "feat(ui): wire ios_backups subitems and Spotlight reindex handler in script.js"
```
