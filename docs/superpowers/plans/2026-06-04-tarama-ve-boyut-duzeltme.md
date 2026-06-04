# Tarama Derinliği ve Boyut Hesabı Düzeltmesi — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tarama toplamındaki çift sayımı ortadan kaldır, "kazanılan alan"ı gerçek `df` farkından raporla, ve geliştirici/sistem/snapshot tarama derinliğini açık kaynak temizleyicilere yakınlaştır.

**Architecture:** `clean_mac.sh` içindeki paralel kategori dizileri tek bir pipe-ayrılmış `CATEGORIES` registry'sinden türetilir (bash 3.2 uyumlu); manşet TOPLAM yalnızca `in_total=1` kategorileri sayar; `do_clean_json` gerçek kazancı `df` farkıyla ölçer; yeni kategori/alt-öğeler registry'ye satır eklenerek büyür. Web tarafı (server.py + script.js) yeni id'leri/risk rozetlerini yansıtır.

**Tech Stack:** bash 3.2 (clean_mac.sh), Python 3 stdlib http.server (web/server.py), vanilla JS (web/script.js), pytest (tests/).

---

## Dosya Yapısı

- **`clean_mac.sh`** — Tüm tarama/temizlik mantığı. Bu planda: registry refactor (66-73), `get_dir_size_bytes` (112-123), `scan_app_leftovers` (293-310), TOPLAM hesapları (449, 1322), `do_scan_json` (1316+), `do_clean_json` (1389+), yeni `scan_/clean_` fonksiyonları, yeni `--thin-snapshots` argümanı.
- **`web/server.py`** — Doğrulama whitelist'leri (33-56), `_handle_clean` (154+), yeni `/api/thin-snapshots` route.
- **`web/script.js`** — freed gösterimi (711-728), risk rozetleri, danger onayı, snapshot maintenance kartı.
- **`web/index.html` / `web/style.css`** — Risk rozeti ve snapshot kartı markup/stil.
- **`tests/test_clean_mac.py`** — YENİ. Script'i geçici `HOME` ile çağırıp tarama/freed davranışını doğrular.
- **`tests/test_server_validation.py`** — Yeni whitelist anahtarları için testler eklenir.

---

## FAZ 1 — Muhasebe Düzeltmeleri (Problem 1 & 2)

### Task 1: Test altyapısı — geçici HOME ile script çağıran pytest fixture

**Files:**
- Create: `tests/test_clean_mac.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_clean_mac.py
import json
import os
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "clean_mac.sh"


def run_scan(home: Path) -> dict:
    """clean_mac.sh --scan-json'u izole bir HOME ile çalıştır, JSON döndür."""
    env = dict(os.environ, HOME=str(home))
    out = subprocess.run(
        ["bash", str(SCRIPT), "--scan-json"],
        env=env, capture_output=True, text=True, timeout=60,
    )
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


def make_dir_with_bytes(path: Path, kb: int) -> None:
    """path altında ~kb kilobayt veri oluştur."""
    path.mkdir(parents=True, exist_ok=True)
    (path / "blob.bin").write_bytes(b"x" * (kb * 1024))


def test_scan_json_has_required_keys(tmp_path):
    data = run_scan(tmp_path)
    assert data["success"] is True
    assert "scan" in data
    assert "total_bytes" in data
    # Her kategori size_bytes alanı taşımalı
    for cat_id, info in data["scan"].items():
        assert "size_bytes" in info, cat_id
```

- [ ] **Step 2: Run test to verify it passes (baseline)**

Run: `cd /Users/burak/Desktop/projects/apple-cleanup && python -m pytest tests/test_clean_mac.py -v`
Expected: PASS (mevcut script zaten geçerli JSON üretir; bu test altyapıyı doğrular).

- [ ] **Step 3: Commit**

```bash
git add tests/test_clean_mac.py
git commit -m "test: add isolated-HOME harness for clean_mac.sh scan output"
```

---

### Task 2: Kategori registry'si (geriye-uyumlu)

Paralel dizileri tek `CATEGORIES` registry'sinden türet. Mevcut indeks-tabanlı erişim (`CAT_IDS[$i]` vb.) bozulmadan kalsın; ek olarak `CAT_RISKS` ve `CAT_IN_TOTAL` türet.

