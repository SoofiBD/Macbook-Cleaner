#!/usr/bin/env bash
# clean_mac.sh — macOS Genel Sistem Temizleyici (Güvenli Sürüm)
# Kullanım: bash clean_mac.sh
#   --scan-json           Tarama sonuçlarını JSON olarak döner (web API için)
#   --clean-json 1,3,7    Belirtilen kategorileri temizler, sonucu JSON döner
#   --app-leftovers "dir1,dir2"  (JSON modunda) Temizlenecek uygulama kalıntı dizinleri
#   --browser-full-sub "chrome,safari"  (JSON modunda) Sıfırlanacak tarayıcı profilleri
#   --developer-sub "derived_data"  (JSON modunda) Temizlenecek geliştirici alt öğeleri
#   --status-json         Sistem bilgisini JSON olarak döner
set -euo pipefail

# ─── Renkler (terminale bağlı değilse devre dışı) ───────────────────────────
if [ -t 1 ]; then
  RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
  CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'
  DIM='\033[2m';     NC='\033[0m'
else
  RED=''; YELLOW=''; GREEN=''; CYAN=''; BLUE=''; BOLD=''; DIM=''; NC=''
fi

VERSION="1.1.0"
SUDO_AVAILABLE=false
TOTAL_FREED=0
TOTAL_ITEMS=0
JSON_MODE=false
CLEAN_RESULTS=()

# JSON modunda temizlenecek alt öğe listeleri (virgülle ayrılmış)
APP_LEFTOVERS_CLEAN=""
BROWSER_FULL_CLEAN=""
DEVELOPER_CLEAN=""
IOS_BACKUPS_CLEAN=""
APP_UNINSTALLER_CLEAN=""

MAIL_DOWNLOADS_DIR="$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"

# Tarayıcı cache dizinleri (~/Library/Caches içindeki üst-seviye klasör adları)
BROWSER_CACHE_TOPDIRS=(
  "com.apple.Safari"
  "com.apple.WebKit.Networking"
  "Google"
  "com.google.Chrome"
  "org.mozilla.firefox"
  "Firefox"
  "com.brave.Browser"
  "com.microsoft.edgemac"
  "Microsoft Edge"
  "com.operasoftware.Opera"
  "com.arc.app"
  "com.vivaldi.Vivaldi"
)

# Tarayıcı profil dizinleri (çerezler, geçmiş vb.)
BROWSER_FULL_DIRS=(
  "$HOME/Library/Safari"
  "$HOME/Library/Cookies"
  "$HOME/Library/Application Support/Google/Chrome"
  "$HOME/Library/Application Support/Firefox"
  "$HOME/Library/Application Support/BraveSoftware"
  "$HOME/Library/Application Support/Microsoft Edge"
  "$HOME/Library/Application Support/com.operasoftware.Opera"
  "$HOME/Library/Application Support/Arc"
)

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
  "diagnostic_reports|Tanılama Raporları|scan_diagnostic_reports|clean_diagnostic_reports|0|safe|1"
  "quicklook_cache|QuickLook Cache|scan_quicklook_cache|clean_quicklook_cache|0|safe|1"
  "saved_app_state|Kaydedilmiş Uygulama Durumu|scan_saved_app_state|clean_saved_app_state|0|caution|1"
  "other_trash|Diğer Ciltlerin Çöpü|scan_other_trash|clean_other_trash|0|safe|1"
)

# Registry'den paralel dizileri türet (mevcut indeks-tabanlı kod korunur)
CAT_IDS=(); CAT_NAMES=(); CAT_NEEDS_SUDO=(); CAT_RISKS=(); CAT_IN_TOTAL=(); CAT_SIZES=()
init_categories() {
  CAT_IDS=(); CAT_NAMES=(); CAT_NEEDS_SUDO=(); CAT_RISKS=(); CAT_IN_TOTAL=(); CAT_SIZES=()
  local row id name scan clean sudo risk in_total
  # scan_fn/clean_fn alanları şimdilik türetilmiyor; ileride cat_field ile okunur.
  for row in "${CATEGORIES[@]}"; do
    IFS='|' read -r id name scan clean sudo risk in_total <<< "$row"
    if [ -z "$in_total" ]; then
      echo "HATA: bozuk CATEGORIES satırı: $row" >&2
      exit 1
    fi
    CAT_IDS+=("$id"); CAT_NAMES+=("$name"); CAT_NEEDS_SUDO+=("$sudo")
    CAT_RISKS+=("$risk"); CAT_IN_TOTAL+=("$in_total"); CAT_SIZES+=(0)
  done
}
init_categories

# Registry satırından alan oku: cat_field <index> <field>
# field: id|name|scan_fn|clean_fn|needs_sudo|risk|in_total
cat_field() {
  local idx="$1" field="$2"
  local id name scan clean sudo risk in_total
  IFS='|' read -r id name scan clean sudo risk in_total <<< "${CATEGORIES[$idx]}"
  case "$field" in
    id) echo "$id" ;; name) echo "$name" ;; scan_fn) echo "$scan" ;;
    clean_fn) echo "$clean" ;; needs_sudo) echo "$sudo" ;;
    risk) echo "$risk" ;; in_total) echo "$in_total" ;;
  esac
}

# id → indeks (bulunamazsa -1)
cat_index_by_id() {
  local want="$1" i
  for i in "${!CAT_IDS[@]}"; do
    [ "${CAT_IDS[$i]}" = "$want" ] && { echo "$i"; return; }
  done
  echo "-1"
}

