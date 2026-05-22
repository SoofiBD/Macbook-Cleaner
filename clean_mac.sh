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

# Paralel diziler — bash 3.2 (Monterey dahil tüm macOS) ile uyumlu
CAT_IDS=(user_cache system_cache app_leftovers logs temp_files developer trash browser_cache browser_full ios_backups)
CAT_NAMES=("Kullanıcı Cache" "Sistem Cache" "Uygulama Kalıntıları" \
            "Loglar" "Geçici Dosyalar" "Geliştirici" "Çöp Kutusu" \
            "Tarayıcı Cache" "Tarayıcı Tüm Veri" "iOS Yedekleri")
CAT_SIZES=(0 0 0 0 0 0 0 0 0 0)
CAT_NEEDS_SUDO=(0 1 0 0 0 0 0 0 0 0)

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
  local total=0
  local item
  while IFS= read -r -d '' item; do
    local s=0
    s=$(du -sk "$item" 2>/dev/null | awk '{print $1 * 1024}') || s=0
    total=$((total + s))
  done < <(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
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
      iCloud|Knowledge|Network|VirtualMachines|DiskImages) continue ;;
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

scan_all() {
  header "🔍 Taranıyor..."
  local fns=(scan_user_cache scan_system_cache scan_app_leftovers \
             scan_logs scan_temp_files scan_developer scan_trash \
             scan_browser_cache scan_browser_full scan_ios_backups)
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
    total_bytes=$((total_bytes + CAT_SIZES[$i]))
  done
  separator
  local total_h; total_h=$(format_bytes "$total_bytes")
  printf "  ${BOLD}%-3s  %-26s  %-12s${NC}\n" "" "TOPLAM" "$total_h"
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
  local fn_map=(clean_user_cache clean_system_cache clean_app_leftovers \
                clean_logs clean_temp_files clean_developer clean_trash \
                clean_browser_cache clean_browser_full clean_ios_backups)
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

do_scan_json() {
  SUDO_AVAILABLE=false
  scan_all >/dev/null 2>&1

  local total_bytes=0
  local i
  for i in "${!CAT_IDS[@]}"; do
    total_bytes=$((total_bytes + CAT_SIZES[$i]))
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
    echo "      \"needs_sudo\": $needs_sudo"
    
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

  # Temizleme fonksiyon eşleşmesi
  local fn_map=(clean_user_cache clean_system_cache clean_app_leftovers \
                clean_logs clean_temp_files clean_developer clean_trash \
                clean_browser_cache clean_browser_full clean_ios_backups)

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

  local freed_h; freed_h=$(format_bytes "$TOTAL_FREED")

  # JSON çıktı
  echo '{'
  echo '  "success": true,'
  echo "  \"freed_bytes\": $TOTAL_FREED,"
  echo "  \"freed_human\": \"$freed_h\","
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