**Files:**
- Modify: `clean_mac.sh:65-73`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_clean_mac.py içine ekle
def test_app_uninstaller_excluded_from_total(tmp_path):
    # app_uninstaller (in_total=0) yalnız bir alt-öğe üretebilir ama
    # total_bytes'a EKLENMEMELİ. Burada user_cache'e 2MB koyup
    # toplamın yalnızca onu içerdiğini doğruluyoruz.
    make_dir_with_bytes(tmp_path / "Library/Caches/com.example.app", kb=2048)
    data = run_scan(tmp_path)
    uninstaller = data["scan"].get("app_uninstaller", {})
    # app_uninstaller bytes'ı varsa bile total'a dahil olmamalı
    assert data["total_bytes"] >= uninstaller.get("size_bytes", 0)
    summed_in_total = sum(
        info["size_bytes"] for cid, info in data["scan"].items()
        if cid != "app_uninstaller"
    )
    assert data["total_bytes"] == summed_in_total
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_clean_mac.py::test_app_uninstaller_excluded_from_total -v`
Expected: FAIL — mevcut `do_scan_json` tüm kategorileri toplar, app_uninstaller dahil.

- [ ] **Step 3: Replace parallel arrays with registry**

`clean_mac.sh:65-73` aralığını şununla değiştir:

```bash
# ─── Kategori Registry'si (bash 3.2 uyumlu: tek dizi, pipe-ayrılmış satırlar) ──
# Format: id|ad|scan_fn|clean_fn|needs_sudo|risk|in_total
#   risk:     safe | caution | danger
#   in_total: 1 → manşet TOPLAM'a girer, 0 → girmez (örtüşen/interaktif seçici)
CATEGORIES=(
  "user_cache|Kullanıcı Cache|scan_user_cache|clean_user_cache|0|safe|1"
  "system_cache|Sistem Cache|scan_system_cache|clean_system_cache|1|safe|1"
  "app_leftovers|Uygulama Kalıntıları|scan_app_leftovers|clean_app_leftovers|0|caution|1"
  "logs|Loglar|scan_logs|clean_logs|0|safe|1"
  "temp_files|Geçici Dosyalar|scan_temp_files|clean_temp_files|0|safe|1"
  "developer|Geliştirici|scan_developer|clean_developer|0|caution|1"
  "trash|Çöp Kutusu|scan_trash|clean_trash|0|safe|1"
  "browser_cache|Tarayıcı Cache|scan_browser_cache|clean_browser_cache|0|safe|1"
  "browser_full|Tarayıcı Tüm Veri|scan_browser_full|clean_browser_full|0|danger|1"
  "ios_backups|iOS Yedekleri|scan_ios_backups|clean_ios_backups|0|caution|1"
  "app_uninstaller|Tam Uygulama Kaldırıcı|scan_app_uninstaller|clean_app_uninstaller|0|caution|0"
  "mail_downloads|Mail İndirilenleri|scan_mail_downloads|clean_mail_downloads|0|safe|1"
)

# Registry'den paralel dizileri türet (mevcut indeks-tabanlı kod korunur)
CAT_IDS=(); CAT_NAMES=(); CAT_NEEDS_SUDO=(); CAT_RISKS=(); CAT_IN_TOTAL=(); CAT_SIZES=()
init_categories() {
  CAT_IDS=(); CAT_NAMES=(); CAT_NEEDS_SUDO=(); CAT_RISKS=(); CAT_IN_TOTAL=(); CAT_SIZES=()
  local row id name scan clean sudo risk in_total
  for row in "${CATEGORIES[@]}"; do
    IFS='|' read -r id name scan clean sudo risk in_total <<< "$row"
    CAT_IDS+=("$id"); CAT_NAMES+=("$name"); CAT_NEEDS_SUDO+=("$sudo")
    CAT_RISKS+=("$risk"); CAT_IN_TOTAL+=("$in_total"); CAT_SIZES+=(0)
  done
}
init_categories
```

- [ ] **Step 4: Update TOTAL loops to honor in_total**

`clean_mac.sh:449` (`print_scan_table` içinde) satırını:

```bash
    total_bytes=$((total_bytes + CAT_SIZES[$i]))
```

şununla değiştir:

```bash
    [ "${CAT_IN_TOTAL[$i]}" -eq 1 ] && total_bytes=$((total_bytes + CAT_SIZES[$i]))
```

`clean_mac.sh:1321-1323` (`do_scan_json` içinde) bloğunu:

```bash
  for i in "${!CAT_IDS[@]}"; do
    total_bytes=$((total_bytes + CAT_SIZES[$i]))
  done
```

şununla değiştir:

```bash
  for i in "${!CAT_IDS[@]}"; do
    [ "${CAT_IN_TOTAL[$i]}" -eq 1 ] && total_bytes=$((total_bytes + CAT_SIZES[$i]))
  done
```

- [ ] **Step 5: Run test to verify it passes**

Run: `python -m pytest tests/test_clean_mac.py -v`
Expected: PASS (her iki test).

- [ ] **Step 6: Commit**

```bash
git add clean_mac.sh tests/test_clean_mac.py
git commit -m "refactor: derive categories from registry; exclude in_total=0 from headline total"
```

---

### Task 3: Tarama tablosunda TOPLAM etiketini "tahmini" yap + scan JSON'a risk ekle

**Files:**
- Modify: `clean_mac.sh:453` (TOPLAM satırı), `clean_mac.sh:1334-1341` (`do_scan_json` per-kategori çıktısı)

- [ ] **Step 1: Write the failing test**

```python
# tests/test_clean_mac.py içine ekle
def test_scan_json_includes_risk_per_category(tmp_path):
    data = run_scan(tmp_path)
    assert data["scan"]["browser_full"]["risk"] == "danger"
    assert data["scan"]["user_cache"]["risk"] == "safe"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_clean_mac.py::test_scan_json_includes_risk_per_category -v`
Expected: FAIL — KeyError 'risk'.

- [ ] **Step 3: Add risk to do_scan_json output**

`clean_mac.sh:1334-1341` aralığındaki per-kategori çıktı bloğunu bul:

```bash
    local needs_sudo="false"
    [ "${CAT_NEEDS_SUDO[$i]}" -eq 1 ] && needs_sudo="true"
    
    echo "    \"$id\": {"
    echo "      \"size_bytes\": ${CAT_SIZES[$i]},"
    echo "      \"size_human\": \"$sz_h\","
    echo "      \"needs_sudo\": $needs_sudo"