# ─── UI ─────────────────────────────────────────────────────────────────────
header() {
  echo ""
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${CYAN}  $1${NC}"
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

separator() {
  echo -e "${DIM}  ──────────────────────────────────────────────────${NC}"
}

info()    { echo -e "  ${BLUE}ℹ${NC}  $1"; }
success() { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }
err()     { echo -e "  ${RED}✗${NC}  $1" >&2; }

# ─── Boyut Yardımcıları ──────────────────────────────────────────────────────
format_bytes() {
  local b=$1
  if   [ "$b" -ge 1073741824 ]; then printf "%.1f GB" "$(echo "scale=1; $b/1073741824" | bc)"
  elif [ "$b" -ge 1048576 ];    then printf "%.1f MB" "$(echo "scale=1; $b/1048576"    | bc)"
  elif [ "$b" -ge 1024 ];       then printf "%.1f KB" "$(echo "scale=1; $b/1024"       | bc)"
  else printf "%d B" "$b"; fi
}

get_size_bytes() {
  local path="$1"
  [ -e "$path" ] || { echo "0"; return; }
  local result
  result=$(du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}') || result=""
  if [ -z "$result" ]; then
    result="0"
  fi
  echo "$result"
}

get_dir_size_bytes() {
  local path="$1"
  [ -d "$path" ] || { echo "0"; return; }
  # Boş dizin: du'yu hiç çağırma (macOS xargs'ta -r yok).
  local first
  first=$(find "$path" -maxdepth 1 -mindepth 1 -print -quit 2>/dev/null)
  [ -z "$first" ] && { echo "0"; return; }
  # Tek du çağrısı: hardlink'ler çağrı içinde tekilleşir.
  # NOT: ~17k+ doğrudan çocuk olan dizinlerde xargs ARG_MAX'te bölünebilir ve
  # awk END yalnız son batch'in 'total'ını alıp eksik sayabilir. Gerçek kazanç
  # df farkından ölçüldüğü için bu yalnızca tahmini etkiler (kabul edilebilir).
  local total
  total=$(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null \
            | xargs -0 du -sck 2>/dev/null \
            | awk 'END {print $1 * 1024}')
  [ -z "$total" ] && total=0
  echo "$total"
}

get_free_disk() {
  df -h / 2>/dev/null | awk 'NR==2 {print $4}' || echo "?"
}

# ─── Etkileşim ──────────────────────────────────────────────────────────────
confirm() {
  local prompt="${1:-Devam etmek istiyor musunuz?}"
  local answer
  echo -ne "  ${YELLOW}?${NC}  $prompt [e/H]: "
  read -r answer
  [[ "$answer" =~ ^[eEyY]$ ]]
}

# ─── Güvenli Silme ───────────────────────────────────────────────────────────
safe_rm() {
  local path="$1"
  local label="${2:-$1}"
  [ -z "$path" ] && { err "Boş path, atlanıyor: $label"; return 1; }
  case "$path" in
    /System/*|/usr/*|/bin/*|/sbin/*|/etc/*|/private/etc/*)
      err "Korunan sistem yolu, dokunulmadı: $path"; return 1 ;;
  esac
  [ -e "$path" ] || return 0
  local sz_b; sz_b=$(get_size_bytes "$path")
  local sz_h; sz_h=$(format_bytes "$sz_b")
  if $SUDO_AVAILABLE; then
    sudo rm -rf "$path" 2>/dev/null && {
      success "$label: ${BOLD}${sz_h}${NC} silindi"
      TOTAL_FREED=$((TOTAL_FREED + sz_b))
      TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
    } || err "$label silinemedi"
  else
    rm -rf "$path" 2>/dev/null && {
      success "$label: ${BOLD}${sz_h}${NC} silindi"
      TOTAL_FREED=$((TOTAL_FREED + sz_b))
      TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
    } || err "$label silinemedi"
  fi
}

safe_rm_contents() {
  local path="$1"
  local label="${2:-$1}"
  [ -d "$path" ] || return 0
  [ -z "$path" ] && return 1
  case "$path" in
    /System/*|/usr/*|/bin/*|/sbin/*|/etc/*|/private/etc/*) err "Korunan yol: $path"; return 1 ;;
  esac
  local sz_b; sz_b=$(get_dir_size_bytes "$path")
  [ "$sz_b" -le 0 ] 2>/dev/null && return 0
  local sz_h; sz_h=$(format_bytes "$sz_b")
  if $SUDO_AVAILABLE; then
    sudo find "$path" -maxdepth 1 -mindepth 1 -exec rm -rf {} + 2>/dev/null && {
      success "$label: ${BOLD}${sz_h}${NC} silindi"
      TOTAL_FREED=$((TOTAL_FREED + sz_b))
      TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
    } || err "$label silinemedi"
  else
    find "$path" -maxdepth 1 -mindepth 1 -exec rm -rf {} + 2>/dev/null && {
      success "$label: ${BOLD}${sz_h}${NC} silindi"
      TOTAL_FREED=$((TOTAL_FREED + sz_b))
      TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
    } || err "$label silinemedi"
  fi
}

# ─── Sudo Kontrolü ──────────────────────────────────────────────────────────
sudo_check() {
  echo ""
  info "Sistem Cache ve Loglar için ${BOLD}sudo${NC} yetkisi gerekebilir."
  info "Sudo olmadan bu kategoriler otomatik atlanır."
  echo ""
  if confirm "Sudo yetkisi ile çalışmak ister misiniz?"; then
    if sudo -v 2>/dev/null; then
      SUDO_AVAILABLE=true
      success "Sudo yetki alındı."
    else
      warn "Sudo yetki alınamadı. Sistem kategorileri atlanacak."
    fi
  else
    info "Sudo atlandı. Sadece kullanıcı seviyesi temizlik yapılacak."
  fi
}

# ─── Tarayıcı Dizin Kontrolü ─────────────────────────────────────────────────
is_browser_cache_dir() {
  local name; name=$(basename "$1")
  local d
  for d in "${BROWSER_CACHE_TOPDIRS[@]}"; do
    [[ "$name" == "$d" ]] && return 0
  done
  return 1
}

# ─── Uygulama Kurulum Kontrol Heuristiği ──────────────────────────────────────
get_app_name_for_dir() {
  local dir_name="$1"
  case "$dir_name" in
    "Claude") echo "Claude" ;;
    "com.anthropic.claude") echo "Claude" ;;
    "Discord") echo "Discord" ;;
    "Slack") echo "Slack" ;;
    "Spotify") echo "Spotify" ;;
    "Steam") echo "Steam" ;;
    "Code") echo "Visual Studio Code" ;;
    "com.microsoft.VSCode") echo "Visual Studio Code" ;;
    "Sublime Text") echo "Sublime Text" ;;
    "Docker") echo "Docker" ;;
    "Telegram Desktop") echo "Telegram" ;;
    "com.tdesktop.Telegram") echo "Telegram" ;;
    "WhatsApp") echo "WhatsApp" ;;
    "zoom.us") echo "zoom.us" ;;
    *)
      if [[ "$dir_name" == *.* ]]; then
        echo "${dir_name##*.}"
      else
        echo "$dir_name"
      fi
      ;;
  esac
}

is_app_installed() {
  local dir_name="$1"
  # Kritik sistem ve korunan klasörler her zaman kurulu kabul edilir ve korunur
  case "$dir_name" in
    Apple|com.apple.*|com.google.*|com.microsoft.*|com.adobe.*|\
    com.oracle.*|Homebrew|\
    Helper|CrashReporter|MobileSync|SyncServices|\
    Audio|Fonts|Compositions|ColorSync|Spelling|Dictionaries|\
    AddressBook|Calendars|Mail|Messages|Safari|\
    CallHistoryDB|CallHistoryTransactions|CloudDocs|Dock|\
    iCloud|Knowledge|Network|VirtualMachines|DiskImages)
      return 0
      ;;
  esac

  local app_name; app_name=$(get_app_name_for_dir "$dir_name")
  
  if [ -d "/Applications/${app_name}.app" ] || \
     [ -d "/System/Applications/${app_name}.app" ] || \
     [ -d "$HOME/Applications/${app_name}.app" ] || \
     [ -d "/Applications/Utilities/${app_name}.app" ] || \
     [ -d "/System/Applications/Utilities/${app_name}.app" ]; then
    return 0
  fi
  return 1
}

# ─── Tarama ─────────────────────────────────────────────────────────────────
scan_user_cache() {
  local total=0
  local item
  while IFS= read -r -d '' item; do
    is_browser_cache_dir "$item" && continue
    local s=0
    s=$(get_size_bytes "$item") || s=0
    total=$((total + s))
  done < <(find "$HOME/Library/Caches" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
  CAT_SIZES[0]=$total
}

scan_system_cache() {
  if ! $SUDO_AVAILABLE; then CAT_SIZES[1]=0; return; fi
  local s; s=$(sudo du -sk /Library/Caches 2>/dev/null | awk '{print $1*1024}') || s=0
  CAT_SIZES[1]=$s
}

scan_app_leftovers() {
  local total=0
  local item base s=0
  while IFS= read -r -d '' item; do
    base=$(basename "$item")
    case "$base" in
      com.apple.*|Apple|MobileSync|SyncServices|CrashReporter|\
      Audio|Fonts|Compositions|ColorSync|Spelling|Dictionaries|\
      AddressBook|Calendars|Mail|Messages|Safari|\
      CallHistoryDB|CallHistoryTransactions|CloudDocs|Dock|\
      iCloud|Knowledge|Network|VirtualMachines|DiskImages|\
      Google|Firefox|BraveSoftware|"Microsoft Edge"|com.operasoftware.Opera|Arc) continue ;;
    esac
    s=$(get_size_bytes "$item") 2>/dev/null || s=0
    [ -z "$s" ] && s=0
    total=$((total + s))
  done < <(find "$HOME/Library/Application Support" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
  CAT_SIZES[2]=$total
}

scan_logs() {
  local total=0
  local s=0
  s=$(get_dir_size_bytes "$HOME/Library/Logs") || s=0
  total=$((total + s))
  if $SUDO_AVAILABLE; then
    s=$(sudo du -sk /Library/Logs 2>/dev/null | awk '{print $1*1024}') || s=0
    total=$((total + s))
  fi
  CAT_SIZES[3]=$total
}

scan_temp_files() {
  local total=0
  local tmpdir s=0
  tmpdir=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || echo "${TMPDIR:-/tmp}")
  local cachedir
  cachedir=$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || echo "")
  if [ -d "$tmpdir" ]; then
    s=$(get_dir_size_bytes "$tmpdir") || s=0
    total=$((total + s))
  fi
  if [ -n "$cachedir" ] && [ -d "$cachedir" ]; then
    s=$(get_dir_size_bytes "$cachedir") || s=0
    total=$((total + s))
  fi
  CAT_SIZES[4]=$total
}

scan_developer() {
  local total=0
  local deriveddata="$HOME/Library/Developer/Xcode/DerivedData"
  if [ -d "$deriveddata" ]; then
    local s=0
    s=$(get_dir_size_bytes "$deriveddata") || s=0
    total=$((total + s))
  fi
  CAT_SIZES[5]=$total
}

scan_trash() {
  local s; s=$(get_dir_size_bytes "$HOME/.Trash") || s=0
  CAT_SIZES[6]=$s
}

scan_browser_cache() {
  local total=0
  local d
  for d in "${BROWSER_CACHE_TOPDIRS[@]}"; do
    local path="$HOME/Library/Caches/$d"
    [ -e "$path" ] || continue
    local s=0
    s=$(get_size_bytes "$path") || s=0
    total=$((total + s))
  done
  CAT_SIZES[7]=$total
}

scan_browser_full() {
  local total=0
  local d
  for d in "${BROWSER_FULL_DIRS[@]}"; do
    [ -e "$d" ] || continue
    local s=0
    s=$(get_size_bytes "$d") || s=0
    total=$((total + s))
  done
  CAT_SIZES[8]=$total
}

scan_ios_backups() {
  local backup_dir="$HOME/Library/MobileSync/Backup"
  local s=0
  if [ -d "$backup_dir" ]; then
    s=$(get_dir_size_bytes "$backup_dir") || s=0
  fi
  CAT_SIZES[9]=$s
}

scan_app_uninstaller() {
  local total=0
  local app app_name s
  while IFS= read -r -d '' app; do
    app_name=$(basename "$app" .app)
    local dir
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

scan_mail_downloads() {
  local s=0
  if [ -d "$MAIL_DOWNLOADS_DIR" ]; then
    s=$(get_dir_size_bytes "$MAIL_DOWNLOADS_DIR") || s=0
  fi
  CAT_SIZES[11]=$s
}

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
  local qldir
  qldir="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null)com.apple.QuickLook.thumbnailcache"
  CAT_SIZES[$i]=$(get_dir_size_bytes "$qldir")
}
clean_quicklook_cache() {
  header "🖼️  QuickLook Cache Temizleniyor"
  if command -v qlmanage &>/dev/null; then
    qlmanage -r cache >/dev/null 2>&1 \
      && success "QuickLook thumbnail cache sıfırlandı" \
      || warn "qlmanage çalıştırılamadı"
  else
    warn "qlmanage bulunamadı"
  fi
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

scan_all() {
  header "🔍 Taranıyor..."
  local fns=()
  local _i
  for _i in "${!CAT_IDS[@]}"; do fns+=("$(cat_field "$_i" scan_fn)"); done
  local i
  for i in "${!fns[@]}"; do
    echo -ne "  ${DIM}${CAT_NAMES[$i]}...${NC}\r"
    "${fns[$i]}"
  done
  echo -e "  ${GREEN}Tarama tamamlandı.${NC}                              "
}

# ─── Tarama Tablosu ──────────────────────────────────────────────────────────
print_scan_table() {
  header "📊 Tarama Sonuçları"
  echo ""
  printf "  ${BOLD}%-3s  %-26s  %-12s  %s${NC}\n" "#" "Kategori" "Boyut" ""
  separator
  local total_bytes=0
  local i
  for i in "${!CAT_IDS[@]}"; do
    local sz_h; sz_h=$(format_bytes "${CAT_SIZES[$i]}")
    local sudo_tag=""
    [ "${CAT_NEEDS_SUDO[$i]}" -eq 1 ] && sudo_tag="${DIM}[sudo]${NC}"
    if [ "${CAT_SIZES[$i]}" -gt 0 ]; then
      printf "  ${GREEN}%-3s${NC}  %-26s  ${BOLD}%-12s${NC}  %b\n" \
        "$((i+1))" "${CAT_NAMES[$i]}" "$sz_h" "$sudo_tag"
    else
      printf "  ${DIM}%-3s  %-26s  %-12s  %b${NC}\n" \
        "$((i+1))" "${CAT_NAMES[$i]}" "—" "$sudo_tag"
    fi
    [ "${CAT_IN_TOTAL[$i]}" -eq 1 ] && total_bytes=$((total_bytes + CAT_SIZES[$i]))
  done
  separator
  local total_h; total_h=$(format_bytes "$total_bytes")
  printf "  ${BOLD}%-3s  %-26s  %-12s${NC}\n" "" "TAHMİNİ TOPLAM" "$total_h"
  echo ""
  info "Mevcut boş disk alanı: ${BOLD}$(get_free_disk)${NC}"
  echo ""
}

# ─── Temizleme Fonksiyonları ─────────────────────────────────────────────────
clean_user_cache() {
  header "🗑️  Kullanıcı Cache Temizleniyor (Tarayıcılar Hariç)"
  local item
  while IFS= read -r -d '' item; do
    is_browser_cache_dir "$item" && continue
    safe_rm_contents "$item" "$(basename "$item")"
  done < <(find "$HOME/Library/Caches" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
}

clean_browser_cache() {
  header "🌐 Tarayıcı Cache Temizleniyor (Çerezler Korunur)"
  local d
  for d in "${BROWSER_CACHE_TOPDIRS[@]}"; do
    local path="$HOME/Library/Caches/$d"
    [ -e "$path" ] || continue
    safe_rm_contents "$path" "$d"
  done
}

clean_browser_full() {
  header "⚠️  Tarayıcı Tüm Veriler Temizleniyor"

  # Tarayıcılar ve sistem çerez yolları
  local browser_keys=("safari" "cookies" "chrome" "firefox" "brave" "edge" "opera" "arc")
  local browser_names=("Safari" "Sistem Çerezleri" "Google Chrome" "Firefox" "Brave" "Microsoft Edge" "Opera" "Arc")
  local browser_paths=(
    "$HOME/Library/Safari"
    "$HOME/Library/Cookies"
    "$HOME/Library/Application Support/Google/Chrome"
    "$HOME/Library/Application Support/Firefox"
    "$HOME/Library/Application Support/BraveSoftware"
    "$HOME/Library/Application Support/Microsoft Edge"
    "$HOME/Library/Application Support/com.operasoftware.Opera"
    "$HOME/Library/Application Support/Arc"
  )

  if $JSON_MODE; then
    if [ -z "$BROWSER_FULL_CLEAN" ]; then
      info "Temizlenecek tarayıcı belirtilmedi, atlanıyor."
      return
    fi
    local IFS_OLD="$IFS"
    IFS=','
    local clean_browsers=($BROWSER_FULL_CLEAN)
    IFS="$IFS_OLD"

    local key
    for key in ${clean_browsers[@]+"${clean_browsers[@]}"}; do
      local i
      for i in "${!browser_keys[@]}"; do
        if [ "${browser_keys[$i]}" = "$key" ]; then
          local path="${browser_paths[$i]}"
          if [ -e "$path" ]; then
            safe_rm_contents "$path" "${browser_names[$i]} Profili"
          fi
        fi
      done
    done
    return
  fi

  # Interactive CLI Mode
  echo ""
  warn "DİKKAT: Tarayıcı tüm verilerini silmek ilgili tarayıcıdaki tüm oturumları kapatır ve verileri sıfırlar!"
  echo ""
  
  local avail_keys=()
  local avail_names=()
  local avail_paths=()
  local idx=1
  local i
  
  for i in "${!browser_keys[@]}"; do
    local path="${browser_paths[$i]}"
    if [ -e "$path" ]; then
      local sz_b; sz_b=$(get_size_bytes "$path") || sz_b=0
      local sz_h; sz_h=$(format_bytes "$sz_b")
      printf "  ${RED}%-3d${NC}  %-24s  %s\n" "$idx" "${browser_names[$i]}" "$sz_h"
      avail_keys+=("${browser_keys[$i]}")
      avail_names+=("${browser_names[$i]}")
      avail_paths+=("$path")
      idx=$((idx + 1))
    fi
  done

  if [ "${#avail_keys[@]}" -eq 0 ]; then
    info "Temizlenecek tarayıcı verisi bulunamadı."
    return
  fi

  echo ""
  echo -ne "  Sıfırlamak istediğiniz tarayıcı numaralarını girin (boşlukla) veya ${BOLD}none${NC}: "
  local selection; read -r selection
  
  if [ "$selection" = "none" ] || [ -z "$selection" ]; then
    info "Tarayıcı temizliği atlandı."
    return
  fi

  read -ra indices <<< "$selection"
  for num in ${indices[@]+"${indices[@]}"}; do
    local real_idx=$((num - 1))
    if [ "$real_idx" -ge 0 ] && [ "$real_idx" -lt "${#avail_keys[@]}" ]; then
      warn "Seçilen '${avail_names[$real_idx]}' profil verileri tamamen silinecek!"
      if confirm "Emin misiniz?"; then
        safe_rm_contents "${avail_paths[$real_idx]}" "${avail_names[$real_idx]} Profili"
      fi
    fi
  done
}

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
      [ -z "$uuid" ] && continue
      case "$uuid" in
        */*|*..*)
          err "Geçersiz UUID (path traversal girişimi): $uuid"
          continue
          ;;
      esac
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

clean_app_uninstaller() {
  header "🗑️  Uygulamalar Kaldırılıyor"
  if $JSON_MODE; then
    if [ -z "$APP_UNINSTALLER_CLEAN" ]; then
      info "Kaldırılacak uygulama belirtilmedi, atlanıyor."
      return
    fi
    local IFS_OLD="$IFS"
    IFS=','
    local clean_apps=($APP_UNINSTALLER_CLEAN)
    IFS="$IFS_OLD"
    local app_name
    for app_name in ${clean_apps[@]+"${clean_apps[@]}"}; do
      [ -z "$app_name" ] && continue
      case "$app_name" in
        */*|*..*)
          err "Geçersiz uygulama adı (path traversal girişimi): $app_name"
          continue
          ;;
      esac
      local app_path="/Applications/$app_name.app"
      if [ -d "$app_path" ]; then
        safe_rm "$app_path" "Uygulama: $app_name"
      fi
      local dir
      for dir in \
          "$HOME/Library/Application Support/$app_name" \
          "$HOME/Library/Caches/$app_name" \
          "$HOME/Library/Preferences/com.${app_name}.plist" \
          "$HOME/Library/Saved Application State/${app_name}.savedState"; do
        if [ -e "$dir" ]; then
          safe_rm "$dir" "Kalıntı: $dir"
        fi
      done
    done
    return
  fi
  info "Tam Uygulama Kaldırıcı yalnızca web arayüzü üzerinden kullanılabilir."
}

clean_mail_downloads() {
  header "📧 Mail İndirilenler Temizleniyor"
  if [ -d "$MAIL_DOWNLOADS_DIR" ]; then
    safe_rm_contents "$MAIL_DOWNLOADS_DIR" "Mail İndirilenler"
  else
    info "Mail İndirilenler klasörü bulunamadı."
  fi
}

clean_system_cache() {
  if ! $SUDO_AVAILABLE; then warn "Sudo yok, Sistem Cache atlandı."; return; fi
  header "🗑️  Sistem Cache Temizleniyor"
  local item
  while IFS= read -r -d '' item; do
    local sz_b; sz_b=$(sudo du -sk "$item" 2>/dev/null | awk '{print $1*1024}') || continue
    [ "$sz_b" -le 0 ] 2>/dev/null && continue
    local sz_h; sz_h=$(format_bytes "$sz_b")
    sudo rm -rf "$item" 2>/dev/null && {
      success "$(basename "$item"): ${BOLD}${sz_h}${NC} silindi"
      TOTAL_FREED=$((TOTAL_FREED + sz_b))
      TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
    } || err "$(basename "$item") silinemedi"
  done < <(sudo find /Library/Caches -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
}

clean_logs() {
  header "🗑️  Loglar Temizleniyor"
  safe_rm_contents "$HOME/Library/Logs" "~/Library/Logs"
  if $SUDO_AVAILABLE; then
    local item
    while IFS= read -r -d '' item; do
      local sz_b; sz_b=$(sudo du -sk "$item" 2>/dev/null | awk '{print $1*1024}') || continue
      [ "$sz_b" -le 0 ] 2>/dev/null && continue
      local sz_h; sz_h=$(format_bytes "$sz_b")
      sudo rm -rf "$item" 2>/dev/null && {
        success "$(basename "$item"): ${BOLD}${sz_h}${NC} silindi"
        TOTAL_FREED=$((TOTAL_FREED + sz_b))
        TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
      } || err "$(basename "$item") silinemedi"
    done < <(sudo find /Library/Logs -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
  fi
}

clean_temp_files() {
  header "🗑️  Geçici Dosyalar Temizleniyor"
  local tmpdir; tmpdir=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || echo "${TMPDIR:-/tmp}")
  local cachedir; cachedir=$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || echo "")
  safe_rm_contents "$tmpdir" "Kullanıcı Temp"
  if [ -n "$cachedir" ] && [ -d "$cachedir" ]; then
    safe_rm_contents "$cachedir" "Kullanıcı Var Cache"
  fi
}

clean_trash() {
  header "🗑️  Çöp Kutusu Temizleniyor"
  safe_rm_contents "$HOME/.Trash" "~/.Trash"
}

clean_app_leftovers() {
  header "📂 Uygulama Kalıntıları Temizleniyor"

  # Eğer JSON modundaysak ve temizlenecek alt dizinler belirtilmişse
  if $JSON_MODE; then
    if [ -z "$APP_LEFTOVERS_CLEAN" ]; then
      info "Temizlenecek alt dizin belirtilmedi, atlanıyor."
      return
    fi
    local IFS_OLD="$IFS"
    IFS=','
    local clean_dirs=($APP_LEFTOVERS_CLEAN)
    IFS="$IFS_OLD"
    
    local d
    for d in "${clean_dirs[@]}"; do
      # Güvenlik: Dizin yolunu kontrol et, sadece ~/Library/Application Support altında olmalı
      local full_path="$HOME/Library/Application Support/$d"
      if [ -d "$full_path" ]; then
        safe_rm "$full_path" "$d (Application Support)"
      fi
      # Tercih dosyası (.plist) varsa onu da temizle
      local plist_path="$HOME/Library/Preferences/$d.plist"
      case "$d" in
        com.apple.*|com.google.*|com.microsoft.*) ;;
        *)
          if [ -e "$plist_path" ]; then
            safe_rm "$plist_path" "$d.plist (Preferences)"
          fi
          ;;
      esac
    done
    return
  fi

  # Interactive CLI Mode
  echo ""
  echo -e "  ${BOLD}~/Library/Application Support/ klasörleri (Analiz Edildi):${NC}"
  echo ""
  
  local as_paths=()
  local as_names=()
  local as_orphaned=()
  local idx=1
  local item
  
  while IFS= read -r -d '' item; do
    local base; base=$(basename "$item")
    case "$base" in
      com.apple.*|Apple|MobileSync|SyncServices|CrashReporter|\
      Audio|Fonts|Compositions|ColorSync|Spelling|Dictionaries|\
      AddressBook|Calendars|Mail|Messages|Safari|\
      CallHistoryDB|CallHistoryTransactions|CloudDocs|Dock|\
      iCloud|Knowledge|Network|VirtualMachines|DiskImages) continue ;;
    esac

    local sz_b; sz_b=$(get_size_bytes "$item") || sz_b=0
    local sz_h; sz_h=$(format_bytes "$sz_b")
    
    local is_installed=0
    if is_app_installed "$base"; then
      is_installed=1
    fi
    
    if [ "$is_installed" -eq 0 ]; then
      printf "  ${GREEN}%-3d${NC}  %-42s  %-8s  ${GREEN}[Kalıntı - Önerilen]${NC}\n" "$idx" "$base" "$sz_h"
      as_orphaned+=("true")
    else
      printf "  ${DIM}%-3d  %-42s  %-8s  [Yüklü - Korunuyor]${NC}\n" "$idx" "$base" "$sz_h"
      as_orphaned+=("false")
    fi
    as_paths+=("$item")
    as_names+=("$base")
    idx=$((idx + 1))
  done < <(find "$HOME/Library/Application Support" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)

  echo ""
  echo -e "  Numara girin (boşlukla), ${BOLD}orphans${NC} = sadece kalıntılar, ${BOLD}none${NC} = atla:"
  echo -ne "  > "
  local selection; read -r selection

  if [ "$selection" != "none" ] && [ -n "$selection" ]; then
    local indices=()
    if [ "$selection" = "orphans" ]; then
      local j; for j in "${!as_paths[@]}"; do
        if [ "${as_orphaned[$j]}" = "true" ]; then
          indices+=("$((j+1))")
        fi
      done
    elif [ "$selection" = "all" ]; then
      warn "UYARI: 'all' seçeneği yüklü uygulamaların (örn. Claude) ayarlarını da silecektir!"
      if confirm "Yüklü uygulamaların ayarlarını da silmek istediğinize emin misiniz?"; then
        local j; for j in "${!as_paths[@]}"; do indices+=("$((j+1))"); done
      else
        local j; for j in "${!as_paths[@]}"; do
          if [ "${as_orphaned[$j]}" = "true" ]; then
            indices+=("$((j+1))");
          fi
        done
        info "Sadece kalıntılar seçildi."
      fi
    else
      read -ra indices <<< "$selection"
    fi
    
    for num in ${indices[@]+"${indices[@]}"}; do
      local real_idx=$((num - 1))
      if [ "$real_idx" -ge 0 ] && [ "$real_idx" -lt "${#as_paths[@]}" ]; then
        local base_name="${as_names[$real_idx]}"
        safe_rm "${as_paths[$real_idx]}" "$base_name (Application Support)"
        local plist_path="$HOME/Library/Preferences/$base_name.plist"
        if [ -e "$plist_path" ]; then
          safe_rm "$plist_path" "$base_name.plist (Preferences)"
        fi
      fi
    done
  else
    info "Application Support atlandı."
  fi
}

clean_developer() {
  header "🛠  Geliştirici Verileri Temizleniyor"

  local deriveddata="$HOME/Library/Developer/Xcode/DerivedData"
  
  if $JSON_MODE; then
    if [ -z "$DEVELOPER_CLEAN" ]; then
      info "Temizlenecek geliştirici alt kategorisi belirtilmedi, atlanıyor."
      return
    fi
    local IFS_OLD="$IFS"
    IFS=','
    local clean_items=($DEVELOPER_CLEAN)
    IFS="$IFS_OLD"
    
    local item
    for item in ${clean_items[@]+"${clean_items[@]}"}; do
      if [ "$item" = "derived_data" ]; then
        if [ -d "$deriveddata" ]; then
          safe_rm_contents "$deriveddata" "Xcode DerivedData"
        fi
      elif [ "$item" = "broken_links" ]; then
        clean_broken_symlinks_silent
      elif [ "$item" = "brew_cache" ]; then
        local brew_path=""
        if command -v brew &>/dev/null; then
          brew_path=$(brew --cache 2>/dev/null || echo "")
        fi
        [ -z "$brew_path" ] && brew_path="$HOME/Library/Caches/Homebrew"
        [ -d "$brew_path" ] && safe_rm_contents "$brew_path" "Homebrew Cache"
      elif [ "$item" = "docker_prune" ]; then
        if command -v docker &>/dev/null; then
          docker system prune -a -f --volumes 2>/dev/null || true
          success "Docker verileri temizlendi."
        else
          info "Docker bulunamadı, atlanıyor."
        fi
      elif [ "$item" = "npm_cache" ]; then
        local npm_cache="$HOME/.npm/_cacache"
        [ -d "$npm_cache" ] && safe_rm_contents "$npm_cache" "npm Cache"
      elif [ "$item" = "pip_cache" ]; then
        local pip_cache="$HOME/Library/Caches/pip"
        [ -d "$pip_cache" ] && safe_rm_contents "$pip_cache" "pip Cache"
      elif [ "$item" = "device_support" ]; then
        safe_rm_contents "$HOME/Library/Developer/Xcode/iOS DeviceSupport" "iOS DeviceSupport"
      elif [ "$item" = "coresim_caches" ]; then
        safe_rm_contents "$HOME/Library/Developer/CoreSimulator/Caches" "CoreSimulator Caches"
      elif [ "$item" = "xcode_archives" ]; then
        safe_rm_contents "$HOME/Library/Developer/Xcode/Archives" "Xcode Archives"
      elif [ "$item" = "cocoapods_cache" ]; then
        safe_rm_contents "$HOME/Library/Caches/CocoaPods" "CocoaPods Cache"
      elif [ "$item" = "pnpm_cache" ]; then
        safe_rm_contents "$HOME/Library/pnpm/store" "pnpm Store"
      elif [ "$item" = "yarn_cache" ]; then
        safe_rm_contents "$HOME/Library/Caches/Yarn" "Yarn Cache"
      elif [ "$item" = "gradle_cache" ]; then
        safe_rm_contents "$HOME/.gradle/caches" "Gradle Cache"
      elif [ "$item" = "maven_repo" ]; then
        safe_rm_contents "$HOME/.m2/repository" "Maven Repository"
      elif [ "$item" = "simctl_unavailable" ]; then
        if command -v xcrun &>/dev/null; then
          xcrun simctl delete unavailable >/dev/null 2>&1 \
            && success "Erişilmez simülatörler silindi" \
            || warn "simctl çalıştırılamadı"
        fi
      fi
    done
    return
  fi

  # Interactive CLI Mode
  if [ -d "$deriveddata" ]; then
    if confirm "Xcode DerivedData temizlensin mi?"; then
      safe_rm_contents "$deriveddata" "Xcode DerivedData"
    fi
  else
    info "Xcode DerivedData bulunamadı."
  fi

  clean_broken_symlinks_interactive
}

clean_broken_symlinks_silent() {
  local scan_dirs=()
  [ -d "/usr/local/bin" ]    && scan_dirs+=("/usr/local/bin")
  [ -d "/opt/homebrew/bin" ] && scan_dirs+=("/opt/homebrew/bin")
  [ -d "$HOME/.local/bin" ]  && scan_dirs+=("$HOME/.local/bin")
  [ -d "$HOME/.config" ]     && scan_dirs+=("$HOME/.config")
  [ -d "$HOME/bin" ]         && scan_dirs+=("$HOME/bin")

  local broken_links=()
  local dir
  for dir in ${scan_dirs[@]+"${scan_dirs[@]}"}; do
    local link
    while IFS= read -r link; do
      [ -n "$link" ] && broken_links+=("$link")
    done < <(find "$dir" -maxdepth 3 -type l ! -e 2>/dev/null)
  done

  for link in ${broken_links[@]+"${broken_links[@]}"}; do
    rm -f "$link" 2>/dev/null && {
      TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
    }
  done
}

clean_broken_symlinks_interactive() {
  echo ""
  echo -e "  ${BOLD}Kırık sembolik linkler taranıyor...${NC}"
  local scan_dirs=()
  [ -d "/usr/local/bin" ]    && scan_dirs+=("/usr/local/bin")
  [ -d "/opt/homebrew/bin" ] && scan_dirs+=("/opt/homebrew/bin")
  [ -d "$HOME/.local/bin" ]  && scan_dirs+=("$HOME/.local/bin")
  [ -d "$HOME/.config" ]     && scan_dirs+=("$HOME/.config")
  [ -d "$HOME/bin" ]         && scan_dirs+=("$HOME/bin")

  local broken_links=()
  local dir
  for dir in ${scan_dirs[@]+"${scan_dirs[@]}"}; do
    local link
    while IFS= read -r link; do
      [ -n "$link" ] && broken_links+=("$link")
    done < <(find "$dir" -maxdepth 3 -type l ! -e 2>/dev/null)
  done

  if [ "${#broken_links[@]}" -eq 0 ]; then
    info "Kırık sembolik link bulunamadı."
    return
  fi

  echo ""
  warn "Kırık sembolik linkler (${#broken_links[@]} adet):"
  local link
  for link in ${broken_links[@]+"${broken_links[@]}"}; do
    printf "  ${DIM}  %s → %s${NC}\n" "$link" "$(readlink "$link" 2>/dev/null || echo '?')"
  done
  echo ""

  if confirm "Tüm kırık sembolik linkler silinsin mi?"; then
    for link in ${broken_links[@]+"${broken_links[@]}"}; do
      rm -f "$link" 2>/dev/null && {
        success "$(basename "$link") silindi"
        TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
      } || err "$(basename "$link") silinemedi"
    done
  fi
}

# ─── Ana Akış ────────────────────────────────────────────────────────────────
category_selector() {
  echo ""
  echo -e "  ${BOLD}Temizlenecek kategorileri seçin:${NC}"
  echo ""
  local i
  for i in "${!CAT_IDS[@]}"; do
    local sz_h; sz_h=$(format_bytes "${CAT_SIZES[$i]}")
    local sudo_tag=""
    [ "${CAT_NEEDS_SUDO[$i]}" -eq 1 ] && sudo_tag=" ${DIM}[sudo]${NC}"
    if [ "${CAT_SIZES[$i]}" -gt 0 ]; then
      printf "  ${GREEN}%d${NC}  %-26s  %s%b\n" "$((i+1))" "${CAT_NAMES[$i]}" "$sz_h" "$sudo_tag"
    else
      printf "  ${DIM}%d  %-26s  —%b${NC}\n" "$((i+1))" "${CAT_NAMES[$i]}" ""
    fi
  done
  echo ""
  echo -ne "  Numara girin (boşlukla, örn. 1 4 7 8) veya ${BOLD}all${NC} (sadece güvenli olanlar): "
  local selection; read -r selection
  echo "$selection"
}

run_clean() {
  local selected_indices=("$@")
  local fn_map=()
  local _i
  for _i in "${!CAT_IDS[@]}"; do fn_map+=("$(cat_field "$_i" clean_fn)"); done
  local idx
  for idx in ${selected_indices[@]+"${selected_indices[@]}"}; do
    local real_idx=$((idx - 1))
    if [ "$real_idx" -ge 0 ] && [ "$real_idx" -lt "${#fn_map[@]}" ]; then
      if [ "${CAT_NEEDS_SUDO[$real_idx]}" -eq 1 ] && ! $SUDO_AVAILABLE; then
        warn "${CAT_NAMES[$real_idx]} atlandı (sudo gerekli)."
        continue
      fi
      "${fn_map[$real_idx]}"
    fi
  done
}

print_report() {
  header "📋 Temizlik Raporu"
  echo ""
  local freed_h; freed_h=$(format_bytes "$TOTAL_FREED")
  echo -e "  ${GREEN}✅ Temizlik tamamlandı!${NC}"
  echo ""
  printf "  ${BOLD}%-24s${NC} %s\n" "Kazanılan Alan:"   "$freed_h"
  printf "  ${BOLD}%-24s${NC} %s\n" "Temizlenen Öğe:"  "$TOTAL_ITEMS"
  printf "  ${BOLD}%-24s${NC} %s\n" "Mevcut Boş Alan:" "$(get_free_disk)"
  echo ""
}

# ─── JSON Çıktı Fonksiyonları (Web API) ──────────────────────────────────────
json_escape_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  echo "$s"
}

scan_app_leftovers_subitems_json() {
  local first=true
  local item base s sz_h is_orph
  while IFS= read -r -d '' item; do
    base=$(basename "$item")
    case "$base" in
      com.apple.*|Apple|MobileSync|SyncServices|CrashReporter|\
      Audio|Fonts|Compositions|ColorSync|Spelling|Dictionaries|\
      AddressBook|Calendars|Mail|Messages|Safari|\
      CallHistoryDB|CallHistoryTransactions|CloudDocs|Dock|\
      iCloud|Knowledge|Network|VirtualMachines|DiskImages) continue ;;
    esac
    s=$(get_size_bytes "$item") 2>/dev/null || s=0
    [ "$s" -le 0 ] && continue
    sz_h=$(format_bytes "$s")
    
    if is_app_installed "$base"; then
      is_orph="false"
    else
      is_orph="true"
    fi
    
    if [ "$first" = true ]; then
      first=false
    else
      echo ","
    fi
    local esc_base; esc_base=$(json_escape_str "$base")
    local esc_path; esc_path=$(json_escape_str "$item")
    echo -n "        {\"id\": \"$esc_base\", \"name\": \"$esc_base\", \"path\": \"$esc_path\", \"size_bytes\": $s, \"size_human\": \"$sz_h\", \"is_orphaned\": $is_orph}"
  done < <(find "$HOME/Library/Application Support" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)
}

# id, görünen ad, yol, risk → JSON alt-öğe satırı (LEADING virgüllü; yol yoksa hiçbir şey yazma)
emit_dev_subitem() {
  local id="$1" name="$2" path="$3" risk="$4"
  [ -e "$path" ] || return 0
  local s; s=$(get_size_bytes "$path") || s=0
  [ "$s" -le 0 ] 2>/dev/null && return 0
  local sz_h; sz_h=$(format_bytes "$s")
  local esc_name; esc_name=$(json_escape_str "$name")
  local esc_path; esc_path=$(json_escape_str "$path")
  echo "        ,{\"id\": \"$id\", \"name\": \"$esc_name\", \"path\": \"$esc_path\", \"size_bytes\": $s, \"size_human\": \"$sz_h\", \"risk\": \"$risk\", \"is_orphaned\": false}"
}

scan_developer_subitems_json() {
  local deriveddata="$HOME/Library/Developer/Xcode/DerivedData"
  local s_derived=0
  if [ -d "$deriveddata" ]; then
    s_derived=$(get_dir_size_bytes "$deriveddata")
  fi
  local sz_derived; sz_derived=$(format_bytes "$s_derived")
  local esc_derived_path; esc_derived_path=$(json_escape_str "$deriveddata")
  echo "        {\"id\": \"derived_data\", \"name\": \"Xcode DerivedData\", \"path\": \"$esc_derived_path\", \"size_bytes\": $s_derived, \"size_human\": \"$sz_derived\", \"is_orphaned\": false}"
  
  local scan_dirs=()
  [ -d "/usr/local/bin" ]    && scan_dirs+=("/usr/local/bin")
  [ -d "/opt/homebrew/bin" ] && scan_dirs+=("/opt/homebrew/bin")
  [ -d "$HOME/.local/bin" ]  && scan_dirs+=("$HOME/.local/bin")
  [ -d "$HOME/.config" ]     && scan_dirs+=("$HOME/.config")
  [ -d "$HOME/bin" ]         && scan_dirs+=("$HOME/bin")

  local broken_count=0
  local dir
  for dir in ${scan_dirs[@]+"${scan_dirs[@]}"}; do
    local link
    while IFS= read -r link; do
      [ -n "$link" ] && broken_count=$((broken_count + 1))
    done < <(find "$dir" -maxdepth 3 -type l ! -e 2>/dev/null)
  done
  
  local s_sym=$((broken_count * 1024))
  local sz_sym; sz_sym="$broken_count adet"
  echo "        ,{\"id\": \"broken_links\", \"name\": \"Kırık Sembolik Linkler\", \"path\": \"\", \"size_bytes\": $s_sym, \"size_human\": \"$sz_sym\", \"is_orphaned\": true}"

  # brew cache
  local brew_cache_path=""
  local s_brew=0
  if command -v brew &>/dev/null; then
    brew_cache_path=$(brew --cache 2>/dev/null || echo "")
  fi
  [ -z "$brew_cache_path" ] && brew_cache_path="$HOME/Library/Caches/Homebrew"
  [ -d "$brew_cache_path" ] && s_brew=$(get_dir_size_bytes "$brew_cache_path")
  local sz_brew; sz_brew=$(format_bytes "$s_brew")
  local esc_brew_path; esc_brew_path=$(json_escape_str "$brew_cache_path")
  echo "        ,{\"id\": \"brew_cache\", \"name\": \"Homebrew Cache\", \"path\": \"$esc_brew_path\", \"size_bytes\": $s_brew, \"size_human\": \"$sz_brew\", \"is_orphaned\": false}"

  # docker data
  local docker_dir="$HOME/Library/Containers/com.docker.docker/Data"
  local s_docker=0
  [ -d "$docker_dir" ] && s_docker=$(get_dir_size_bytes "$docker_dir")
  local sz_docker; sz_docker=$(format_bytes "$s_docker")
  local esc_docker_path; esc_docker_path=$(json_escape_str "$docker_dir")
  echo "        ,{\"id\": \"docker_prune\", \"name\": \"Docker Data\", \"path\": \"$esc_docker_path\", \"size_bytes\": $s_docker, \"size_human\": \"$sz_docker\", \"is_orphaned\": false}"

  # npm cache
  local npm_cache_path="$HOME/.npm/_cacache"
  local s_npm=0
  [ -d "$npm_cache_path" ] && s_npm=$(get_dir_size_bytes "$npm_cache_path")
  local sz_npm; sz_npm=$(format_bytes "$s_npm")
  local esc_npm_path; esc_npm_path=$(json_escape_str "$npm_cache_path")
  echo "        ,{\"id\": \"npm_cache\", \"name\": \"npm Cache\", \"path\": \"$esc_npm_path\", \"size_bytes\": $s_npm, \"size_human\": \"$sz_npm\", \"is_orphaned\": false}"

  # pip cache
  local pip_cache_path="$HOME/Library/Caches/pip"
  local s_pip=0
  [ -d "$pip_cache_path" ] && s_pip=$(get_dir_size_bytes "$pip_cache_path")
  local sz_pip; sz_pip=$(format_bytes "$s_pip")
  local esc_pip_path; esc_pip_path=$(json_escape_str "$pip_cache_path")
  echo "        ,{\"id\": \"pip_cache\", \"name\": \"pip Cache\", \"path\": \"$esc_pip_path\", \"size_bytes\": $s_pip, \"size_human\": \"$sz_pip\", \"is_orphaned\": false}"

  emit_dev_subitem "device_support" "iOS DeviceSupport" \
    "$HOME/Library/Developer/Xcode/iOS DeviceSupport" "safe"
  emit_dev_subitem "coresim_caches" "CoreSimulator Caches" \
    "$HOME/Library/Developer/CoreSimulator/Caches" "safe"
  emit_dev_subitem "xcode_archives" "Xcode Archives" \
    "$HOME/Library/Developer/Xcode/Archives" "caution"
  emit_dev_subitem "cocoapods_cache" "CocoaPods Cache" \
    "$HOME/Library/Caches/CocoaPods" "safe"
  emit_dev_subitem "pnpm_cache" "pnpm Store" \
    "$HOME/Library/pnpm/store" "safe"
  emit_dev_subitem "yarn_cache" "Yarn Cache" \
    "$HOME/Library/Caches/Yarn" "safe"
  emit_dev_subitem "gradle_cache" "Gradle Cache" \
    "$HOME/.gradle/caches" "caution"
  emit_dev_subitem "maven_repo" "Maven Repository" \
    "$HOME/.m2/repository" "caution"
}

scan_browser_full_subitems_json() {
  local first=true
  local d path s sz_h esc_id esc_path
  
  local browser_keys=("safari" "cookies" "chrome" "firefox" "brave" "edge" "opera" "arc")
  local browser_names=("Safari" "Sistem Çerezleri" "Google Chrome" "Firefox" "Brave" "Microsoft Edge" "Opera" "Arc")
  local browser_paths=(
    "$HOME/Library/Safari"
    "$HOME/Library/Cookies"
    "$HOME/Library/Application Support/Google/Chrome"
    "$HOME/Library/Application Support/Firefox"
    "$HOME/Library/Application Support/BraveSoftware"
    "$HOME/Library/Application Support/Microsoft Edge"
    "$HOME/Library/Application Support/com.operasoftware.Opera"
    "$HOME/Library/Application Support/Arc"
  )
  
  local i
  for i in "${!browser_keys[@]}"; do
    path="${browser_paths[$i]}"
    [ -e "$path" ] || continue
    s=$(get_size_bytes "$path") || s=0
    [ "$s" -le 0 ] && continue
    sz_h=$(format_bytes "$s")
    esc_id="${browser_keys[$i]}"
    esc_path=$(json_escape_str "$path")
    local esc_name; esc_name=$(json_escape_str "${browser_names[$i]}")
    
    if [ "$first" = true ]; then
      first=false
    else
      echo ","
    fi
    echo -n "        {\"id\": \"$esc_id\", \"name\": \"$esc_name\", \"path\": \"$esc_path\", \"size_bytes\": $s, \"size_human\": \"$sz_h\", \"is_orphaned\": false}"
  done
}

scan_ios_backups_subitems_json() {
  local backup_dir="$HOME/Library/MobileSync/Backup"
  [ -d "$backup_dir" ] || return 0
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

do_flush_dns() {
  JSON_MODE=true
  local ok=true
  dscacheutil -flushcache 2>/dev/null || ok=false
  killall -HUP mDNSResponder 2>/dev/null || ok=false
  if $ok; then
    printf '{"success":true,"message":"DNS önbelleği temizlendi."}\n'
  else
    printf '{"success":false,"error":"DNS temizleme başarısız."}\n'
  fi
}

do_purge_ram() {
  JSON_MODE=true
  if purge 2>/dev/null; then
    printf '{"success":true,"message":"RAM önbelleği temizlendi."}\n'
  else
    printf '{"success":false,"error":"RAM temizleme başarısız (sudo gerekebilir)."}\n'
  fi
}

do_clean_launchagents() {
  JSON_MODE=true
  local removed=0
  local errors=()
  local dirs=(
    "$HOME/Library/LaunchAgents"
    "/Library/LaunchAgents"
    "/Library/LaunchDaemons"
  )
  local d plist
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    while IFS= read -r -d '' plist; do
      if ! plutil -lint "$plist" &>/dev/null; then
        rm -f "$plist" 2>/dev/null && removed=$((removed + 1)) || errors+=("$plist")
      fi
    done < <(find "$d" -maxdepth 1 -name "*.plist" -print0 2>/dev/null)
  done
  printf '{"success":true,"removed":%d,"errors":%d}\n' "$removed" "${#errors[@]}"
}

do_thin_snapshots_json() {
  JSON_MODE=true
  local before after note="ok"
  before=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple.TimeMachine" || true)
  [ -z "$before" ] && before=0
  if [ "${APPLE_CLEANUP_DRYRUN:-0}" = "1" ]; then
    note="dryrun"
    after=$before
  else
    # 10GB hedef, urgency 4 (agresif). Yetki/snapshot yoksa sessiz başarısız.
    tmutil thinLocalSnapshots / 10000000000 4 >/dev/null 2>&1 || note="yetki_yok_veya_snapshot_yok"
    after=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple.TimeMachine" || true)
    [ -z "$after" ] && after=0
  fi
  printf '{"success":true,"snapshots_before":%s,"snapshots_after":%s,"note":"%s","disk_free":"%s"}\n' \
    "$before" "$after" "$note" "$(get_free_disk)"
}

get_app_bundle_id() {
  local app_path="$1"
  local plist="$app_path/Contents/Info.plist"
  [ -f "$plist" ] || { echo ""; return; }
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || echo ""
}

scan_app_uninstaller_subitems_json() {
  local first=true
  local app app_name bundle_id leftover_total s sz_h esc_name esc_bundle
  while IFS= read -r -d '' app; do
    app_name=$(basename "$app" .app)
    bundle_id=$(get_app_bundle_id "$app")
    leftover_total=0
    local dir
    for dir in \
        "$HOME/Library/Application Support/$app_name" \
        "$HOME/Library/Caches/$app_name" \
        "$HOME/Library/Preferences/${bundle_id}.plist" \
        "$HOME/Library/Saved Application State/${bundle_id}.savedState"; do
      [ -e "$dir" ] || continue
      s=$(get_size_bytes "$dir") || s=0
      leftover_total=$((leftover_total + s))
    done
    sz_h=$(format_bytes "$leftover_total")
    esc_name=$(json_escape_str "$app_name")
    esc_bundle=$(json_escape_str "$bundle_id")
    if [ "$first" = true ]; then
      first=false
    else
      echo ","
    fi
    echo -n "        {\"id\": \"$esc_name\", \"name\": \"$esc_name\", \"bundle_id\": \"$esc_bundle\", \"size_bytes\": $leftover_total, \"size_human\": \"$sz_h\", \"is_orphaned\": false}"
  done < <(find /Applications -maxdepth 1 -name "*.app" -print0 2>/dev/null | sort -z)
}

scan_mail_downloads_subitems_json() {
  local total=0
  local f sz_h esc_name s
  if [ -d "$MAIL_DOWNLOADS_DIR" ]; then
    while IFS= read -r -d '' f; do
      s=$(get_size_bytes "$f") || s=0
      total=$((total + s))
      sz_h=$(format_bytes "$s")
      esc_name=$(json_escape_str "$(basename "$f")")
      echo -n "        {\"id\": \"$esc_name\", \"name\": \"$esc_name\", \"path\": \"\", \"size_bytes\": $s, \"size_human\": \"$sz_h\", \"is_orphaned\": false}"
      echo ","
    done < <(find "$MAIL_DOWNLOADS_DIR" -maxdepth 1 -mindepth 1 -print0 2>/dev/null | sort -z)
  fi
}

do_scan_json() {
  SUDO_AVAILABLE=false
  scan_all >/dev/null 2>&1

  local total_bytes=0
  local i
  for i in "${!CAT_IDS[@]}"; do
    [ "${CAT_IN_TOTAL[$i]}" -eq 1 ] && total_bytes=$((total_bytes + CAT_SIZES[$i]))
  done

  local total_h; total_h=$(format_bytes "$total_bytes")

  cat <<ENDJSON
{
  "success": true,
  "scan": {
ENDJSON
  for i in "${!CAT_IDS[@]}"; do
    local id="${CAT_IDS[$i]}"
    local sz_h; sz_h=$(format_bytes "${CAT_SIZES[$i]}")
    local needs_sudo="false"
    [ "${CAT_NEEDS_SUDO[$i]}" -eq 1 ] && needs_sudo="true"
    
    echo "    \"$id\": {"
    echo "      \"size_bytes\": ${CAT_SIZES[$i]},"
    echo "      \"size_human\": \"$sz_h\","
    echo "      \"needs_sudo\": $needs_sudo,"
    echo "      \"risk\": \"${CAT_RISKS[$i]}\""

    if [ "$id" = "app_leftovers" ]; then
      echo "      ,\"subitems\": ["
      scan_app_leftovers_subitems_json
      echo ""
      echo "      ]"
    elif [ "$id" = "developer" ]; then
      echo "      ,\"subitems\": ["
      scan_developer_subitems_json
      echo ""
      echo "      ]"
    elif [ "$id" = "browser_full" ]; then
      echo "      ,\"subitems\": ["
      scan_browser_full_subitems_json
      echo ""
      echo "      ]"
    elif [ "$id" = "ios_backups" ]; then
      echo "      ,\"subitems\": ["
      scan_ios_backups_subitems_json
      echo ""
      echo "      ]"
    elif [ "$id" = "app_uninstaller" ]; then
      echo "      ,\"subitems\": ["
      scan_app_uninstaller_subitems_json
      echo ""
      echo "      ]"
    elif [ "$id" = "mail_downloads" ]; then
      echo "      ,\"subitems\": ["
      scan_mail_downloads_subitems_json
      echo "      ]"
    fi
    
    local comma=","
    [ "$i" -eq $((${#CAT_IDS[@]} - 1)) ] && comma=""
    echo "    }${comma}"
  done
  cat <<ENDJSON
  },
  "total_bytes": $total_bytes,
  "total_human": "$total_h",
  "disk_free": "$(get_free_disk)",
  "macos_version": "$(sw_vers -productVersion 2>/dev/null || echo 'unknown')",
  "user": "$(whoami)"
}
ENDJSON
}

do_clean_json() {
  local cats_csv="$1"
  SUDO_AVAILABLE=false
  JSON_MODE=true

  # Kategori numaralarını parse et
  local IFS_OLD="$IFS"
  IFS=','
  local cat_nums=($cats_csv)
  IFS="$IFS_OLD"

  # Önce tarama yap
  scan_all >/dev/null 2>&1

  # Kayıtları resetle
  TOTAL_FREED=0
  TOTAL_ITEMS=0
  CLEAN_RESULTS=()

  # Gerçek kazanç ölçümü için temizlik öncesi boş alan (KB, available on /)
  local df_before
  df_before=$(df -k / 2>/dev/null | awk 'NR==2 {print $4}')

  # Temizleme fonksiyon eşleşmesi
  local fn_map=()
  local _i
  for _i in "${!CAT_IDS[@]}"; do fn_map+=("$(cat_field "$_i" clean_fn)"); done

  local idx
  for idx in ${cat_nums[@]+"${cat_nums[@]}"}; do
    local real_idx=$((idx - 1))
    if [ "$real_idx" -ge 0 ] && [ "$real_idx" -lt "${#fn_map[@]}" ]; then
      local fn="${fn_map[$real_idx]}"
      if [ -n "$fn" ]; then
        local before_freed=$TOTAL_FREED
        "$fn" >/dev/null 2>&1 || true
        local after_freed=$TOTAL_FREED
        local cat_freed=$((after_freed - before_freed))
        local cat_freed_h; cat_freed_h=$(format_bytes "$cat_freed")
        CLEAN_RESULTS+=("${CAT_IDS[$real_idx]}|$cat_freed|$cat_freed_h|ok")
      else
        CLEAN_RESULTS+=("${CAT_IDS[$real_idx]}|0|0 B|skipped")
      fi
    fi
  done

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
  echo '  "details": ['

  local j=0
  for entry in ${CLEAN_RESULTS[@]+"${CLEAN_RESULTS[@]}"}; do
    IFS='|' read -r cat_id freed freed_h status <<< "$entry"
    local comma=","
    [ $((j + 1)) -eq ${#CLEAN_RESULTS[@]} ] && comma=""
    echo "    {\"category\": \"$cat_id\", \"freed\": \"$freed_h\", \"status\": \"$status\"}${comma}"
    j=$((j + 1))
  done

  echo '  ],'
  echo '  "errors": []'
  echo '}'
}

do_status_json() {
  cat <<ENDJSON
{
  "status": "ready",
  "disk_free": "$(get_free_disk)",
  "macos_version": "$(sw_vers -productVersion 2>/dev/null || echo 'unknown')",
  "user": "$(whoami)"
}
ENDJSON
}

do_spotlight_reindex() {
  (sudo mdutil -i off / 2>/dev/null || true
   sudo mdutil -E    / 2>/dev/null || true
   sudo mdutil -i on / 2>/dev/null || true) >/dev/null 2>&1 &
  disown
  echo '{"success": true, "status": "started", "message": "Spotlight yeniden indeksleme arka planda başlatıldı."}'
}

# ─── Ana Akış ────────────────────────────────────────────────────────────────
main() {
  local args=("$@")
  local i=0
  local clean_csv=""
  
  while [ $i -lt ${#args[@]} ]; do
    case "${args[$i]}" in
      --scan-json)
        do_scan_json
        exit 0
        ;;
      --status-json)
        do_status_json
        exit 0
        ;;
      --spotlight-reindex)
        do_spotlight_reindex
        exit 0
        ;;
      --clean-json)
        i=$((i + 1))
        clean_csv="${args[$i]}"
        ;;
      --app-leftovers)
        i=$((i + 1))
        APP_LEFTOVERS_CLEAN="${args[$i]}"
        ;;
      --browser-full-sub)
        i=$((i + 1))
        BROWSER_FULL_CLEAN="${args[$i]}"
        ;;
      --developer-sub)
        i=$((i + 1))
        DEVELOPER_CLEAN="${args[$i]}"
        ;;
      --ios-backups-sub)
        i=$((i + 1))
        IOS_BACKUPS_CLEAN="${args[$i]}"
        ;;
      --app-uninstaller-sub)
        i=$((i + 1))
        APP_UNINSTALLER_CLEAN="${args[$i]}"
        ;;
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
      --thin-snapshots-json)
        do_thin_snapshots_json
        exit 0
        ;;
      --help|-h)
        echo ""
        echo -e "${BOLD}clean_mac v${VERSION}${NC} — macOS Sistem Temizleyici (Güvenli Sürüm)"
        echo ""
        echo "Kullanım: bash clean_mac.sh"
        echo ""
        echo -e "${BOLD}Kategoriler:${NC}"
        echo "  1  Kullanıcı Cache       ~/Library/Caches/* (Tarayıcılar hariç)"
        echo "  2  Sistem Cache          /Library/Caches/*          [sudo]"
        echo "  3  Uygulama Kalıntıları  ~/Library/Application Support/ + Preferences"
        echo "  4  Loglar                ~/Library/Logs/* + /Library/Logs/*"
        echo "  5  Geçici Dosyalar       \$TMPDIR + user var/folders"
        echo "  6  Geliştirici           Xcode DerivedData + kırık symlink'ler"
        echo "  7  Çöp Kutusu            ~/.Trash/*"
        echo "  8  Tarayıcı Cache        Tarayıcı önbellekleri (Güvenli)"
        echo "  9  Tarayıcı Tüm Veri     Tarayıcı profilleri, çerezler [Oturumlar Kapanır!]"
        echo ""
        echo -e "${BOLD}Web API:${NC}"
        echo "  --scan-json              Tarama sonuçlarını JSON döner"
        echo "  --clean-json 1,3,7       Belirtilen kategorileri temizler, JSON döner"
        echo "  --app-leftovers 'd1,d2'  Silinecek kalıntı klasör isimleri"
        echo "  --browser-full-sub 'c,s' Sıfırlanacak tarayıcı kodları (chrome, safari...)"
        echo "  --developer-sub 'd,b'    Xcode DerivedData (derived_data) veya Kırık Symlinkler (broken_links)"
        echo "  --status-json            Sistem bilgisini JSON döner"
        echo "  --thin-snapshots-json    Yerel snapshot'ları inceltir, JSON döner"
        echo ""
        echo "Not: Downloads klasörüne dokunulmaz."
        echo ""
        exit 0
        ;;
    esac
    i=$((i + 1))
  done

  # Eğer clean_csv argümanı yakalandıysa JSON modda çalıştır
  if [ -n "$clean_csv" ]; then
    do_clean_json "$clean_csv"
    exit 0
  fi

  # Terminal İnteraktif Mod
  clear
  header "🍎 clean_mac v${VERSION} — macOS Sistem Temizleyici"
  echo ""
  echo -e "  macOS     : $(sw_vers -productVersion 2>/dev/null || echo '?')"
  echo -e "  Kullanıcı : $(whoami)"
  echo -e "  Tarih     : $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  info "Bu betik ÖNCE tarar, silmeden önce onayınızı ister."
  warn "Kritik sistem dosyaları ve aktif uygulama oturumları korunur."
  echo ""

  sudo_check
  scan_all
  print_scan_table

  echo -e "  ${BOLD}Ne yapmak istersiniz?${NC}"
  echo ""
  echo -e "  ${GREEN}1${NC}  Sadece Kesinlikle Güvenli Dosyaları Hızlı Temizle (Önbellek, Log, Temp, Sepet vb.)"
  echo -e "  ${GREEN}2${NC}  Kategori Seçerek Temizle (Uygulama Ayarları / Tarayıcı Oturumları Seçmeli)"
  echo -e "  ${RED}3${NC}  İptal"
  echo ""
  echo -ne "  Seçiminiz [1/2/3]: "
  local choice; read -r choice

  case "$choice" in
    1)
      echo ""
      warn "Kesinlikle güvenli kategoriler (Önbellek, Log, Temp, Çöp Kutusu, Tarayıcı Caches) temizlenecek."
      confirm "Devam etmek istiyor musunuz?" || { echo ""; info "İptal edildi."; exit 0; }
      # Sadece güvenli kategorileri çalıştır: 1, 2 (varsa sudo), 4, 5, 7, 8
      run_clean 1 2 4 5 7 8
      ;;
    2)
      local raw_selection; raw_selection=$(category_selector)
      local selected_nums=()
      if [ "$raw_selection" = "all" ]; then
        selected_nums=(1 2 4 5 7 8)
      else
        read -ra selected_nums <<< "$raw_selection"
      fi
      if [ "${#selected_nums[@]}" -eq 0 ]; then
        info "Seçim yapılmadı. İptal edildi."
        exit 0
      fi
      echo ""
      confirm "Seçilen kategoriler temizlensin mi?" || { info "İptal edildi."; exit 0; }
      run_clean "${selected_nums[@]}"
      ;;
    *)
      echo ""
      info "İptal edildi."
      exit 0
      ;;
  esac

  print_report
}

main "$@"
