#!/usr/bin/env bash
# clean_mac.sh — macOS Genel Sistem Temizleyici
# Kullanım: bash clean_mac.sh
#   --scan-json           Tarama sonuçlarını JSON olarak döner (web API için)
#   --clean-json 1,3,7    Belirtilen kategorileri temizler, sonucu JSON döner
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

VERSION="1.0.0"
SUDO_AVAILABLE=false
TOTAL_FREED=0
TOTAL_ITEMS=0
JSON_MODE=false
CLEAN_RESULTS=()

# Paralel diziler — bash 3.2 (Monterey dahil tüm macOS) ile uyumlu
CAT_IDS=(user_cache system_cache app_leftovers logs temp_files developer trash)
CAT_NAMES=("Kullanıcı Cache" "Sistem Cache" "Uygulama Kalıntıları" \
            "Loglar" "Geçici Dosyalar" "Geliştirici" "Çöp Kutusu")
CAT_SIZES=(0 0 0 0 0 0 0)
CAT_NEEDS_SUDO=(0 1 0 0 0 0 0)

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

# ─── Tarama ─────────────────────────────────────────────────────────────────
scan_user_cache() {
  local total=0
  local item
  while IFS= read -r -d '' item; do
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
    s=$(get_size_bytes "$item") 2>/dev/null || s=0
    [ -z "$s" ] && s=0
    total=$((total + s))
  done < <(find "$HOME/Library/Application Support" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
  while IFS= read -r -d '' item; do
    base=$(basename "$item" .plist)
    case "$base" in
      com.apple.*|com.microsoft.*|com.google.*|NSGlobalDomain|.GlobalPreferences|loginwindow*)
        continue
        ;;
    esac
    s=$(get_size_bytes "$item") 2>/dev/null || s=0
    [ -z "$s" ] && s=0
    total=$((total + s))
  done < <(find "$HOME/Library/Preferences" -maxdepth 1 -name "*.plist" -print0 2>/dev/null)
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

scan_all() {
  header "🔍 Taranıyor..."
  local fns=(scan_user_cache scan_system_cache scan_app_leftovers \
             scan_logs scan_temp_files scan_developer scan_trash)
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
  header "🗑️  Kullanıcı Cache Temizleniyor"
  local item
  while IFS= read -r -d '' item; do
    safe_rm_contents "$item" "$(basename "$item")"
  done < <(find "$HOME/Library/Caches" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
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

# ─── App Leftovers Sub-Menü ──────────────────────────────────────────────────
clean_app_leftovers() {
  header "📂 Uygulama Kalıntıları"

  # ── Application Support ──
  echo ""
  echo -e "  ${BOLD}~/Library/Application Support/ klasörleri:${NC}"
  echo ""
  local as_paths=()
  local idx=1
  local item
  while IFS= read -r -d '' item; do
    local sz_b; sz_b=$(get_size_bytes "$item") || sz_b=0
    local sz_h; sz_h=$(format_bytes "$sz_b")
    printf "  ${GREEN}%-3d${NC}  %-42s  %s\n" "$idx" "$(basename "$item")" "$sz_h"
    as_paths+=("$item")
    idx=$((idx + 1))
  done < <(find "$HOME/Library/Application Support" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)

  echo ""
  echo -e "  Numara girin (boşlukla), ${BOLD}all${NC} = hepsi, ${BOLD}none${NC} = atla:"
  echo -ne "  > "
  local selection; read -r selection

  if [ "$selection" != "none" ] && [ -n "$selection" ]; then
    local indices=()
    if [ "$selection" = "all" ]; then
      local j; for j in "${!as_paths[@]}"; do indices+=("$((j+1))"); done
    else
      read -ra indices <<< "$selection"
    fi
    for num in "${indices[@]}"; do
      local real_idx=$((num - 1))
      if [ "$real_idx" -ge 0 ] && [ "$real_idx" -lt "${#as_paths[@]}" ]; then
        safe_rm "${as_paths[$real_idx]}" "$(basename "${as_paths[$real_idx]}")"
      fi
    done
  else
    info "Application Support atlandı."
  fi

  # ── Third-party Preferences ──
  echo ""
  echo -e "  ${BOLD}~/Library/Preferences/ (üçüncü taraf .plist):${NC}"
  echo ""
  local pl_paths=()
  idx=1
  while IFS= read -r -d '' item; do
    local base; base=$(basename "$item" .plist)
    case "$base" in
      com.apple.*|com.microsoft.*|com.google.*|NSGlobalDomain|.GlobalPreferences|loginwindow*) continue ;;
    esac
    local sz_b; sz_b=$(get_size_bytes "$item") || sz_b=0
    local sz_h; sz_h=$(format_bytes "$sz_b")
    printf "  ${GREEN}%-3d${NC}  %-52s  %s\n" "$idx" "$(basename "$item")" "$sz_h"
    pl_paths+=("$item")
    idx=$((idx + 1))
  done < <(find "$HOME/Library/Preferences" -maxdepth 1 -name "*.plist" -print0 2>/dev/null | sort -z)

  if [ "${#pl_paths[@]}" -eq 0 ]; then
    info "Üçüncü taraf .plist bulunamadı."
    return
  fi

  echo ""
  echo -ne "  Numaralar (boşlukla, all/none): "
  read -r selection

  if [ "$selection" = "none" ] || [ -z "$selection" ]; then
    info "Preferences atlandı."; return
  fi

  local indices=()
  if [ "$selection" = "all" ]; then
    local j; for j in "${!pl_paths[@]}"; do indices+=("$((j+1))"); done
  else
    read -ra indices <<< "$selection"
  fi

  for num in "${indices[@]}"; do
    local real_idx=$((num - 1))
    if [ "$real_idx" -ge 0 ] && [ "$real_idx" -lt "${#pl_paths[@]}" ]; then
      safe_rm "${pl_paths[$real_idx]}" "$(basename "${pl_paths[$real_idx]}")"
    fi
  done
}

# ─── Geliştirici + Broken Symlinks ──────────────────────────────────────────
clean_developer() {
  header "🛠️  Geliştirici Verileri Temizleniyor"

  # Xcode DerivedData
  local deriveddata="$HOME/Library/Developer/Xcode/DerivedData"
  if [ -d "$deriveddata" ]; then
    if confirm "Xcode DerivedData temizlensin mi?"; then
      safe_rm_contents "$deriveddata" "Xcode DerivedData"
    fi
  else
    info "Xcode DerivedData bulunamadı."
  fi

  # Broken symlinks
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
  for dir in "${scan_dirs[@]}"; do
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
  for link in "${broken_links[@]}"; do
    printf "  ${DIM}  %s → %s${NC}\n" "$link" "$(readlink "$link" 2>/dev/null || echo '?')"
  done
  echo ""

  if confirm "Tüm kırık sembolik linkler silinsin mi?"; then
    for link in "${broken_links[@]}"; do
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
  echo -ne "  Numara girin (boşlukla, örn. 1 3 7) veya ${BOLD}all${NC}: "
  local selection; read -r selection
  echo "$selection"
}

run_clean() {
  local selected_indices=("$@")
  local fn_map=(clean_user_cache clean_system_cache clean_app_leftovers \
                clean_logs clean_temp_files clean_developer clean_trash)
  local idx
  for idx in "${selected_indices[@]}"; do
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

do_scan_json() {
  # Sudo yok, interaktif input yok
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
    local sz_h; sz_h=$(format_bytes "${CAT_SIZES[$i]}")
    local needs_sudo="false"
    [ "${CAT_NEEDS_SUDO[$i]}" -eq 1 ] && needs_sudo="true"
    local comma=","
    [ "$i" -eq $((${#CAT_IDS[@]} - 1)) ] && comma=""
    cat <<ENDJSON
    "${CAT_IDS[$i]}": {"size_bytes": ${CAT_SIZES[$i]}, "size_human": "$sz_h", "needs_sudo": $needs_sudo}${comma}
ENDJSON
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

  # Temizleme — interaktif olmayan modda uygulama kalıntıları atlanır
  local fn_map=(clean_user_cache clean_system_cache "" \
                clean_logs clean_temp_files "" clean_trash)
  # Not: index 2 (app_leftovers) ve 5 (developer) interaktif, web'den atlanır

  local idx
  for idx in "${cat_nums[@]}"; do
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
  for entry in "${CLEAN_RESULTS[@]}"; do
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

# ─── Ana Akış ────────────────────────────────────────────────────────────────
main() {
  # JSON API modları (web arayüzü için)
  case "${1:-}" in
    --scan-json)
      do_scan_json
      exit 0
      ;;
    --clean-json)
      if [ -z "${2:-}" ]; then
        echo '{"success": false, "error": "Kategori listesi gerekli. Örnek: --clean-json 1,3,7"}'
        exit 1
      fi
      do_clean_json "$2"
      exit 0
      ;;
    --status-json)
      do_status_json
      exit 0
      ;;
  esac

  # --help / -h support
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo ""
    echo -e "${BOLD}clean_mac v${VERSION}${NC} — macOS Sistem Temizleyici"
    echo ""
    echo "Kullanım: bash clean_mac.sh"
    echo ""
    echo -e "${BOLD}Kategoriler:${NC}"
    echo "  1  Kullanıcı Cache       ~/Library/Caches/*"
    echo "  2  Sistem Cache          /Library/Caches/*          [sudo]"
    echo "  3  Uygulama Kalıntıları  ~/Library/Application Support/ + Preferences"
    echo "  4  Loglar                ~/Library/Logs/* + /Library/Logs/*"
    echo "  5  Geçici Dosyalar       \$TMPDIR + user var/folders"
    echo "  6  Geliştirici           Xcode DerivedData + kırık symlink'ler"
    echo "  7  Çöp Kutusu            ~/.Trash/*"
    echo ""
    echo -e "${BOLD}Web API:${NC}"
    echo "  --scan-json              Tarama sonuçlarını JSON döner"
    echo "  --clean-json 1,3,7       Belirtilen kategorileri temizler, JSON döner"
    echo "  --status-json            Sistem bilgisini JSON döner"
    echo ""
    echo "Not: Downloads klasörüne dokunulmaz."
    echo ""
    exit 0
  fi

  clear
  header "🍎 clean_mac v${VERSION} — macOS Sistem Temizleyici"
  echo ""
  echo -e "  macOS     : $(sw_vers -productVersion 2>/dev/null || echo '?')"
  echo -e "  Kullanıcı : $(whoami)"
  echo -e "  Tarih     : $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  info "Bu script ÖNCE tarar, silmeden önce onayınızı ister."
  warn "Kritik sistem dosyalarına dokunulmaz."
  echo ""

  sudo_check
  scan_all
  print_scan_table

  echo -e "  ${BOLD}Ne yapmak istersiniz?${NC}"
  echo ""
  echo -e "  ${GREEN}1${NC}  Hepsini Temizle"
  echo -e "  ${GREEN}2${NC}  Kategori Seçerek Temizle"
  echo -e "  ${RED}3${NC}  İptal"
  echo ""
  echo -ne "  Seçiminiz [1/2/3]: "
  local choice; read -r choice

  case "$choice" in
    1)
      echo ""
      warn "Tüm kategoriler temizlenecek. Bu işlem geri alınamaz."
      confirm "Devam etmek istiyor musunuz?" || { echo ""; info "İptal edildi."; exit 0; }
      run_clean 1 2 3 4 5 6 7
      ;;
    2)
      local raw_selection; raw_selection=$(category_selector)
      local selected_nums=()
      if [ "$raw_selection" = "all" ]; then
        selected_nums=(1 2 3 4 5 6 7)
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