```

`needs_sudo` satırından sonraki `echo` satırını şu iki satırla değiştir (sonuna virgül gelmeli, sonra risk):

```bash
    echo "      \"needs_sudo\": $needs_sudo,"
    echo "      \"risk\": \"${CAT_RISKS[$i]}\""
```

- [ ] **Step 4: Update TOPLAM label (print_scan_table)**

`clean_mac.sh:453` satırını:

```bash
  printf "  ${BOLD}%-3s  %-26s  %-12s${NC}\n" "" "TOPLAM" "$total_h"
```

şununla değiştir:

```bash
  printf "  ${BOLD}%-3s  %-26s  %-12s${NC}\n" "" "TAHMİNİ TOPLAM" "$total_h"
```

- [ ] **Step 5: Run test to verify it passes**

Run: `python -m pytest tests/test_clean_mac.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add clean_mac.sh tests/test_clean_mac.py
git commit -m "feat: expose per-category risk in scan JSON; label total as estimate"
```

---

### Task 4: `scan_app_leftovers` tarayıcı dizinlerini hariç tutsun (çift sayım dedup)

**Files:**
- Modify: `clean_mac.sh:293-310` (`scan_app_leftovers`)

- [ ] **Step 1: Write the failing test**

```python
# tests/test_clean_mac.py içine ekle
def test_app_leftovers_excludes_browser_dirs(tmp_path):
    # Chrome profili Application Support/Google altında; app_leftovers'a
    # sayılmamalı (browser_full sahibi).
    make_dir_with_bytes(
        tmp_path / "Library/Application Support/Google/Chrome", kb=4096)
    make_dir_with_bytes(
        tmp_path / "Library/Application Support/SomeApp", kb=1024)
    data = run_scan(tmp_path)
    leftovers = data["scan"]["app_leftovers"]["size_bytes"]
    # Yalnızca SomeApp (~1MB) sayılmalı, Google (~4MB) değil
    assert leftovers < 3 * 1024 * 1024, leftovers
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_clean_mac.py::test_app_leftovers_excludes_browser_dirs -v`
Expected: FAIL — şu an Google dizini de sayılıyor.

- [ ] **Step 3: Add browser-dir exclusion**

`clean_mac.sh:298-303` aralığındaki `case "$base" in ... esac` bloğuna tarayıcı sahibi üst dizinleri ekle. Mevcut blok:

```bash
    case "$base" in
      com.apple.*|Apple|MobileSync|SyncServices|CrashReporter|\
      Audio|Fonts|Compositions|ColorSync|Spelling|Dictionaries|\
      AddressBook|Calendars|Mail|Messages|Safari|\
      CallHistoryDB|CallHistoryTransactions|CloudDocs|Dock|\
      iCloud|Knowledge|Network|VirtualMachines|DiskImages) continue ;;
    esac
```

şununla değiştir (browser_full'un sahip olduğu üst dizinler eklendi):

```bash
    case "$base" in
      com.apple.*|Apple|MobileSync|SyncServices|CrashReporter|\
      Audio|Fonts|Compositions|ColorSync|Spelling|Dictionaries|\
      AddressBook|Calendars|Mail|Messages|Safari|\
      CallHistoryDB|CallHistoryTransactions|CloudDocs|Dock|\
      iCloud|Knowledge|Network|VirtualMachines|DiskImages|\
      Google|Firefox|BraveSoftware|"Microsoft Edge"|com.operasoftware.Opera|Arc) continue ;;
    esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_clean_mac.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add clean_mac.sh tests/test_clean_mac.py
git commit -m "fix: exclude browser dirs from app_leftovers scan to stop double-counting"
```

---

### Task 5: `get_dir_size_bytes` tek `du -sck` çağrısı (hardlink dedup)

**Files:**
- Modify: `clean_mac.sh:112-123`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_clean_mac.py içine ekle
def test_hardlinks_not_double_counted(tmp_path):
    import os as _os
    logs = tmp_path / "Library/Logs"
    logs.mkdir(parents=True)
    (logs / "a").mkdir()
    (logs / "b").mkdir()
    big = logs / "a" / "big.bin"
    big.write_bytes(b"y" * (5 * 1024 * 1024))  # 5MB
    _os.link(big, logs / "b" / "big_link.bin")  # aynı inode, kardeş dizinde
    data = run_scan(tmp_path)
    logs_size = data["scan"]["logs"]["size_bytes"]
    # Hardlink tek sayılmalı → ~5MB, 10MB değil
    assert logs_size < 8 * 1024 * 1024, logs_size
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_clean_mac.py::test_hardlinks_not_double_counted -v`
Expected: FAIL — per-child `du` döngüsü hardlink'i iki kez sayar.

- [ ] **Step 3: Rewrite get_dir_size_bytes**

`clean_mac.sh:112-123` aralığını şununla değiştir:

```bash
get_dir_size_bytes() {
  local path="$1"
  [ -d "$path" ] || { echo "0"; return; }
  # Tek du çağrısı: hardlink'ler çağrı içinde tekilleşir.
  # -c toplam satırı verir; sadece doğrudan çocukları topla.
  local total
  total=$(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null \
            | xargs -0 du -sck 2>/dev/null \
            | awk 'END {print $1 * 1024}')
  [ -z "$total" ] && total=0
  echo "$total"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_clean_mac.py -v`
Expected: PASS (tüm Faz 1 testleri).

- [ ] **Step 5: Commit**

```bash
git add clean_mac.sh tests/test_clean_mac.py
git commit -m "fix: single du -sck call dedupes hardlinks in get_dir_size_bytes"
```

---

### Task 6: `do_clean_json` gerçek kazancı `df` farkından raporlasın

**Files:**
- Modify: `clean_mac.sh:1389-1455` (`do_clean_json`)

- [ ] **Step 1: Write the failing test**

```python
# tests/test_clean_mac.py içine ekle
def run_clean(home, cats: str) -> dict:
    env = dict(os.environ, HOME=str(home))
    out = subprocess.run(
        ["bash", str(SCRIPT), "--clean-json", cats],
        env=env, capture_output=True, text=True, timeout=60,
    )
    assert out.returncode == 0, out.stderr
    return json.loads(out.stdout)


def test_clean_json_reports_real_and_estimated(tmp_path):
    # logs kategorisi (id index 4) — boş HOME'da silinecek bir şey yok.
    data = run_clean(tmp_path, "4")
    assert "freed_bytes" in data       # gerçek (df farkı)
    assert "estimated_bytes" in data   # du tahmini
    assert "freed_source" in data      # "df" veya "estimated"
    assert data["freed_bytes"] >= 0    # negatif kıstırılmış
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_clean_mac.py::test_clean_json_reports_real_and_estimated -v`
Expected: FAIL — `estimated_bytes`/`freed_source` yok.

- [ ] **Step 3: Add df-delta measurement**

`clean_mac.sh:1403-1406` arasındaki reset bloğunu bul:

```bash
  # Kayıtları resetle
  TOTAL_FREED=0
  TOTAL_ITEMS=0
  CLEAN_RESULTS=()
```

ondan SONRA, temizlik döngüsünden ÖNCE, df ölçümünü ekle:

```bash
  # Kayıtları resetle
  TOTAL_FREED=0
  TOTAL_ITEMS=0
  CLEAN_RESULTS=()

  # Gerçek kazanç ölçümü için temizlik öncesi boş alan (KB, available on /)
  local df_before
  df_before=$(df -k / 2>/dev/null | awk 'NR==2 {print $4}')
```

- [ ] **Step 4: Compute real freed after the clean loop and emit JSON fields**

`clean_mac.sh:1432-1440` aralığındaki çıktı hazırlığını bul:

```bash
  local freed_h; freed_h=$(format_bytes "$TOTAL_FREED")

  # JSON çıktı
  echo '{'
  echo '  "success": true,'
  echo "  \"freed_bytes\": $TOTAL_FREED,"
  echo "  \"freed_human\": \"$freed_h\","
  echo "  \"items_cleaned\": $TOTAL_ITEMS,"
  echo "  \"disk_free\": \"$(get_free_disk)\","
```

şununla değiştir:

```bash
  # Temizlik sonrası boş alan; gerçek kazanç = df farkı (bayt)
  local df_after real_freed freed_source
  df_after=$(df -k / 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -n "$df_before" ] && [ -n "$df_after" ]; then
    real_freed=$(( (df_after - df_before) * 1024 ))
    [ "$real_freed" -lt 0 ] && real_freed=0   # başka süreçler veri yazmış olabilir
    freed_source="df"
  else
    real_freed=$TOTAL_FREED                    # df okunamadı → tahmine düş
    freed_source="estimated"
  fi
  local estimated_bytes=$TOTAL_FREED
  local freed_h; freed_h=$(format_bytes "$real_freed")
  local est_h; est_h=$(format_bytes "$estimated_bytes")

  # JSON çıktı
  echo '{'
  echo '  "success": true,'
  echo "  \"freed_bytes\": $real_freed,"
  echo "  \"freed_human\": \"$freed_h\","
  echo "  \"estimated_bytes\": $estimated_bytes,"
  echo "  \"estimated_human\": \"$est_h\","
  echo "  \"freed_source\": \"$freed_source\","
  echo "  \"items_cleaned\": $TOTAL_ITEMS,"
  echo "  \"disk_free\": \"$(get_free_disk)\","
```

- [ ] **Step 5: Run test to verify it passes**

Run: `python -m pytest tests/test_clean_mac.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add clean_mac.sh tests/test_clean_mac.py
git commit -m "fix: report real freed space via df delta, keep du as estimate"
```

---

### Task 7: Web — gerçek kazancı göster, tahmini ikincil olarak

**Files:**
- Modify: `web/script.js:711-728`

- [ ] **Step 1: Update result rendering**

`web/script.js:711-713` aralığını bul:

```javascript
      const freedText = data.freed_human || formatBytes(data.freed_bytes || 0);
      el.resultsFreed.textContent = freedText;
      el.resultsSub.textContent = `${data.items_cleaned || selected.length} kategori · Yeni boş alan ${data.disk_free || '—'}`;
```

şununla değiştir (gerçek kazanç büyük rakam; tahmin ve kaynak alt satırda):

```javascript
      const freedText = data.freed_human || formatBytes(data.freed_bytes || 0);
      el.resultsFreed.textContent = freedText;
      let subParts = [`${data.items_cleaned || selected.length} kategori`,
                      `Yeni boş alan ${data.disk_free || '—'}`];
      if (data.estimated_human && data.freed_source === 'df') {
        subParts.push(`Tahmini taranan: ${data.estimated_human}`);
      }
      el.resultsSub.textContent = subParts.join(' · ');
```

- [ ] **Step 2: Manual verification**

Run: `cd /Users/burak/Desktop/projects/apple-cleanup && python web/server.py` (ayrı terminalde), tarayıcıda paneli aç, küçük bir güvenli kategori (Loglar) temizle. "Kazanılan alan" rakamının `df` farkını, alt satırın "Tahmini taranan"ı gösterdiğini doğrula.
Expected: Büyük rakam gerçek df-farkı; alt satırda tahmini.

- [ ] **Step 3: Commit**

```bash
git add web/script.js
git commit -m "feat(ui): show real freed space, surface du estimate as secondary"
```

---

**FAZ 1 SONU.** Bu noktada Problem 1 (tarama toplamı şişmesi) ve Problem 2 (silinen≠gösterilen) çözülmüştür ve testlerle doğrulanmıştır. İstenirse burada merge edilebilir.

---

## FAZ 2 — Tarama Derinliği

### Task 8: Geliştirici alt-öğelerini genişlet (brew/npm/pnpm/yarn/pip/cocoapods/gradle/maven/devicesupport/coresim/archives/simctl/node_modules)

> **Not:** Mevcut `developer` kategorisi zaten alt-öğe (`--developer-sub`) mekanizmasına sahip (`DEVELOPER_CLEAN`, `clean_developer:877+`, `_DEVELOPER_WHITELIST`). Bu task o mekanizmayı genişletir. Önce `scan_developer_subitems_json` ve `clean_developer` fonksiyonlarını oku.

**Files:**
- Modify: `clean_mac.sh` — `scan_developer_subitems_json`, `clean_developer` (877+)
- Modify: `web/server.py:33-36` (`_DEVELOPER_WHITELIST`)
- Modify: `tests/test_server_validation.py`

- [ ] **Step 1: Write failing validation test**

```python
# tests/test_server_validation.py — DeveloperWhitelist test sınıfına ekle
    def test_new_developer_keys_allowed(self):
        for k in ["device_support", "coresim_caches", "xcode_archives",
                  "simctl_unavailable", "pnpm_cache", "yarn_cache",
                  "cocoapods_cache", "gradle_cache", "maven_repo"]:
            self.assertTrue(self.v(k), k)
```

- [ ] **Step 2: Run to verify it fails**

Run: `python -m pytest tests/test_server_validation.py -v -k developer`
Expected: FAIL — yeni anahtarlar whitelist'te yok.

- [ ] **Step 3: Extend whitelist in server.py**

`web/server.py:33-36` aralığını şununla değiştir:

```python
_DEVELOPER_WHITELIST = frozenset({
    "derived_data", "broken_links",
    "brew_cache", "docker_prune", "npm_cache", "pip_cache",
    "device_support", "coresim_caches", "xcode_archives",
    "simctl_unavailable", "pnpm_cache", "yarn_cache",
    "cocoapods_cache", "gradle_cache", "maven_repo",
})
```

- [ ] **Step 4: Run validation test to verify it passes**

Run: `python -m pytest tests/test_server_validation.py -v -k developer`
Expected: PASS.

- [ ] **Step 5: Add scan helper for path-based dev items**

`clean_mac.sh`'te `scan_developer_subitems_json` fonksiyonundan ÖNCE şu yardımcıyı ekle (yol → tek alt-öğe JSON satırı, risk dahil):

```bash
# id, görünen ad, yol, risk → JSON alt-öğe satırı (yol yoksa hiçbir şey yazma)
emit_dev_subitem() {
  local id="$1" name="$2" path="$3" risk="$4"
  [ -e "$path" ] || return 0
  local s; s=$(get_size_bytes "$path") || s=0
  [ "$s" -le 0 ] 2>/dev/null && return 0
  local sz_h; sz_h=$(format_bytes "$s")
  local esc_name; esc_name=$(json_escape_str "$name")
  echo -n "        {\"id\": \"$id\", \"name\": \"$esc_name\", \"path\": \"\", \"size_bytes\": $s, \"size_human\": \"$sz_h\", \"risk\": \"$risk\", \"is_orphaned\": true}"
  echo ","
}
```

- [ ] **Step 6: Extend scan_developer_subitems_json**

`scan_developer_subitems_json` fonksiyonunun gövdesine (mevcut derived_data/broken_links satırlarından sonra) şu çağrıları ekle:

```bash
  emit_dev_subitem "device_support" "iOS DeviceSupport" \
    "$HOME/Library/Developer/Xcode/iOS DeviceSupport" "safe"
  emit_dev_subitem "coresim_caches" "CoreSimulator Caches" \
    "$HOME/Library/Developer/CoreSimulator/Caches" "safe"
  emit_dev_subitem "xcode_archives" "Xcode Archives" \
    "$HOME/Library/Developer/Xcode/Archives" "caution"
  emit_dev_subitem "cocoapods_cache" "CocoaPods Cache" \
    "$HOME/Library/Caches/CocoaPods" "safe"
  emit_dev_subitem "pip_cache" "pip Cache" \
    "$HOME/Library/Caches/pip" "safe"
  emit_dev_subitem "pnpm_cache" "pnpm Store" \
    "$HOME/Library/pnpm" "safe"
  emit_dev_subitem "yarn_cache" "Yarn Cache" \
    "$HOME/Library/Caches/Yarn" "safe"
  emit_dev_subitem "gradle_cache" "Gradle Cache" \
    "$HOME/.gradle/caches" "caution"
  emit_dev_subitem "maven_repo" "Maven Repository" \
    "$HOME/.m2/repository" "caution"
  # Homebrew cache yolu (brew kuruluysa)
  if command -v brew >/dev/null 2>&1; then
    local brew_cache; brew_cache=$(brew --cache 2>/dev/null)
    emit_dev_subitem "brew_cache" "Homebrew Cache" "$brew_cache" "safe"
  fi
  # npm cache yolu
  if command -v npm >/dev/null 2>&1; then
    local npm_cache; npm_cache=$(npm config get cache 2>/dev/null)
    emit_dev_subitem "npm_cache" "npm Cache" "$npm_cache" "safe"
  fi
```

- [ ] **Step 7: Extend clean_developer (JSON mode) to handle new keys**

`clean_developer`'ın JSON-mode döngüsünde (`for item in $clean_items`) yeni anahtarları işle. Mevcut `case "$item" in ... esac` bloğuna şu kolları ekle (yol-tabanlı olanlar `safe_rm_contents`, simctl ayrı komut):

```bash
      device_support)
        safe_rm_contents "$HOME/Library/Developer/Xcode/iOS DeviceSupport" "iOS DeviceSupport" ;;
      coresim_caches)
        safe_rm_contents "$HOME/Library/Developer/CoreSimulator/Caches" "CoreSimulator Caches" ;;
      xcode_archives)
        safe_rm_contents "$HOME/Library/Developer/Xcode/Archives" "Xcode Archives" ;;
      cocoapods_cache)
        safe_rm_contents "$HOME/Library/Caches/CocoaPods" "CocoaPods Cache" ;;
      pip_cache)
        safe_rm_contents "$HOME/Library/Caches/pip" "pip Cache" ;;
      pnpm_cache)
        safe_rm_contents "$HOME/Library/pnpm" "pnpm Store" ;;
      yarn_cache)
        safe_rm_contents "$HOME/Library/Caches/Yarn" "Yarn Cache" ;;
      gradle_cache)
        safe_rm_contents "$HOME/.gradle/caches" "Gradle Cache" ;;
      maven_repo)
        safe_rm_contents "$HOME/.m2/repository" "Maven Repository" ;;
      simctl_unavailable)
        if command -v xcrun >/dev/null 2>&1; then
          xcrun simctl delete unavailable >/dev/null 2>&1 \
            && success "Erişilmez simülatörler silindi" \
            || warn "simctl çalıştırılamadı"
        fi ;;
      brew_cache)
        if command -v brew >/dev/null 2>&1; then
          safe_rm_contents "$(brew --cache 2>/dev/null)" "Homebrew Cache"
        fi ;;
      npm_cache)
        if command -v npm >/dev/null 2>&1; then
          safe_rm_contents "$(npm config get cache 2>/dev/null)" "npm Cache"
        fi ;;
```

- [ ] **Step 8: Commit**

```bash
git add clean_mac.sh web/server.py tests/test_server_validation.py
git commit -m "feat: expand developer subitems (brew/npm/pip/pods/gradle/maven/simulators)"
```

---

### Task 9: Yeni sistem & geçici kategorileri

`diagnostic_reports`, `quicklook_cache`, `font_cache`, `saved_app_state`, `other_trash` kategorilerini registry'ye ekle ve scan_/clean_ fonksiyonlarını yaz.

**Files:**
- Modify: `clean_mac.sh` — `CATEGORIES` registry + yeni fonksiyonlar + `fn_map` (1409-1412) + `do_clean_json` fonksiyon eşleştirmesi

- [ ] **Step 1: Write the failing test**

```python
# tests/test_clean_mac.py içine ekle
def test_new_system_categories_present(tmp_path):
    data = run_scan(tmp_path)
    for cid in ["diagnostic_reports", "quicklook_cache",
                "saved_app_state", "other_trash"]:
        assert cid in data["scan"], cid
```

- [ ] **Step 2: Run to verify it fails**

Run: `python -m pytest tests/test_clean_mac.py::test_new_system_categories_present -v`
Expected: FAIL — bu kategoriler yok.

- [ ] **Step 3: Add registry rows**

`CATEGORIES` dizisine (mail_downloads satırından önce) ekle:

```bash
  "diagnostic_reports|Tanılama Raporları|scan_diagnostic_reports|clean_diagnostic_reports|0|safe|1"
  "quicklook_cache|QuickLook Cache|scan_quicklook_cache|clean_quicklook_cache|0|safe|1"
  "saved_app_state|Kaydedilmiş Uygulama Durumu|scan_saved_app_state|clean_saved_app_state|0|caution|1"
  "other_trash|Diğer Ciltlerin Çöpü|scan_other_trash|clean_other_trash|0|safe|1"
```

- [ ] **Step 4: Add scan + clean functions**

`clean_mac.sh`'te tarama fonksiyonları bölümüne ekle:

```bash
scan_diagnostic_reports() {
  local i; i=$(cat_index_by_id diagnostic_reports)
  CAT_SIZES[$i]=$(get_dir_size_bytes "$HOME/Library/Logs/DiagnosticReports")
}
clean_diagnostic_reports() {
  header "🩺 Tanılama Raporları Temizleniyor"
  safe_rm_contents "$HOME/Library/Logs/DiagnosticReports" "DiagnosticReports"
}

scan_quicklook_cache() {
  local i; i=$(cat_index_by_id quicklook_cache)
  CAT_SIZES[$i]=$(get_dir_size_bytes \
    "$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null)com.apple.QuickLook.thumbnailcache")
}
clean_quicklook_cache() {
  header "🖼️  QuickLook Cache Temizleniyor"
  qlmanage -r cache >/dev/null 2>&1 \
    && success "QuickLook thumbnail cache sıfırlandı" \
    || warn "qlmanage çalıştırılamadı"
}

scan_saved_app_state() {
  local i; i=$(cat_index_by_id saved_app_state)
  CAT_SIZES[$i]=$(get_dir_size_bytes "$HOME/Library/Saved Application State")
}
clean_saved_app_state() {
  header "💾 Kaydedilmiş Uygulama Durumu Temizleniyor"
  safe_rm_contents "$HOME/Library/Saved Application State" "Saved Application State"
}

scan_other_trash() {
  local i; i=$(cat_index_by_id other_trash)
  local total=0 d s
  for d in /Volumes/*/.Trashes; do
    [ -d "$d" ] || continue
    s=$(get_dir_size_bytes "$d") || s=0
    total=$((total + s))
  done
  CAT_SIZES[$i]=$total
}
clean_other_trash() {
  header "🗑️  Diğer Ciltlerin Çöpü Temizleniyor"
  local d
  for d in /Volumes/*/.Trashes; do
    [ -d "$d" ] || continue
    safe_rm_contents "$d" "$d"
  done
}
```

- [ ] **Step 5: Add cat_index_by_id helper**

`cat_field` yakınına ekle (id → indeks):

```bash
cat_index_by_id() {
  local want="$1" i
  for i in "${!CAT_IDS[@]}"; do
    [ "${CAT_IDS[$i]}" = "$want" ] && { echo "$i"; return; }
  done
  echo "-1"
}
```

- [ ] **Step 6: Wire into fn_map (do_clean_json)**

`clean_mac.sh:1409-1412` `fn_map` artık registry'den türetilmeli. Mevcut sabit `fn_map=(...)` bloğunu şununla değiştir:

```bash
  # Temizleme fonksiyonları registry'den türetilir (indeks hizalaması garanti)
  local fn_map=()
  local _i
  for _i in "${!CAT_IDS[@]}"; do
    fn_map+=("$(cat_field "$_i" clean_fn)")
  done
```

> **Not:** `scan_all`'daki `fns=(...)` listesi de (`clean_mac.sh:418-421`) aynı şekilde registry'den türetilmeli:
> ```bash
>   local fns=()
>   local _i
>   for _i in "${!CAT_IDS[@]}"; do fns+=("$(cat_field "$_i" scan_fn)"); done
> ```

- [ ] **Step 7: Run tests**

Run: `python -m pytest tests/test_clean_mac.py -v`
Expected: PASS (yeni kategoriler scan JSON'da görünür).

- [ ] **Step 8: Commit**

```bash
git add clean_mac.sh tests/test_clean_mac.py
git commit -m "feat: add diagnostic reports, QuickLook, saved state, other-volume trash categories"
```

---

### Task 10: Yerel snapshot inceltme — maintenance action (`--thin-snapshots`)

Purgeable alanı gerçek boş alana çeviren `tmutil thinLocalSnapshots` eylemi. Mevcut flush-dns/purge-ram maintenance deseni izlenir.

**Files:**
- Modify: `clean_mac.sh` — yeni `do_thin_snapshots_json` + argüman parser (1484+)
- Modify: `web/server.py` — yeni `/api/thin-snapshots` route
- Modify: `web/script.js`, `web/index.html`, `web/style.css` — maintenance kartı

- [ ] **Step 1: Write the failing test**

```python
# tests/test_clean_mac.py içine ekle
def test_thin_snapshots_json_shape(tmp_path):
    env = dict(os.environ, HOME=str(tmp_path))
    out = subprocess.run(
        ["bash", str(SCRIPT), "--thin-snapshots-json"],
        env=env, capture_output=True, text=True, timeout=60,
    )
    assert out.returncode == 0, out.stderr
    data = json.loads(out.stdout)
    assert "success" in data
    assert "snapshots_before" in data
```

- [ ] **Step 2: Run to verify it fails**

Run: `python -m pytest tests/test_clean_mac.py::test_thin_snapshots_json_shape -v`
Expected: FAIL — bilinmeyen argüman.

- [ ] **Step 3: Add do_thin_snapshots_json**

`do_status_json` yakınına ekle:

```bash
do_thin_snapshots_json() {
  local before after note="ok"
  before=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple.TimeMachine" || echo 0)
  # 10GB hedef, urgency 4 (agresif). Yetki yoksa sessiz başarısız.
  tmutil thinLocalSnapshots / 10000000000 4 >/dev/null 2>&1 || note="yetki_yok_veya_snapshot_yok"
  after=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple.TimeMachine" || echo 0)
  cat <<ENDJSON
{
  "success": true,
  "snapshots_before": $before,
  "snapshots_after": $after,
  "note": "$note",
  "disk_free": "$(get_free_disk)"
}
ENDJSON
}
```

- [ ] **Step 4: Add argument parsing**

`clean_mac.sh:1484` civarındaki argüman `case` bloğuna ekle:

```bash
    --thin-snapshots-json)
      JSON_MODE=true
      do_thin_snapshots_json
      exit 0
      ;;
```

- [ ] **Step 5: Run test to verify it passes**

Run: `python -m pytest tests/test_clean_mac.py::test_thin_snapshots_json_shape -v`
Expected: PASS.

- [ ] **Step 6: Add server route**

`web/server.py` `do_POST` route dağıtıcısına (`/api/launchagents-clean` yakınına) ekle:

```python
        elif parsed.path == "/api/thin-snapshots":
            self._handle_thin_snapshots()
```

ve handler (`_handle_launchagents_clean` yakınına):

```python
    def _handle_thin_snapshots(self):
        data, err = self._run_script(["--thin-snapshots-json"], timeout=120)
        if err:
            self._send_error_json(f"Snapshot inceltme hatası: {err}")
        else:
            self._send_json(data)
```

- [ ] **Step 7: Add UI maintenance card**

`web/index.html`'de mevcut DNS/RAM maintenance kartlarının yanına ekle:

```html
<button class="maint-card" id="thinSnapshotsBtn" type="button">
  <span class="maint-icon">📸</span>
  <span class="maint-title">Yerel Snapshot İnceltme</span>
  <span class="maint-desc">Purgeable alanı gerçek boş alana çevirir</span>
</button>
```

`web/script.js`'de mevcut maintenance handler desenini izleyerek ekle (örn. `purgeRamBtn` handler'ının hemen yanına):

```javascript
  $('#thinSnapshotsBtn')?.addEventListener('click', async () => {
    termLog('Yerel snapshot inceltme başlatıldı…');
    try {
      const res = await fetch('/api/thin-snapshots', { method: 'POST' });
      const data = await res.json();
      if (data.success) {
        termLog(`Snapshot: ${data.snapshots_before} → ${data.snapshots_after} · Boş alan ${data.disk_free}`, 'success');
      } else {
        termLog(`Hata: ${data.error || 'bilinmeyen'}`, 'error');
      }
    } catch (e) {
      termLog(`İstek hatası: ${e.message}`, 'error');
    }
  });
```

- [ ] **Step 8: Manual verification + commit**

Run: `python web/server.py`, panelde "Yerel Snapshot İnceltme" kartına tıkla; terminal log'unda snapshot sayısı ve yeni boş alanın güncellendiğini doğrula.

```bash
git add clean_mac.sh web/server.py web/script.js web/index.html web/style.css
git commit -m "feat: add local snapshot thinning maintenance action"
```

---

### Task 11: Risk rozetleri ve danger onayı (UI)

Scan JSON artık `risk` taşıyor (Task 3). Kategori kartlarında rozet göster; `danger` kategoriler temizlik payload'ına girmeden açık onay iste.

**Files:**
- Modify: `web/script.js` (kategori kart render'ı ~236, clean payload toplama), `web/style.css`

- [ ] **Step 1: Render risk badge in category card**

`web/script.js:236` civarındaki kategori kart şablonunda `cat-size` span'inin yanına risk rozeti ekle:

```javascript
        <span class="cat-risk" data-risk="${cat.key}"></span>
```

ve scan sonucu işlenirken (`web/script.js:528` civarı, `sizeEl` set edildiği yerde) ekle:

```javascript
        const riskEl = $(`.cat-risk[data-risk="${key}"]`, card);
        if (riskEl && info.risk && info.risk !== 'safe') {
          riskEl.textContent = info.risk === 'danger' ? '⚠ Riskli' : '⚠ Dikkat';
          riskEl.className = `cat-risk risk-${info.risk}`;
        }
```

- [ ] **Step 2: Require confirm for danger categories before clean**

Clean tetikleyen handler'da (seçili kategoriler toplandıktan sonra, fetch'ten önce) ekle:

```javascript
      const dangerSelected = selected.filter(
        (k) => scanData?.scan?.[k]?.risk === 'danger');
      if (dangerSelected.length > 0) {
        const names = dangerSelected.map((k) => CAT_BY_KEY[k]?.name || k).join(', ');
        if (!confirm(`Riskli kategoriler seçildi (${names}). Bu veriler kalıcı silinir. Devam edilsin mi?`)) {
          return;
        }
      }
```

- [ ] **Step 3: Add CSS**

`web/style.css`'e ekle:

```css
.cat-risk { font-size: 11px; font-weight: 600; margin-left: 8px; }
.cat-risk.risk-caution { color: #d68900; }
.cat-risk.risk-danger  { color: #d23f31; }
```

- [ ] **Step 4: Manual verification + commit**

Run: `python web/server.py`; "Tarayıcı Tüm Veri" (danger) kategorisinde ⚠ rozeti göründüğünü ve seçili temizlikte onay diyaloğu çıktığını doğrula.

```bash
git add web/script.js web/style.css
git commit -m "feat(ui): risk badges on categories and confirm gate for danger items"
```

---

## Self-Review Notları

- **Spec kapsamı:** Problem 1 → Task 2-4; Problem 2 → Task 5-7; geliştirici derinliği → Task 8; sistem/geçici → Task 9; purgeable/snapshot → Task 10; risk etiketleri → Task 3 (JSON) + Task 11 (UI); testler her task'ta + Task 8 (validation).
- **node_modules bulucu** ve **eski indirilenler**: spec'te listelendi ama kök-dizin/eşik kararı kullanıcı onayına bağlı. Bu plana DAHİL EDİLMEDİ (YAGNI / belirsiz girdi); ayrı task olarak, kullanıcı kök dizini ve gün eşiğini netleştirince eklenecek.
- **Tutarlılık:** `cat_field`, `cat_index_by_id`, `init_categories`, `emit_dev_subitem` tüm task'larda aynı imzayla kullanılıyor. `fn_map`/`fns` Task 9'da registry'den türetiliyor.
```
