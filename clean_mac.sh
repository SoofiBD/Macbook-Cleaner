#!/usr/bin/env bash
# clean_mac.sh — macOS System Cleaner (Enterprise-Safe Edition)
# Usage: bash clean_mac.sh
#   --scan-json             Return scan results as JSON (web API)
#   --clean-json 1,3,7      Clean specified categories, return JSON
#   --app-leftovers "d1,d2" (JSON mode) App leftover dirs to clean
#   --browser-full-sub "chrome,safari"  (JSON mode) Browser profiles to reset
#   --developer-sub "derived_data"      (JSON mode) Developer sub-items to clean
#   --ios-backups-sub "uuid1,uuid2"     (JSON mode) iOS backup UUIDs to delete
#   --app-uninstaller-sub "App1,App2"   (JSON mode) Apps to uninstall
#   --status-json           Return system info as JSON
#   --flush-dns             Flush DNS cache
#   --purge-ram             Purge RAM cache
#   --launchagents-clean    Clean invalid LaunchAgents
#   --thin-snapshots-json   Thin local TM snapshots, return JSON
#   --spotlight-reindex     Rebuild Spotlight index
#   --lang en|tr            Set UI language (default: tr)
set -euo pipefail

# ─── Localization Engine (Bash 3.2 compatible — no assoc arrays) ─────────────
# Default language; override via --lang <code> or APPLE_CLEANUP_LANG env var
LANG_KEY="${APPLE_CLEANUP_LANG:-tr}"

L() {
  local key="$1"
  case "${LANG_KEY}::${key}" in
    # ── General UI ───────────────────────────────────────────
    tr::version_banner)       echo "macOS Sistem Temizleyici" ;;
    en::version_banner)       echo "macOS System Cleaner" ;;
    tr::scanning)             echo "Taranıyor..." ;;
    en::scanning)             echo "Scanning..." ;;
    tr::scan_complete)        echo "Tarama tamamlandı." ;;
    en::scan_complete)        echo "Scan complete." ;;
    tr::scan_results)         echo "Tarama Sonuçları" ;;
    en::scan_results)         echo "Scan Results" ;;
    tr::category)             echo "Kategori" ;;
    en::category)             echo "Category" ;;
    tr::size)                 echo "Boyut" ;;
    en::size)                 echo "Size" ;;
    tr::estimated_total)      echo "TAHMİNİ TOPLAM" ;;
    en::estimated_total)      echo "ESTIMATED TOTAL" ;;
    tr::free_disk)            echo "Mevcut boş disk alanı" ;;
    en::free_disk)            echo "Current free disk space" ;;
    tr::cleanup_report)       echo "Temizlik Raporu" ;;
    en::cleanup_report)       echo "Cleanup Report" ;;
    tr::cleanup_done)         echo "Temizlik tamamlandı!" ;;
    en::cleanup_done)         echo "Cleanup complete!" ;;
    tr::space_freed)          echo "Kazanılan Alan:" ;;
    en::space_freed)          echo "Space Freed:" ;;
    tr::items_cleaned)        echo "Temizlenen Öğe:" ;;
    en::items_cleaned)        echo "Items Cleaned:" ;;
    tr::current_free)         echo "Mevcut Boş Alan:" ;;
    en::current_free)         echo "Current Free Space:" ;;
    tr::cancelled)            echo "İptal edildi." ;;
    en::cancelled)            echo "Cancelled." ;;
    tr::continue_prompt)      echo "Devam etmek istiyor musunuz?" ;;
    en::continue_prompt)      echo "Do you want to continue?" ;;
    tr::confirm_yes_no)       echo "[e/H]" ;;
    en::confirm_yes_no)       echo "[y/N]" ;;
    tr::deleted)              echo "silindi" ;;
    en::deleted)              echo "deleted" ;;
    tr::trashed)              echo "çöpe taşındı" ;;
    en::trashed)              echo "moved to trash" ;;
    tr::would_remove)         echo "kaldırılacaktı (deneme)" ;;
    en::would_remove)         echo "would remove (dry-run)" ;;
    tr::excluded)             echo "hariç tutuldu (korumalı)" ;;
    en::excluded)             echo "excluded (protected)" ;;
    tr::delete_failed)        echo "silinemedi" ;;
    en::delete_failed)        echo "could not be deleted" ;;
    tr::empty_path)           echo "Boş path, atlanıyor" ;;
    en::empty_path)           echo "Empty path, skipping" ;;
    tr::protected_path)       echo "Korunan sistem yolu, dokunulmadı" ;;
    en::protected_path)       echo "Protected system path, not touched" ;;
    tr::skipped)              echo "atlandı" ;;
    en::skipped)              echo "skipped" ;;

    # ── Sudo ─────────────────────────────────────────────────
    tr::sudo_info)            echo "Sistem Cache ve Loglar için sudo yetkisi gerekebilir." ;;
    en::sudo_info)            echo "Sudo privileges may be required for System Cache and Logs." ;;
    tr::sudo_skip_info)       echo "Sudo olmadan bu kategoriler otomatik atlanır." ;;
    en::sudo_skip_info)       echo "These categories will be automatically skipped without sudo." ;;
    tr::sudo_prompt)          echo "Sudo yetkisi ile çalışmak ister misiniz?" ;;
    en::sudo_prompt)          echo "Would you like to run with sudo privileges?" ;;
    tr::sudo_granted)         echo "Sudo yetki alındı." ;;
    en::sudo_granted)         echo "Sudo privileges granted." ;;
    tr::sudo_failed)          echo "Sudo yetki alınamadı. Sistem kategorileri atlanacak." ;;
    en::sudo_failed)          echo "Sudo authorization failed. System categories will be skipped." ;;
    tr::sudo_declined)        echo "Sudo atlandı. Sadece kullanıcı seviyesi temizlik yapılacak." ;;
    en::sudo_declined)        echo "Sudo skipped. Only user-level cleanup will be performed." ;;
    tr::sudo_required)        echo "sudo gerekli" ;;
    en::sudo_required)        echo "sudo required" ;;
    tr::sudo_no_skip)         echo "Sudo yok, atlandı" ;;
    en::sudo_no_skip)         echo "No sudo, skipped" ;;

    # ── Category Names ───────────────────────────────────────
    tr::cat_user_cache)       echo "Kullanıcı Cache" ;;
    en::cat_user_cache)       echo "User Cache" ;;
    tr::cat_system_cache)     echo "Sistem Cache" ;;
    en::cat_system_cache)     echo "System Cache" ;;
    tr::cat_app_leftovers)    echo "Uygulama Kalıntıları" ;;
    en::cat_app_leftovers)    echo "App Leftovers" ;;
    tr::cat_logs)             echo "Loglar" ;;
    en::cat_logs)             echo "Logs" ;;
    tr::cat_temp_files)       echo "Geçici Dosyalar" ;;
    en::cat_temp_files)       echo "Temporary Files" ;;
    tr::cat_developer)        echo "Geliştirici" ;;
    en::cat_developer)        echo "Developer" ;;
    tr::cat_trash)            echo "Çöp Kutusu" ;;
    en::cat_trash)            echo "Trash" ;;
    tr::cat_browser_cache)    echo "Tarayıcı Cache" ;;
    en::cat_browser_cache)    echo "Browser Cache" ;;
    tr::cat_browser_full)     echo "Tarayıcı Tüm Veri" ;;
    en::cat_browser_full)     echo "Browser Full Data" ;;
    tr::cat_ios_backups)      echo "iOS Yedekleri" ;;
    en::cat_ios_backups)      echo "iOS Backups" ;;
    tr::cat_app_uninstaller)  echo "Tam Uygulama Kaldırıcı" ;;
    en::cat_app_uninstaller)  echo "Full App Uninstaller" ;;
    tr::cat_mail_downloads)   echo "Mail İndirilenleri" ;;
    en::cat_mail_downloads)   echo "Mail Downloads" ;;
    tr::cat_diagnostic_reports) echo "Tanılama Raporları" ;;
    en::cat_diagnostic_reports) echo "Diagnostic Reports" ;;
    tr::cat_quicklook_cache)  echo "QuickLook Cache" ;;
    en::cat_quicklook_cache)  echo "QuickLook Cache" ;;
    tr::cat_saved_app_state)  echo "Kaydedilmiş Uygulama Durumu" ;;
    en::cat_saved_app_state)  echo "Saved Application State" ;;
    tr::cat_other_trash)      echo "Diğer Ciltlerin Çöpü" ;;
    en::cat_other_trash)      echo "Other Volumes Trash" ;;
    tr::cat_project_artifacts) echo "Proje Yapıları" ;;
    en::cat_project_artifacts) echo "Project Artifacts" ;;

    # ── Cleaning Headers ─────────────────────────────────────
    tr::hdr_user_cache)       echo "🗑️  Kullanıcı Cache Temizleniyor (Tarayıcılar Hariç)" ;;
    en::hdr_user_cache)       echo "🗑️  Cleaning User Cache (Excluding Browsers)" ;;
    tr::hdr_system_cache)     echo "🗑️  Sistem Cache Temizleniyor" ;;
    en::hdr_system_cache)     echo "🗑️  Cleaning System Cache" ;;
    tr::hdr_app_leftovers)    echo "📂 Uygulama Kalıntıları Temizleniyor" ;;
    en::hdr_app_leftovers)    echo "📂 Cleaning App Leftovers" ;;
    tr::hdr_logs)             echo "🗑️  Loglar Temizleniyor" ;;
    en::hdr_logs)             echo "🗑️  Cleaning Logs" ;;
    tr::hdr_temp)             echo "🗑️  Geçici Dosyalar Temizleniyor" ;;
    en::hdr_temp)             echo "🗑️  Cleaning Temporary Files" ;;
    tr::hdr_developer)        echo "🛠  Geliştirici Verileri Temizleniyor" ;;
    en::hdr_developer)        echo "🛠  Cleaning Developer Data" ;;
    tr::hdr_trash)            echo "🗑️  Çöp Kutusu Temizleniyor" ;;
    en::hdr_trash)            echo "🗑️  Emptying Trash" ;;
    tr::hdr_browser_cache)    echo "🌐 Tarayıcı Cache Temizleniyor (Çerezler Korunur)" ;;
    en::hdr_browser_cache)    echo "🌐 Cleaning Browser Cache (Cookies Preserved)" ;;
    tr::hdr_browser_full)     echo "⚠️  Tarayıcı Tüm Veriler Temizleniyor" ;;
    en::hdr_browser_full)     echo "⚠️  Cleaning All Browser Data" ;;
    tr::hdr_ios_backups)      echo "📱 iOS Yedekleri Temizleniyor" ;;
    en::hdr_ios_backups)      echo "📱 Cleaning iOS Backups" ;;
    tr::hdr_app_uninstaller)  echo "🗑️  Uygulamalar Kaldırılıyor" ;;
    en::hdr_app_uninstaller)  echo "🗑️  Uninstalling Applications" ;;
    tr::hdr_project_artifacts) echo "🧱 Proje Yapıları Temizleniyor" ;;
    en::hdr_project_artifacts) echo "🧱 Cleaning Project Artifacts" ;;
    tr::hdr_mail_downloads)   echo "📧 Mail İndirilenler Temizleniyor" ;;
    en::hdr_mail_downloads)   echo "📧 Cleaning Mail Downloads" ;;
    tr::hdr_diagnostic)       echo "🩺 Tanılama Raporları Temizleniyor" ;;
    en::hdr_diagnostic)       echo "🩺 Cleaning Diagnostic Reports" ;;
    tr::hdr_quicklook)        echo "🖼️  QuickLook Cache Temizleniyor" ;;
    en::hdr_quicklook)        echo "🖼️  Cleaning QuickLook Cache" ;;
    tr::hdr_saved_state)      echo "💾 Kaydedilmiş Uygulama Durumu Temizleniyor" ;;
    en::hdr_saved_state)      echo "💾 Cleaning Saved Application State" ;;
    tr::hdr_other_trash)      echo "🗑️  Diğer Ciltlerin Çöpü Temizleniyor" ;;
    en::hdr_other_trash)      echo "🗑️  Cleaning Other Volumes Trash" ;;

    # ── Interactive Prompts ──────────────────────────────────
    tr::select_categories)    echo "Temizlenecek kategorileri seçin:" ;;
    en::select_categories)    echo "Select categories to clean:" ;;
    tr::enter_numbers)        echo "Numara girin (boşlukla, örn. 1 4 7 8) veya" ;;
    en::enter_numbers)        echo "Enter numbers (space-separated, e.g. 1 4 7 8) or" ;;
    tr::safe_only)            echo "sadece güvenli olanlar" ;;
    en::safe_only)            echo "safe ones only" ;;
    tr::what_to_do)           echo "Ne yapmak istersiniz?" ;;
    en::what_to_do)           echo "What would you like to do?" ;;
    tr::quick_clean)          echo "Sadece Kesinlikle Güvenli Dosyaları Hızlı Temizle (Önbellek, Log, Temp, Sepet vb.)" ;;
    en::quick_clean)          echo "Quick Clean Safe Files Only (Cache, Log, Temp, Trash etc.)" ;;
    tr::selective_clean)      echo "Kategori Seçerek Temizle (Uygulama Ayarları / Tarayıcı Oturumları Seçmeli)" ;;
    en::selective_clean)      echo "Selective Clean (Choose App Settings / Browser Sessions)" ;;
    tr::cancel)               echo "İptal" ;;
    en::cancel)               echo "Cancel" ;;
    tr::your_choice)          echo "Seçiminiz" ;;
    en::your_choice)          echo "Your choice" ;;
    tr::no_selection)         echo "Seçim yapılmadı. İptal edildi." ;;
    en::no_selection)         echo "No selection made. Cancelled." ;;
    tr::safe_clean_info)      echo "Kesinlikle güvenli kategoriler (Önbellek, Log, Temp, Çöp Kutusu, Tarayıcı Caches) temizlenecek." ;;
    en::safe_clean_info)      echo "Absolutely safe categories (Cache, Log, Temp, Trash, Browser Caches) will be cleaned." ;;
    tr::selected_clean_q)     echo "Seçilen kategoriler temizlensin mi?" ;;
    en::selected_clean_q)     echo "Clean selected categories?" ;;

    # ── Browser Full ─────────────────────────────────────────
    tr::browser_warn)         echo "DİKKAT: Tarayıcı tüm verilerini silmek ilgili tarayıcıdaki tüm oturumları kapatır ve verileri sıfırlar!" ;;
    en::browser_warn)         echo "WARNING: Deleting all browser data will close all sessions and reset data!" ;;
    tr::no_browser_data)      echo "Temizlenecek tarayıcı verisi bulunamadı." ;;
    en::no_browser_data)      echo "No browser data found to clean." ;;
    tr::browser_select)       echo "Sıfırlamak istediğiniz tarayıcı numaralarını girin (boşlukla) veya" ;;
    en::browser_select)       echo "Enter browser numbers to reset (space-separated) or" ;;
    tr::browser_skipped)      echo "Tarayıcı temizliği atlandı." ;;
    en::browser_skipped)      echo "Browser cleanup skipped." ;;
    tr::profile_deleted)      echo "Profili" ;;
    en::profile_deleted)      echo "Profile" ;;
    tr::are_you_sure)         echo "Emin misiniz?" ;;
    en::are_you_sure)         echo "Are you sure?" ;;
    tr::profile_warn)         echo "profil verileri tamamen silinecek!" ;;
    en::profile_warn)         echo "profile data will be permanently deleted!" ;;
    tr::no_browser_specified) echo "Temizlenecek tarayıcı belirtilmedi, atlanıyor." ;;
    en::no_browser_specified) echo "No browser specified, skipping." ;;

    # ── iOS Backups ──────────────────────────────────────────
    tr::no_ios_backups)       echo "iOS yedekleri bulunamadı." ;;
    en::no_ios_backups)       echo "No iOS backups found." ;;
    tr::no_ios_clean)         echo "Temizlenecek iOS yedeği bulunamadı." ;;
    en::no_ios_clean)         echo "No iOS backups found to clean." ;;
    tr::ios_skipped)          echo "iOS yedekleri atlandı." ;;
    en::ios_skipped)          echo "iOS backups skipped." ;;
    tr::ios_select)           echo "Numara girin (boşlukla)," ;;
    en::ios_select)           echo "Enter numbers (space-separated)," ;;
    tr::no_backup_specified)  echo "Temizlenecek yedek belirtilmedi, atlanıyor." ;;
    en::no_backup_specified)  echo "No backup specified, skipping." ;;

    # ── App Leftovers ────────────────────────────────────────
    tr::app_support_header)   echo "~/Library/Application Support/ klasörleri (Analiz Edildi):" ;;
    en::app_support_header)   echo "~/Library/Application Support/ folders (Analyzed):" ;;
    tr::orphan_suggested)     echo "Kalıntı - Önerilen" ;;
    en::orphan_suggested)     echo "Orphan - Recommended" ;;
    tr::installed_protected)  echo "Yüklü - Korunuyor" ;;
    en::installed_protected)  echo "Installed - Protected" ;;
    tr::leftovers_select)     echo "Numara girin (boşlukla)," ;;
    en::leftovers_select)     echo "Enter numbers (space-separated)," ;;
    tr::orphans_only)         echo "sadece kalıntılar" ;;
    en::orphans_only)         echo "orphans only" ;;
    tr::skip)                 echo "atla" ;;
    en::skip)                 echo "skip" ;;
    tr::all_warn)             echo "UYARI: 'all' seçeneği yüklü uygulamaların (örn. Chrome, VSCode) ayarlarını da silecektir!" ;;
    en::all_warn)             echo "WARNING: 'all' option will also delete settings for installed apps (e.g. Chrome, VSCode)!" ;;
    tr::all_confirm)          echo "Yüklü uygulamaların ayarlarını da silmek istediğinize emin misiniz?" ;;
    en::all_confirm)          echo "Are you sure you want to delete settings for installed apps too?" ;;
    tr::orphans_selected)     echo "Sadece kalıntılar seçildi." ;;
    en::orphans_selected)     echo "Only orphans selected." ;;
    tr::app_support_skipped)  echo "Application Support atlandı." ;;
    en::app_support_skipped)  echo "Application Support skipped." ;;
    tr::no_subdir_specified)  echo "Temizlenecek alt dizin belirtilmedi, atlanıyor." ;;
    en::no_subdir_specified)  echo "No subdirectory specified, skipping." ;;

    # ── Developer ────────────────────────────────────────────
    tr::no_dev_specified)     echo "Temizlenecek geliştirici alt kategorisi belirtilmedi, atlanıyor." ;;
    en::no_dev_specified)     echo "No developer sub-category specified, skipping." ;;
    tr::xcode_dd_prompt)      echo "Xcode DerivedData temizlensin mi?" ;;
    en::xcode_dd_prompt)      echo "Clean Xcode DerivedData?" ;;
    tr::xcode_dd_missing)     echo "Xcode DerivedData bulunamadı." ;;
    en::xcode_dd_missing)     echo "Xcode DerivedData not found." ;;
    tr::scanning_broken_links) echo "Kırık sembolik linkler taranıyor..." ;;
    en::scanning_broken_links) echo "Scanning for broken symlinks..." ;;
    tr::no_broken_links)      echo "Kırık sembolik link bulunamadı." ;;
    en::no_broken_links)      echo "No broken symlinks found." ;;
    tr::broken_links_count)   echo "Kırık sembolik linkler" ;;
    en::broken_links_count)   echo "Broken symlinks" ;;
    tr::delete_broken_q)      echo "Tüm kırık sembolik linkler silinsin mi?" ;;
    en::delete_broken_q)      echo "Delete all broken symlinks?" ;;
    tr::docker_cleaned)       echo "Docker verileri temizlendi." ;;
    en::docker_cleaned)       echo "Docker data cleaned." ;;
    tr::docker_missing)       echo "Docker bulunamadı, atlanıyor." ;;
    en::docker_missing)       echo "Docker not found, skipping." ;;
    tr::unknown_dev_key)      echo "Bilinmeyen geliştirici anahtarı, atlanıyor" ;;
    en::unknown_dev_key)      echo "Unknown developer key, skipping" ;;
    tr::simctl_deleted)       echo "Erişilmez simülatörler silindi" ;;
    en::simctl_deleted)       echo "Unavailable simulators deleted" ;;
    tr::simctl_failed)        echo "simctl çalıştırılamadı" ;;
    en::simctl_failed)        echo "simctl could not be executed" ;;
    tr::simctl_erased)        echo "Simülatörler fabrika ayarlarına sıfırlandı" ;;
    en::simctl_erased)        echo "Simulators reset to factory state" ;;
    tr::brew_cleanup_success)  echo "Homebrew temizliği (brew cleanup -s) tamamlandı" ;;
    en::brew_cleanup_success)  echo "Homebrew cleanup (brew cleanup -s) completed" ;;
    tr::brew_cleanup_failed)   echo "Homebrew temizliği başarısız oldu" ;;
    en::brew_cleanup_failed)   echo "Homebrew cleanup failed" ;;

    # ── App Uninstaller ──────────────────────────────────────
    tr::no_app_specified)     echo "Kaldırılacak uygulama belirtilmedi, atlanıyor." ;;
    en::no_app_specified)     echo "No application specified, skipping." ;;
    tr::no_artifact_specified) echo "Temizlenecek proje yapısı belirtilmedi, atlanıyor." ;;
    en::no_artifact_specified) echo "No project artifact specified, skipping." ;;
    tr::invalid_artifact)     echo "Geçersiz proje yapısı yolu, atlanıyor" ;;
    en::invalid_artifact)     echo "Invalid project artifact path, skipping" ;;
    tr::uninstaller_cli_only) echo "Tam Uygulama Kaldırıcı yalnızca web arayüzü üzerinden kullanılabilir." ;;
    en::uninstaller_cli_only) echo "Full App Uninstaller is only available via the web interface." ;;
    tr::invalid_path_traversal) echo "Geçersiz (path traversal girişimi)" ;;
    en::invalid_path_traversal) echo "Invalid (path traversal attempt)" ;;

    # ── Mail Downloads ───────────────────────────────────────
    tr::mail_dir_missing)     echo "Mail İndirilenler klasörü bulunamadı." ;;
    en::mail_dir_missing)     echo "Mail Downloads folder not found." ;;

    # ── QuickLook ────────────────────────────────────────────
    tr::ql_reset)             echo "QuickLook thumbnail cache sıfırlandı" ;;
    en::ql_reset)             echo "QuickLook thumbnail cache reset" ;;
    tr::ql_failed)            echo "qlmanage çalıştırılamadı" ;;
    en::ql_failed)            echo "qlmanage could not be executed" ;;
    tr::ql_missing)           echo "qlmanage bulunamadı" ;;
    en::ql_missing)           echo "qlmanage not found" ;;

    # ── Misc ─────────────────────────────────────────────────
    tr::dns_flushed)          echo "DNS önbelleği temizlendi." ;;
    en::dns_flushed)          echo "DNS cache flushed." ;;
    tr::dns_failed)           echo "DNS temizleme başarısız." ;;
    en::dns_failed)           echo "DNS flush failed." ;;
    tr::ram_purged)           echo "RAM önbelleği temizlendi." ;;
    en::ram_purged)           echo "RAM cache purged." ;;
    tr::ram_failed)           echo "RAM temizleme başarısız (sudo gerekebilir)." ;;
    en::ram_failed)           echo "RAM purge failed (sudo may be required)." ;;
    tr::scan_first)           echo "Bu betik ÖNCE tarar, silmeden önce onayınızı ister." ;;
    en::scan_first)           echo "This script scans FIRST, then asks for confirmation before deleting." ;;
    tr::critical_protected)   echo "Kritik sistem dosyaları ve aktif uygulama oturumları korunur." ;;
    en::critical_protected)   echo "Critical system files and active app sessions are protected." ;;
    tr::broken_category_row)  echo "HATA: bozuk CATEGORIES satırı" ;;
    en::broken_category_row)  echo "ERROR: broken CATEGORIES row" ;;
    tr::spotlight_rebuild)    echo "Spotlight indexing rebuilt successfully." ;;
    en::spotlight_rebuild)    echo "Spotlight indexing rebuilt successfully." ;;
    tr::no_history)           echo "Henüz temizlik geçmişi yok." ;;
    en::no_history)           echo "No cleanup history yet." ;;

    # ── Fallback ─────────────────────────────────────────────
    *) echo "$key" ;;
  esac
}

# Resolved category name via localization
cat_display_name() {
  local id="$1"
  L "cat_${id}"
}

# ─── Colors (disabled if not a terminal) ─────────────────────────────────────
if [ -t 1 ]; then
  RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
  CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'
  DIM='\033[2m';     NC='\033[0m'
else
  RED=''; YELLOW=''; GREEN=''; CYAN=''; BLUE=''; BOLD=''; DIM=''; NC=''
fi

VERSION="2.0.0"
SUDO_AVAILABLE=false
TOTAL_FREED=0
TOTAL_ITEMS=0
JSON_MODE=false
CLEAN_RESULTS=()

# When set to 1, bypass trash-first and use rm -rf directly (for CI/testing)
FORCE_RM="${APPLE_CLEANUP_FORCE_RM:-0}"

# When set to 1, preview only: report what WOULD be removed without deleting.
DRYRUN="${APPLE_CLEANUP_DRYRUN:-0}"

# User exclusion list: colon-separated paths/globs that must never be deleted.
# A pattern protects the path itself and everything beneath it.
EXCLUDE_RAW="${APPLE_CLEANUP_EXCLUDE:-}"

_is_excluded() {
  local path="$1"
  [ -n "$EXCLUDE_RAW" ] || return 1
  local oldIFS="$IFS"; IFS=':'
  local pat
  for pat in $EXCLUDE_RAW; do
    [ -n "$pat" ] || continue
    # Unquoted $pat in case enables glob matching; $pat/* covers descendants.
    case "$path" in
      $pat|$pat/*) IFS="$oldIFS"; return 0 ;;
    esac
  done
  IFS="$oldIFS"
  return 1
}

# JSON mode sub-item lists (comma-separated, parsed via IFS read -ra)
APP_LEFTOVERS_CLEAN=""
BROWSER_FULL_CLEAN=""
DEVELOPER_CLEAN=""
IOS_BACKUPS_CLEAN=""
APP_UNINSTALLER_CLEAN=""
PROJECT_ARTIFACT_CLEAN=""

MAIL_DOWNLOADS_DIR="$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"

# ─── Project artifact scanner config ─────────────────────────────────────────
# Build/dependency directories that are safe to remove (they regenerate from a
# project manifest). Each is identified by a marker file living alongside it.
# Marker → artifact mapping is enforced by _is_valid_project_artifact() so the
# web API can only ever delete a genuine artifact dir next to its project file.
_PROJECT_ARTIFACT_NAMES="node_modules|target|.build|build|vendor|.dart_tool|.terraform"
_PROJECT_MARKERS="package.json|Cargo.toml|Package.swift|go.mod|build.gradle|build.gradle.kts|pom.xml|composer.json|pubspec.yaml|CMakeLists.txt|main.tf"
# Roots to scan for projects (under $HOME). Tilde-relative, expanded at runtime.
_PROJECT_SCAN_ROOTS=("Documents" "Developer" "Projects" "Code" "repos" "src" "workspace" "Desktop")
_PROJECT_ARTIFACT_MIN_BYTES=10485760  # only surface artifacts > 10 MB

# ─── Developer sub-item whitelist (for case-validation) ──────────────────────
# Must be kept 100% in sync with server.py _DEVELOPER_WHITELIST
_VALID_DEVELOPER_KEYS="derived_data|broken_links|brew_cache|docker_prune|npm_cache|pip_cache|device_support|coresim_caches|xcode_archives|cocoapods_cache|pnpm_cache|yarn_cache|gradle_cache|maven_repo|simctl_unavailable|xcode_products|simulator_logs|simulator_devices|font_caches|brew_cleanup|swift_pm_cache|xcode_logs|xcode_previews|carthage_cache|bun_cache|deno_cache|conda_pkgs|uv_cache|poetry_cache|go_modules|cargo_registry|composer_cache|gradle_wrapper|sbt_ivy_cache|bazel_cache|flutter_pub_cache|jetbrains_cache|playwright_cache|puppeteer_cache|prisma_cache|huggingface_cache"

# ─── Browser key whitelist ───────────────────────────────────────────────────
# Must be kept 100% in sync with server.py _BROWSER_WHITELIST
_VALID_BROWSER_KEYS="safari|cookies|chrome|firefox|brave|edge|opera|arc"

# Browser cache dirs (top-level folder names under ~/Library/Caches)
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

# Browser profile dirs (cookies, history, etc.)
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

# ─── Category Registry (Bash 3.2 compatible: single array, pipe-separated) ──
# Format: id|name_key|scan_fn|clean_fn|needs_sudo|risk|in_total
#   name_key: localization key (resolved via cat_display_name)
#   risk:     safe | caution | danger
#   in_total: 1 → included in headline TOTAL, 0 → excluded (overlapping/interactive)
CATEGORIES=(
  "user_cache|cat_user_cache|scan_user_cache|clean_user_cache|0|safe|1"
  "system_cache|cat_system_cache|scan_system_cache|clean_system_cache|1|safe|1"
  "app_leftovers|cat_app_leftovers|scan_app_leftovers|clean_app_leftovers|0|caution|1"
  "logs|cat_logs|scan_logs|clean_logs|0|safe|1"
  "temp_files|cat_temp_files|scan_temp_files|clean_temp_files|0|safe|1"
  "developer|cat_developer|scan_developer|clean_developer|0|caution|1"
  "trash|cat_trash|scan_trash|clean_trash|0|safe|1"
  "browser_cache|cat_browser_cache|scan_browser_cache|clean_browser_cache|0|safe|1"
  "browser_full|cat_browser_full|scan_browser_full|clean_browser_full|0|danger|1"
  "ios_backups|cat_ios_backups|scan_ios_backups|clean_ios_backups|0|caution|1"
  "app_uninstaller|cat_app_uninstaller|scan_app_uninstaller|clean_app_uninstaller|0|caution|0"
  "mail_downloads|cat_mail_downloads|scan_mail_downloads|clean_mail_downloads|0|safe|1"
  "diagnostic_reports|cat_diagnostic_reports|scan_diagnostic_reports|clean_diagnostic_reports|0|safe|0"
  "quicklook_cache|cat_quicklook_cache|scan_quicklook_cache|clean_quicklook_cache|0|safe|1"
  "saved_app_state|cat_saved_app_state|scan_saved_app_state|clean_saved_app_state|0|caution|1"
  "other_trash|cat_other_trash|scan_other_trash|clean_other_trash|0|safe|1"
  "project_artifacts|cat_project_artifacts|scan_project_artifacts|clean_project_artifacts|0|caution|0"
)

# Derive parallel arrays from registry (preserves index-based access)
CAT_IDS=(); CAT_NAME_KEYS=(); CAT_NEEDS_SUDO=(); CAT_RISKS=(); CAT_IN_TOTAL=(); CAT_SIZES=()
init_categories() {
  CAT_IDS=(); CAT_NAME_KEYS=(); CAT_NEEDS_SUDO=(); CAT_RISKS=(); CAT_IN_TOTAL=(); CAT_SIZES=()
  local row id name_key scan clean sudo risk in_total
  for row in "${CATEGORIES[@]}"; do
    IFS='|' read -r id name_key scan clean sudo risk in_total <<< "$row"
    if [ -z "$in_total" ]; then
      echo "$(L broken_category_row): $row" >&2
      exit 1
    fi
    CAT_IDS+=("$id"); CAT_NAME_KEYS+=("$name_key"); CAT_NEEDS_SUDO+=("$sudo")
    CAT_RISKS+=("$risk"); CAT_IN_TOTAL+=("$in_total"); CAT_SIZES+=(0)
  done
}
init_categories

# Read field from registry row: cat_field <index> <field>
# field: id|name_key|scan_fn|clean_fn|needs_sudo|risk|in_total
cat_field() {
  local idx="$1" field="$2"
  local id name_key scan clean sudo risk in_total
  IFS='|' read -r id name_key scan clean sudo risk in_total <<< "${CATEGORIES[$idx]}"
  case "$field" in
    id) echo "$id" ;; name_key) echo "$name_key" ;; scan_fn) echo "$scan" ;;
    clean_fn) echo "$clean" ;; needs_sudo) echo "$sudo" ;;
    risk) echo "$risk" ;; in_total) echo "$in_total" ;;
  esac
}

# Resolve display name for index
cat_name() {
  local idx="$1"
  cat_display_name "${CAT_IDS[$idx]}"
}

# id → index (returns -1 if not found)
cat_index_by_id() {
  local want="$1" i
  for i in "${!CAT_IDS[@]}"; do
    [ "${CAT_IDS[$i]}" = "$want" ] && { echo "$i"; return; }
  done
  echo "-1"
}

# ─── UI ──────────────────────────────────────────────────────────────────────
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

# ─── Size Helpers ────────────────────────────────────────────────────────────
format_bytes() {
  local b=$1
  if   [ "$b" -ge 1073741824 ]; then printf "%.1f GB" "$(echo "scale=1; $b/1073741824" | bc)"
  elif [ "$b" -ge 1048576 ];    then printf "%.1f MB" "$(echo "scale=1; $b/1048576"    | bc)"
  elif [ "$b" -ge 1024 ];       then printf "%.1f KB" "$(echo "scale=1; $b/1024"       | bc)"
  else printf "%d B" "$b"; fi
}

json_escape_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  echo "$s"
}

# ─── Operation Log ───────────────────────────────────────────────────────────
# Append-only audit trail of real deletions. Paired with trash-first deletion so
# users can see what was removed and whether it is recoverable from Trash.
OPLOG_FILE="$HOME/.cache/apple-cleanup/operations.log"
OPLOG_MAX_BYTES="${APPLE_CLEANUP_OPLOG_MAX_BYTES:-5242880}"

# Unique per script invocation; tags every oplog record from this run.
SESSION_ID="$(uuidgen 2>/dev/null || echo "$$-$(date +%s)")"

# oplog_record <action> <bytes> <source> <trash_dest> <category>
# action: trash (recoverable) | delete (permanent) | restore (audit).
oplog_record() {
  [ "${APPLE_CLEANUP_NO_OPLOG:-0}" = "1" ] && return 0
  [ "${DRYRUN:-0}" = "1" ] && return 0
  local action="$1" bytes="$2" path="$3" trash_dest="${4:-}" category="${5:-}"
  path="${path//$'\t'/ }"; path="${path//$'\n'/ }"
  trash_dest="${trash_dest//$'\t'/ }"; trash_dest="${trash_dest//$'\n'/ }"
  local dir; dir="$(dirname "$OPLOG_FILE")"
  mkdir -p "$dir" 2>/dev/null || return 0
  if [ -f "$OPLOG_FILE" ]; then
    local sz; sz=$(wc -c <"$OPLOG_FILE" 2>/dev/null | tr -d ' ')
    if [ -n "$sz" ] && [ "$sz" -gt "$OPLOG_MAX_BYTES" ] 2>/dev/null; then
      local lines half
      lines=$(wc -l <"$OPLOG_FILE" 2>/dev/null | tr -d ' ')
      half=$(( lines / 2 )); [ "$half" -lt 1 ] && half=1
      tail -n "$half" "$OPLOG_FILE" >"$OPLOG_FILE.tmp" 2>/dev/null \
        && mv "$OPLOG_FILE.tmp" "$OPLOG_FILE" 2>/dev/null
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date +%s)" "$SESSION_ID" "$action" "$bytes" "$path" "$trash_dest" "$category" \
    >>"$OPLOG_FILE" 2>/dev/null || true
  return 0
}

# Days since a path was last modified (0 if unknown / inaccessible).
dir_age_days() {
  local p="$1" mt now
  [ -e "$p" ] || { echo 0; return; }
  mt=$(stat -f %m "$p" 2>/dev/null) || { echo 0; return; }
  [ -n "$mt" ] || { echo 0; return; }
  now=$(date +%s)
  echo $(( (now - mt) / 86400 ))
}

get_dir_size_bytes() {
  local path="$1"
  [ -d "$path" ] || { echo "0"; return; }
  local total
  total=$(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null \
            | xargs -0 du -sk 2>/dev/null \
            | awk '{sum += $1} END {print sum * 1024}')
  [ -z "$total" ] && total=0
  echo "$total"
}

get_size_bytes() {
  local path="$1"
  [ -e "$path" ] || { echo "0"; return; }
  local result
  result=$(du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}')
  [ -z "$result" ] && result="0"
  echo "$result"
}

get_free_disk() {
  df -h / 2>/dev/null | awk 'NR==2 {print $4}' || echo "?"
}

# ─── Interaction ─────────────────────────────────────────────────────────────
confirm() {
  local prompt="${1:-$(L continue_prompt)}"
  local answer
  echo -ne "  ${YELLOW}?${NC}  $prompt $(L confirm_yes_no): "
  read -r answer
  [[ "$answer" =~ ^[eEyY]$ ]]
}

# ─── Trash-First Safe Deletion Infrastructure ────────────────────────────────
# Moves a file/directory to macOS Trash via AppleScript; falls back to mv ~/.Trash
# Returns 0 on success, 1 on failure
_trash_item() {
  local path="$1"
  [ -e "$path" ] || return 0
  local base; base=$(basename "$path")
  # Tier 1: AppleScript (native Finder trash). Finder's trash is tied to the
  # logged-in GUI session's real home directory, not an overridden $HOME, so
  # only attempt it when $HOME matches the real account home (i.e. not under
  # test isolation) -- otherwise go straight to the deterministic Tier 2 mv.
  local _real_home; _real_home=$(eval echo "~$(id -un)" 2>/dev/null)
  if [ -n "$_real_home" ] && [ "$_real_home" = "$HOME" ] \
     && osascript -e 'tell application "Finder" to move POSIX file "'"$path"'" to trash' >/dev/null 2>&1; then
    # Item lands at ~/.Trash/<base>; if renamed on collision, take newest match.
    local dest="$HOME/.Trash/$base"
    if [ ! -e "$dest" ]; then
      dest=$(ls -dt "$HOME/.Trash/$base"* 2>/dev/null | head -n1) || dest=""
    fi
    echo "$dest"
    return 0
  fi
  # Tier 2: manual mv with collision-safe naming
  local dest="$HOME/.Trash/$base"
  [ -e "$dest" ] && dest="$HOME/.Trash/${base}.$(date +%s)"
  if mv "$path" "$dest" 2>/dev/null; then
    echo "$dest"
    return 0
  fi
  return 1
}

# Determine if we should use rm -rf or trash-first for a given context
# Arguments: needs_sudo_flag (0 or 1), is_trash_empty (0 or 1)
_should_force_rm() {
  local needs_sudo="${1:-0}"
  local is_trash_empty="${2:-0}"
  # Force RM conditions:
  #   1. CI/test bypass env var
  #   2. Category requires sudo (system paths)
  #   3. We are emptying the trash itself
  [ "$FORCE_RM" = "1" ] && return 0
  [ "$needs_sudo" -eq 1 ] && return 0
  [ "$is_trash_empty" -eq 1 ] && return 0
  return 1
}

# Context variable: set by clean functions to indicate sudo context
_CURRENT_NEEDS_SUDO=0
_CURRENT_IS_TRASH_EMPTY=0
# Category key for the item currently being cleaned (set by run_clean); used to
# tag operation-log records. Empty when cleanup runs outside a category loop.
_CURRENT_CATEGORY=""

safe_rm() {
  local path="$1"
  local label="${2:-$1}"
  [ -z "$path" ] && { err "$(L empty_path): $label"; return 1; }
  case "$path" in
    /System/*|/usr/*|/bin/*|/sbin/*|/etc/*|/private/etc/*)
      err "$(L protected_path): $path"; return 1 ;;
  esac
  if _is_excluded "$path"; then
    info "$(L excluded): $label"
    return 0
  fi
  [ -e "$path" ] || return 0
  local sz_b; sz_b=$(get_size_bytes "$path")
  local sz_h; sz_h=$(format_bytes "$sz_b")

  if [ "$DRYRUN" = "1" ]; then
    success "$label: ${BOLD}${sz_h}${NC} $(L would_remove)"
    TOTAL_FREED=$((TOTAL_FREED + sz_b))
    TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
    return 0
  fi

  if _should_force_rm "$_CURRENT_NEEDS_SUDO" "$_CURRENT_IS_TRASH_EMPTY"; then
    # Direct rm -rf (sudo paths, trash emptying, or CI mode)
    if $SUDO_AVAILABLE && [ "$_CURRENT_NEEDS_SUDO" -eq 1 ]; then
      sudo rm -rf "$path" 2>/dev/null && {
        success "$label: ${BOLD}${sz_h}${NC} $(L deleted)"
        TOTAL_FREED=$((TOTAL_FREED + sz_b))
        TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
        oplog_record "delete" "$sz_b" "$path" "" "$_CURRENT_CATEGORY"
      } || err "$label $(L delete_failed)"
    else
      rm -rf "$path" 2>/dev/null && {
        success "$label: ${BOLD}${sz_h}${NC} $(L deleted)"
        TOTAL_FREED=$((TOTAL_FREED + sz_b))
        TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
        oplog_record "delete" "$sz_b" "$path" "" "$_CURRENT_CATEGORY"
      } || err "$label $(L delete_failed)"
    fi
  else
    # Trash-first (user files, non-sudo)
    local _td; _td="$(_trash_item "$path")"
    if [ -n "$_td" ] || [ ! -e "$path" ]; then
      success "$label: ${BOLD}${sz_h}${NC} $(L trashed)"
      TOTAL_FREED=$((TOTAL_FREED + sz_b))
      TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
      oplog_record "trash" "$sz_b" "$path" "$_td" "$_CURRENT_CATEGORY"
    else
      err "$label $(L delete_failed)"
    fi
  fi
}

safe_rm_contents() {
  local path="$1"
  local label="${2:-$1}"
  [ -d "$path" ] || return 0
  [ -z "$path" ] && return 1
  case "$path" in
    /System/*|/usr/*|/bin/*|/sbin/*|/etc/*|/private/etc/*) err "$(L protected_path): $path"; return 1 ;;
  esac
  # Exclusion-aware mode: when the user defined protected paths, delete each
  # child individually (via safe_rm, which honors excludes + dry-run) so a
  # protected item inside the directory is never swept away by a bulk rm.
  if [ -n "$EXCLUDE_RAW" ]; then
    local child
    while IFS= read -r -d '' child; do
      safe_rm "$child" "$child"
    done < <(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
    return 0
  fi
  local sz_b; sz_b=$(get_dir_size_bytes "$path")
  [ "$sz_b" -le 0 ] 2>/dev/null && return 0
  local sz_h; sz_h=$(format_bytes "$sz_b")

  if [ "$DRYRUN" = "1" ]; then
    success "$label: ${BOLD}${sz_h}${NC} $(L would_remove)"
    TOTAL_FREED=$((TOTAL_FREED + sz_b))
    TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
    return 0
  fi

  if _should_force_rm "$_CURRENT_NEEDS_SUDO" "$_CURRENT_IS_TRASH_EMPTY"; then
    # Direct rm -rf (sudo paths, trash emptying, or CI mode)
    if $SUDO_AVAILABLE && [ "$_CURRENT_NEEDS_SUDO" -eq 1 ]; then
      sudo find "$path" -maxdepth 1 -mindepth 1 -exec rm -rf {} + 2>/dev/null && {
        success "$label: ${BOLD}${sz_h}${NC} $(L deleted)"
        TOTAL_FREED=$((TOTAL_FREED + sz_b))
        TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
        oplog_record "delete" "$sz_b" "$path" "" "$_CURRENT_CATEGORY"
      } || err "$label $(L delete_failed)"
    else
      find "$path" -maxdepth 1 -mindepth 1 -exec rm -rf {} + 2>/dev/null && {
        success "$label: ${BOLD}${sz_h}${NC} $(L deleted)"
        TOTAL_FREED=$((TOTAL_FREED + sz_b))
        TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
        oplog_record "delete" "$sz_b" "$path" "" "$_CURRENT_CATEGORY"
      } || err "$label $(L delete_failed)"
    fi
  else
    # Trash-first: move each child item to trash individually
    local trashed_any=false
    local child
    while IFS= read -r -d '' child; do
      _trash_item "$child" >/dev/null && trashed_any=true
    done < <(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
    if $trashed_any; then
      success "$label: ${BOLD}${sz_h}${NC} $(L trashed)"
      TOTAL_FREED=$((TOTAL_FREED + sz_b))
      TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
      oplog_record "trash" "$sz_b" "$path" "" "$_CURRENT_CATEGORY"
    fi
  fi
}

# ─── Sudo Check ─────────────────────────────────────────────────────────────
sudo_check() {
  echo ""
  info "$(L sudo_info)"
  info "$(L sudo_skip_info)"
  echo ""
  if confirm "$(L sudo_prompt)"; then
    if sudo -v 2>/dev/null; then
      SUDO_AVAILABLE=true
      success "$(L sudo_granted)"
    else
      warn "$(L sudo_failed)"
    fi
  else
    info "$(L sudo_declined)"
  fi
}

# ─── Browser Dir Check ──────────────────────────────────────────────────────
is_browser_cache_dir() {
  local name; name=$(basename "$1")
  local d
  for d in "${BROWSER_CACHE_TOPDIRS[@]}"; do
    [[ "$name" == "$d" ]] && return 0
  done
  return 1
}

# ─── App Installation Heuristic ──────────────────────────────────────────────
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
  # Critical system and protected folders are always considered installed
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

# ─── Scan Functions ──────────────────────────────────────────────────────────
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

scan_quicklook_cache() {
  local i; i=$(cat_index_by_id quicklook_cache)
  local qldir
  qldir="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null)com.apple.quicklook.ThumbnailsAgent/com.apple.QuickLook.thumbnailcache"
  CAT_SIZES[$i]=$(get_dir_size_bytes "$qldir")
}

scan_saved_app_state() {
  local i; i=$(cat_index_by_id saved_app_state)
  CAT_SIZES[$i]=$(get_dir_size_bytes "$HOME/Library/Saved Application State")
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

scan_all() {
  header "🔍 $(L scanning)"
  local fns=()
  local _i
  for _i in "${!CAT_IDS[@]}"; do fns+=("$(cat_field "$_i" scan_fn)"); done
  local i
  for i in "${!fns[@]}"; do
    echo -ne "  ${DIM}$(cat_name "$i")...${NC}\r"
    "${fns[$i]}"
  done
  echo -e "  ${GREEN}$(L scan_complete)${NC}                              "
}

# ─── Scan Table ──────────────────────────────────────────────────────────────
print_scan_table() {
  header "📊 $(L scan_results)"
  echo ""
  printf "  ${BOLD}%-3s  %-26s  %-12s  %s${NC}\n" "#" "$(L category)" "$(L size)" ""
  separator
  local total_bytes=0
  local i
  for i in "${!CAT_IDS[@]}"; do
    local sz_h; sz_h=$(format_bytes "${CAT_SIZES[$i]}")
    local display_name; display_name=$(cat_name "$i")
    local sudo_tag=""
    [ "${CAT_NEEDS_SUDO[$i]}" -eq 1 ] && sudo_tag="${DIM}[sudo]${NC}"
    if [ "${CAT_SIZES[$i]}" -gt 0 ]; then
      printf "  ${GREEN}%-3s${NC}  %-26s  ${BOLD}%-12s${NC}  %b\n" \
        "$((i+1))" "$display_name" "$sz_h" "$sudo_tag"
    else
      printf "  ${DIM}%-3s  %-26s  %-12s  %b${NC}\n" \
        "$((i+1))" "$display_name" "—" "$sudo_tag"
    fi
    [ "${CAT_IN_TOTAL[$i]}" -eq 1 ] && total_bytes=$((total_bytes + CAT_SIZES[$i]))
  done
  separator
  local total_h; total_h=$(format_bytes "$total_bytes")
  printf "  ${BOLD}%-3s  %-26s  %-12s${NC}\n" "" "$(L estimated_total)" "$total_h"
  echo ""
  info "$(L free_disk): ${BOLD}$(get_free_disk)${NC}"
  echo ""
}

# ─── Clean Functions ─────────────────────────────────────────────────────────

clean_user_cache() {
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=0
  header "$(L hdr_user_cache)"
  local item
  while IFS= read -r -d '' item; do
    is_browser_cache_dir "$item" && continue
    safe_rm_contents "$item" "$(basename "$item")"
  done < <(find "$HOME/Library/Caches" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
}

clean_system_cache() {
  _CURRENT_NEEDS_SUDO=1; _CURRENT_IS_TRASH_EMPTY=0
  if ! $SUDO_AVAILABLE; then warn "$(L sudo_no_skip): $(L cat_system_cache)"; return; fi
  header "$(L hdr_system_cache)"
  local item
  while IFS= read -r -d '' item; do
    local sz_b; sz_b=$(sudo du -sk "$item" 2>/dev/null | awk '{print $1*1024}') || continue
    [ "$sz_b" -le 0 ] 2>/dev/null && continue
    local sz_h; sz_h=$(format_bytes "$sz_b")
    sudo rm -rf "$item" 2>/dev/null && {
      success "$(basename "$item"): ${BOLD}${sz_h}${NC} $(L deleted)"
      TOTAL_FREED=$((TOTAL_FREED + sz_b))
      TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
    } || err "$(basename "$item") $(L delete_failed)"
  done < <(sudo find /Library/Caches -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
}

clean_logs() {
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=0
  header "$(L hdr_logs)"
  safe_rm_contents "$HOME/Library/Logs" "~/Library/Logs"
  if $SUDO_AVAILABLE; then
    _CURRENT_NEEDS_SUDO=1
    local item
    while IFS= read -r -d '' item; do
      local sz_b; sz_b=$(sudo du -sk "$item" 2>/dev/null | awk '{print $1*1024}') || continue
      [ "$sz_b" -le 0 ] 2>/dev/null && continue
      local sz_h; sz_h=$(format_bytes "$sz_b")
      sudo rm -rf "$item" 2>/dev/null && {
        success "$(basename "$item"): ${BOLD}${sz_h}${NC} $(L deleted)"
        TOTAL_FREED=$((TOTAL_FREED + sz_b))
        TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
      } || err "$(basename "$item") $(L delete_failed)"
    done < <(sudo find /Library/Logs -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
    _CURRENT_NEEDS_SUDO=0
  fi
}

clean_temp_files() {
  # Temp files are OS-managed ephemeral data — use rm -rf directly (not trash)
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=1
  header "$(L hdr_temp)"
  local tmpdir; tmpdir=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || echo "${TMPDIR:-/tmp}")
  local cachedir; cachedir=$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || echo "")
  safe_rm_contents "$tmpdir" "User Temp"
  if [ -n "$cachedir" ] && [ -d "$cachedir" ]; then
    safe_rm_contents "$cachedir" "User Var Cache"
  fi
  _CURRENT_IS_TRASH_EMPTY=0
}

clean_trash() {
  # Emptying trash IS permanent deletion — use rm -rf
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=1
  header "$(L hdr_trash)"
  safe_rm_contents "$HOME/.Trash" "~/.Trash"
  _CURRENT_IS_TRASH_EMPTY=0
}

clean_browser_cache() {
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=0
  header "$(L hdr_browser_cache)"
  local d
  for d in "${BROWSER_CACHE_TOPDIRS[@]}"; do
    local path="$HOME/Library/Caches/$d"
    [ -e "$path" ] || continue
    safe_rm_contents "$path" "$d"
  done
}

clean_browser_full() {
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=0
  header "$(L hdr_browser_full)"

  local browser_keys=("safari" "cookies" "chrome" "firefox" "brave" "edge" "opera" "arc")
  local browser_names=("Safari" "System Cookies" "Google Chrome" "Firefox" "Brave" "Microsoft Edge" "Opera" "Arc")
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
      info "$(L no_browser_specified)"
      return
    fi

    # ── Robust comma parsing ──
    local parsed_browsers=()
    IFS=',' read -ra parsed_browsers <<< "$BROWSER_FULL_CLEAN"

    local key
    for key in "${parsed_browsers[@]}"; do
      # Trim whitespace
      key="${key## }"; key="${key%% }"
      [ -z "$key" ] && continue

      # Case-validate against whitelist
      case "$key" in
        safari|cookies|chrome|firefox|brave|edge|opera|arc) ;;
        *)
          err "$(L unknown_dev_key): $key" >&2
          continue
          ;;
      esac

      local i
      for i in "${!browser_keys[@]}"; do
        if [ "${browser_keys[$i]}" = "$key" ]; then
          local path="${browser_paths[$i]}"
          if [ -e "$path" ]; then
            safe_rm_contents "$path" "${browser_names[$i]} $(L profile_deleted)"
          fi
        fi
      done
    done
    return
  fi

  # Interactive CLI Mode
  echo ""
  warn "$(L browser_warn)"
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
    info "$(L no_browser_data)"
    return
  fi

  echo ""
  echo -ne "  $(L browser_select) ${BOLD}none${NC}: "
  local selection; read -r selection
  
  if [ "$selection" = "none" ] || [ -z "$selection" ]; then
    info "$(L browser_skipped)"
    return
  fi

  read -ra indices <<< "$selection"
  for num in ${indices[@]+"${indices[@]}"}; do
    local real_idx=$((num - 1))
    if [ "$real_idx" -ge 0 ] && [ "$real_idx" -lt "${#avail_keys[@]}" ]; then
      warn "'${avail_names[$real_idx]}' $(L profile_warn)"
      if confirm "$(L are_you_sure)"; then
        safe_rm_contents "${avail_paths[$real_idx]}" "${avail_names[$real_idx]} $(L profile_deleted)"
      fi
    fi
  done
}

clean_ios_backups() {
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=0
  header "$(L hdr_ios_backups)"
  local backup_dir="$HOME/Library/MobileSync/Backup"

  if $JSON_MODE; then
    if [ -z "$IOS_BACKUPS_CLEAN" ]; then
      info "$(L no_backup_specified)"
      return
    fi

    # ── Robust comma parsing ──
    local parsed_uuids=()
    IFS=',' read -ra parsed_uuids <<< "$IOS_BACKUPS_CLEAN"

    local uuid
    for uuid in "${parsed_uuids[@]}"; do
      uuid="${uuid## }"; uuid="${uuid%% }"
      [ -z "$uuid" ] && continue
      case "$uuid" in
        */*|*..*)
          err "$(L invalid_path_traversal): $uuid"
          continue
          ;;
      esac
      local full_path="$backup_dir/$uuid"
      if [ -d "$full_path" ]; then
        safe_rm "$full_path" "iOS Backup: $uuid"
      fi
    done
    return
  fi

  # Interactive CLI Mode
  if [ ! -d "$backup_dir" ]; then
    info "$(L no_ios_backups)"
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
    mod_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$item" 2>/dev/null || echo "Unknown")
    printf "  ${GREEN}%-3d${NC}  %-40s  %-8s  %s\n" "$idx" "$base" "$sz_h" "$mod_date"
    backup_paths+=("$item")
    backup_names+=("$base")
    idx=$((idx + 1))
  done < <(find "$backup_dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)

  if [ "${#backup_paths[@]}" -eq 0 ]; then
    info "$(L no_ios_clean)"
    return
  fi

  echo ""
  echo -ne "  $(L ios_select) ${BOLD}all${NC} / ${BOLD}none${NC}: "
  local selection; read -r selection

  if [ "$selection" = "none" ] || [ -z "$selection" ]; then
    info "$(L ios_skipped)"
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
      safe_rm "${backup_paths[$real_idx]}" "iOS Backup: ${backup_names[$real_idx]}"
    fi
  done
}

clean_app_uninstaller() {
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=0
  header "$(L hdr_app_uninstaller)"
  if $JSON_MODE; then
    if [ -z "$APP_UNINSTALLER_CLEAN" ]; then
      info "$(L no_app_specified)"
      return
    fi

    # ── Robust comma parsing ──
    local parsed_apps=()
    IFS=',' read -ra parsed_apps <<< "$APP_UNINSTALLER_CLEAN"

    local app_name
    for app_name in "${parsed_apps[@]}"; do
      app_name="${app_name## }"; app_name="${app_name%% }"
      [ -z "$app_name" ] && continue
      case "$app_name" in
        */*|*..*)
          err "$(L invalid_path_traversal): $app_name"
          continue
          ;;
      esac
      local app_path=""
      if [ -d "/Applications/$app_name.app" ]; then
        app_path="/Applications/$app_name.app"
      elif [ -d "$HOME/Applications/$app_name.app" ]; then
        app_path="$HOME/Applications/$app_name.app"
      fi
      # Resolve the real bundle id from Info.plist BEFORE deleting the .app,
      # so leftovers keyed by bundle id can still be located afterwards.
      local bundle_id=""
      if [ -n "$app_path" ] && [ -d "$app_path" ]; then
        bundle_id=$(get_app_bundle_id "$app_path")
        safe_rm "$app_path" "App: $app_name"
      fi
      local dir
      while IFS= read -r -d '' dir; do
        if [ -e "$dir" ]; then
          safe_rm "$dir" "Leftover: $dir"
        fi
      done < <(app_leftover_paths "$app_name" "$bundle_id")
    done
    return
  fi
  info "$(L uninstaller_cli_only)"
}

clean_mail_downloads() {
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=0
  header "$(L hdr_mail_downloads)"
  if [ -d "$MAIL_DOWNLOADS_DIR" ]; then
    safe_rm_contents "$MAIL_DOWNLOADS_DIR" "Mail Downloads"
  else
    info "$(L mail_dir_missing)"
  fi
}

clean_diagnostic_reports() {
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=0
  header "$(L hdr_diagnostic)"
  safe_rm_contents "$HOME/Library/Logs/DiagnosticReports" "DiagnosticReports"
}

clean_quicklook_cache() {
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=0
  header "$(L hdr_quicklook)"
  if command -v qlmanage &>/dev/null; then
    qlmanage -r cache >/dev/null 2>&1 \
      && success "$(L ql_reset)" \
      || warn "$(L ql_failed)"
  else
    warn "$(L ql_missing)"
  fi
}

clean_saved_app_state() {
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=0
  header "$(L hdr_saved_state)"
  safe_rm_contents "$HOME/Library/Saved Application State" "Saved Application State"
}

clean_other_trash() {
  # Other volumes trash — permanent deletion (same as emptying trash)
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=1
  header "$(L hdr_other_trash)"
  local d
  for d in /Volumes/*/.Trashes; do
    [ -d "$d" ] || continue
    safe_rm_contents "$d" "$d"
  done
  _CURRENT_IS_TRASH_EMPTY=0
}

clean_app_leftovers() {
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=0
  header "$(L hdr_app_leftovers)"

  if $JSON_MODE; then
    if [ -z "$APP_LEFTOVERS_CLEAN" ]; then
      info "$(L no_subdir_specified)"
      return
    fi

    # ── Robust comma parsing ──
    local parsed_dirs=()
    IFS=',' read -ra parsed_dirs <<< "$APP_LEFTOVERS_CLEAN"
    
    local d
    for d in "${parsed_dirs[@]}"; do
      d="${d## }"; d="${d%% }"
      [ -z "$d" ] && continue
      # Security: only ~/Library/Application Support subdirs
      local full_path="$HOME/Library/Application Support/$d"
      if [ -d "$full_path" ]; then
        safe_rm "$full_path" "$d (Application Support)"
      fi
      # Also clean preference plist if exists (except system ones)
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
  echo -e "  ${BOLD}$(L app_support_header)${NC}"
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
      printf "  ${GREEN}%-3d${NC}  %-42s  %-8s  ${GREEN}[$(L orphan_suggested)]${NC}\n" "$idx" "$base" "$sz_h"
      as_orphaned+=("true")
    else
      printf "  ${DIM}%-3d  %-42s  %-8s  [$(L installed_protected)]${NC}\n" "$idx" "$base" "$sz_h"
      as_orphaned+=("false")
    fi
    as_paths+=("$item")
    as_names+=("$base")
    idx=$((idx + 1))
  done < <(find "$HOME/Library/Application Support" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)

  echo ""
  echo -e "  $(L leftovers_select) ${BOLD}orphans${NC} = $(L orphans_only), ${BOLD}none${NC} = $(L skip):"
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
      warn "$(L all_warn)"
      if confirm "$(L all_confirm)"; then
        local j; for j in "${!as_paths[@]}"; do indices+=("$((j+1))"); done
      else
        local j; for j in "${!as_paths[@]}"; do
          if [ "${as_orphaned[$j]}" = "true" ]; then
            indices+=("$((j+1))");
          fi
        done
        info "$(L orphans_selected)"
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
    info "$(L app_support_skipped)"
  fi
}

clean_developer() {
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=0
  header "$(L hdr_developer)"

  local deriveddata="$HOME/Library/Developer/Xcode/DerivedData"
  
  if $JSON_MODE; then
    if [ -z "$DEVELOPER_CLEAN" ]; then
      info "$(L no_dev_specified)"
      return
    fi

    # ── Robust comma parsing with case-validated whitelist ──
    local parsed_items=()
    IFS=',' read -ra parsed_items <<< "$DEVELOPER_CLEAN"
    
    local item
    for item in "${parsed_items[@]}"; do
      item="${item## }"; item="${item%% }"
      [ -z "$item" ] && continue

      # Case-validate against the developer whitelist
      case "$item" in
        derived_data)
          [ -d "$deriveddata" ] && safe_rm_contents "$deriveddata" "Xcode DerivedData"
          ;;
        broken_links)
          clean_broken_symlinks_silent
          ;;
        brew_cache)
          local brew_path=""
          if command -v brew &>/dev/null; then
            brew_path=$(brew --cache 2>/dev/null || echo "")
          fi
          [ -z "$brew_path" ] && brew_path="$HOME/Library/Caches/Homebrew"
          [ -d "$brew_path" ] && safe_rm_contents "$brew_path" "Homebrew Cache"
          ;;
        docker_prune)
          if command -v docker &>/dev/null; then
            docker system prune -a -f --volumes 2>/dev/null || true
            success "$(L docker_cleaned)"
          else
            info "$(L docker_missing)"
          fi
          ;;
        npm_cache)
          local npm_cache="$HOME/.npm/_cacache"
          [ -d "$npm_cache" ] && safe_rm_contents "$npm_cache" "npm Cache"
          ;;
        pip_cache)
          local pip_cache="$HOME/Library/Caches/pip"
          [ -d "$pip_cache" ] && safe_rm_contents "$pip_cache" "pip Cache"
          ;;
        device_support)
          safe_rm_contents "$HOME/Library/Developer/Xcode/iOS DeviceSupport" "iOS DeviceSupport"
          ;;
        coresim_caches)
          safe_rm_contents "$HOME/Library/Developer/CoreSimulator/Caches" "CoreSimulator Caches"
          ;;
        xcode_archives)
          safe_rm_contents "$HOME/Library/Developer/Xcode/Archives" "Xcode Archives"
          ;;
        cocoapods_cache)
          safe_rm_contents "$HOME/Library/Caches/CocoaPods" "CocoaPods Cache"
          ;;
        pnpm_cache)
          safe_rm_contents "$HOME/Library/pnpm/store" "pnpm Store"
          ;;
        yarn_cache)
          safe_rm_contents "$HOME/Library/Caches/Yarn" "Yarn Cache"
          ;;
        gradle_cache)
          safe_rm_contents "$HOME/.gradle/caches" "Gradle Cache"
          ;;
        maven_repo)
          safe_rm_contents "$HOME/.m2/repository" "Maven Repository"
          ;;
        simctl_unavailable)
          if command -v xcrun &>/dev/null; then
            xcrun simctl delete unavailable >/dev/null 2>&1 \
              && success "$(L simctl_deleted)" \
              || warn "$(L simctl_failed)"
          fi
          ;;
        xcode_products)
          local xcode_products_dir="$HOME/Library/Developer/Xcode/Products"
          [ -d "$xcode_products_dir" ] && safe_rm_contents "$xcode_products_dir" "Xcode Products"
          ;;
        simulator_logs)
          local sim_logs_dir="$HOME/Library/Logs/CoreSimulator"
          [ -d "$sim_logs_dir" ] && safe_rm_contents "$sim_logs_dir" "Simulator Logs"
          ;;
        simulator_devices)
          # Reset simulators to factory state via simctl rather than deleting
          # the Devices directory wholesale, which corrupts CoreSimulator and
          # loses the device registry. `erase all` reclaims per-device data
          # (installed apps, settings) while keeping the devices registered.
          if command -v xcrun &>/dev/null; then
            xcrun simctl shutdown all >/dev/null 2>&1
            xcrun simctl erase all >/dev/null 2>&1 \
              && success "$(L simctl_erased)" \
              || warn "$(L simctl_failed)"
          fi
          ;;
        font_caches)
          local font_user="$HOME/Library/Caches/com.apple.FontRegistry"
          [ -d "$font_user" ] && safe_rm_contents "$font_user" "Font Caches"
          local d_font_clean
          for d_font_clean in /var/folders/*/*/*/com.apple.FontRegistry /var/folders/*/*/C/com.apple.FontRegistry; do
            [ -d "$d_font_clean" ] && safe_rm_contents "$d_font_clean" "System Font Cache"
          done
          ;;
        brew_cleanup)
          if command -v brew &>/dev/null; then
            brew cleanup -s >/dev/null 2>&1 \
              && success "$(L brew_cleanup_success)" \
              || warn "$(L brew_cleanup_failed)"
          fi
          ;;
        swift_pm_cache)
          local swift_pm_dir="$HOME/Library/Caches/org.swift.swiftpm"
          [ -d "$swift_pm_dir" ] && safe_rm_contents "$swift_pm_dir" "Swift Package Manager Cache"
          ;;
        xcode_logs)
          local d_log_clean
          for d_log_clean in "$HOME/Library/Developer/Xcode/DerivedData"/*/Logs; do
            [ -d "$d_log_clean" ] && safe_rm_contents "$d_log_clean" "Xcode Logs"
          done
          ;;
        xcode_previews)
          safe_rm_contents "$HOME/Library/Developer/Xcode/UserData/Previews" "Xcode Previews"
          ;;
        carthage_cache)
          safe_rm_contents "$HOME/Library/Caches/org.carthage.CarthageKit" "Carthage Cache"
          ;;
        bun_cache)
          safe_rm_contents "$HOME/.bun/install/cache" "Bun Cache"
          ;;
        deno_cache)
          safe_rm_contents "$HOME/Library/Caches/deno" "Deno Cache"
          ;;
        conda_pkgs)
          safe_rm_contents "$HOME/.conda/pkgs" "Conda Packages"
          ;;
        uv_cache)
          safe_rm_contents "$HOME/.cache/uv" "UV Cache"
          ;;
        poetry_cache)
          safe_rm_contents "$HOME/Library/Caches/pypoetry" "Poetry Cache"
          ;;
        go_modules)
          safe_rm_contents "$HOME/go/pkg/mod/cache" "Go Module Cache"
          ;;
        cargo_registry)
          safe_rm_contents "$HOME/.cargo/registry" "Rust Cargo Registry"
          ;;
        composer_cache)
          safe_rm_contents "$HOME/.composer/cache" "Composer Cache"
          ;;
        gradle_wrapper)
          safe_rm_contents "$HOME/.gradle/wrapper/dists" "Gradle Wrapper Dists"
          ;;
        sbt_ivy_cache)
          safe_rm_contents "$HOME/.ivy2/cache" "SBT/Ivy Cache"
          ;;
        bazel_cache)
          safe_rm_contents "$HOME/.cache/bazel" "Bazel Cache"
          ;;
        flutter_pub_cache)
          safe_rm_contents "$HOME/.pub-cache" "Flutter/Pub Cache"
          ;;
        jetbrains_cache)
          safe_rm_contents "$HOME/Library/Caches/JetBrains" "JetBrains Cache"
          ;;
        playwright_cache)
          safe_rm_contents "$HOME/Library/Caches/ms-playwright" "Playwright Browsers"
          ;;
        puppeteer_cache)
          safe_rm_contents "$HOME/.cache/puppeteer" "Puppeteer Browsers"
          ;;
        prisma_cache)
          safe_rm_contents "$HOME/.cache/prisma" "Prisma Engines"
          ;;
        huggingface_cache)
          safe_rm_contents "$HOME/.cache/huggingface" "HuggingFace Cache"
          ;;
        *)
          # Unknown key — warn and skip (never silently swallow)
          warn "$(L unknown_dev_key): '$item'"
          ;;
      esac
    done
    return
  fi

  # Interactive CLI Mode
  if [ -d "$deriveddata" ]; then
    if confirm "$(L xcode_dd_prompt)"; then
      safe_rm_contents "$deriveddata" "Xcode DerivedData"
    fi
  else
    info "$(L xcode_dd_missing)"
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
  echo -e "  ${BOLD}$(L scanning_broken_links)${NC}"
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
    info "$(L no_broken_links)"
    return
  fi

  echo ""
  warn "$(L broken_links_count) (${#broken_links[@]}):"
  local link
  for link in ${broken_links[@]+"${broken_links[@]}"}; do
    printf "  ${DIM}  %s → %s${NC}\n" "$link" "$(readlink "$link" 2>/dev/null || echo '?')"
  done
  echo ""

  if confirm "$(L delete_broken_q)"; then
    for link in ${broken_links[@]+"${broken_links[@]}"}; do
      rm -f "$link" 2>/dev/null && {
        success "$(basename "$link") $(L deleted)"
        TOTAL_ITEMS=$((TOTAL_ITEMS + 1))
      } || err "$(basename "$link") $(L delete_failed)"
    done
  fi
}

# ─── Main Flow ───────────────────────────────────────────────────────────────
category_selector() {
  echo ""
  echo -e "  ${BOLD}$(L select_categories)${NC}"
  echo ""
  local i
  for i in "${!CAT_IDS[@]}"; do
    local sz_h; sz_h=$(format_bytes "${CAT_SIZES[$i]}")
    local display_name; display_name=$(cat_name "$i")
    local sudo_tag=""
    [ "${CAT_NEEDS_SUDO[$i]}" -eq 1 ] && sudo_tag=" ${DIM}[sudo]${NC}"
    if [ "${CAT_SIZES[$i]}" -gt 0 ]; then
      printf "  ${GREEN}%d${NC}  %-26s  %s%b\n" "$((i+1))" "$display_name" "$sz_h" "$sudo_tag"
    else
      printf "  ${DIM}%d  %-26s  —%b${NC}\n" "$((i+1))" "$display_name" ""
    fi
  done
  echo ""
  echo -ne "  $(L enter_numbers) ${BOLD}all${NC} ($(L safe_only)): "
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
        warn "$(cat_name "$real_idx") $(L skipped) ($(L sudo_required))."
        continue
      fi
      _CURRENT_CATEGORY="${CAT_IDS[$real_idx]}"
      "${fn_map[$real_idx]}"
      _CURRENT_CATEGORY=""
    fi
  done
}

print_report() {
  header "📋 $(L cleanup_report)"
  echo ""
  local freed_h; freed_h=$(format_bytes "$TOTAL_FREED")
  echo -e "  ${GREEN}✅ $(L cleanup_done)${NC}"
  echo ""
  printf "  ${BOLD}%-24s${NC} %s\n" "$(L space_freed)"   "$freed_h"
  printf "  ${BOLD}%-24s${NC} %s\n" "$(L items_cleaned)"  "$TOTAL_ITEMS"
  printf "  ${BOLD}%-24s${NC} %s\n" "$(L current_free)" "$(get_free_disk)"
  echo ""
}

# ─── JSON Output Functions (Web API) ─────────────────────────────────────────

# Emit the operation log as a JSON array, newest first. Malformed lines (no
# numeric timestamp) are skipped. Empty/missing log yields [].
do_history_json() {
  echo -n "["
  local first=true
  if [ -f "$OPLOG_FILE" ]; then
    local line ts session action bytes path dest category recoverable size_h nf
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      nf=$(awk -F'\t' '{print NF}' <<<"$line")
      if [ "$nf" -eq 7 ]; then
        # Bash 3.2's `read`/array splitting collapses empty fields with
        # custom IFS (tab is IFS-whitespace), so fields are extracted via
        # awk (which handles empty fields correctly) rather than `read`.
        ts=$(awk -F'\t' '{print $1}' <<<"$line")
        action=$(awk -F'\t' '{print $3}' <<<"$line")
        bytes=$(awk -F'\t' '{print $4}' <<<"$line")
        path=$(awk -F'\t' '{print $5}' <<<"$line")
        category=$(awk -F'\t' '{print $7}' <<<"$line")
      elif [ "$nf" -eq 5 ]; then
        IFS=$'\t' read -r ts action bytes path category <<<"$line"
        session=""; dest=""
      else
        continue
      fi
      [ -z "$ts" ] && continue
      case "$ts" in *[!0-9]*) continue ;; esac
      case "$bytes" in ''|*[!0-9]*) bytes=0 ;; esac
      recoverable="false"
      [ "$action" = "trash" ] && recoverable="true"
      size_h=$(format_bytes "$bytes")
      $first || echo -n ","
      first=false
      printf '{"ts":%s,"action":"%s","bytes":%s,"size_human":"%s","path":"%s","category":"%s","recoverable":%s}' \
        "$ts" "$(json_escape_str "$action")" "$bytes" \
        "$(json_escape_str "$size_h")" "$(json_escape_str "$path")" \
        "$(json_escape_str "${category:-}")" "$recoverable"
    done < <(tail -r "$OPLOG_FILE" 2>/dev/null)
  fi
  echo "]"
}

# Human-readable operation history, newest first.
do_history() {
  if [ ! -s "$OPLOG_FILE" ]; then
    echo "  $(L no_history)"
    return 0
  fi
  printf "  %-19s  %-9s  %-10s  %-14s  %s\n" "When" "Action" "Size" "Category" "Path"
  local line ts session action bytes path dest category when size_h tag nf
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    nf=$(awk -F'\t' '{print NF}' <<<"$line")
    if [ "$nf" -eq 7 ]; then
      # Bash 3.2's `read`/array splitting collapses empty fields with
      # custom IFS (tab is IFS-whitespace), so fields are extracted via
      # awk (which handles empty fields correctly) rather than `read`.
      ts=$(awk -F'\t' '{print $1}' <<<"$line")
      action=$(awk -F'\t' '{print $3}' <<<"$line")
      bytes=$(awk -F'\t' '{print $4}' <<<"$line")
      path=$(awk -F'\t' '{print $5}' <<<"$line")
      category=$(awk -F'\t' '{print $7}' <<<"$line")
    elif [ "$nf" -eq 5 ]; then
      IFS=$'\t' read -r ts action bytes path category <<<"$line"
      session=""; dest=""
    else
      continue
    fi
    [ -z "$ts" ] && continue
    case "$ts" in *[!0-9]*) continue ;; esac
    case "$bytes" in ''|*[!0-9]*) bytes=0 ;; esac
    when=$(date -r "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$ts")
    size_h=$(format_bytes "$bytes")
    tag="$action"
    [ "$action" = "trash" ] && tag="trash↺"
    printf "  %-19s  %-9s  %-10s  %-14s  %s\n" "$when" "$tag" "$size_h" "${category:-}" "$path"
  done < <(tail -r "$OPLOG_FILE" 2>/dev/null)
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
      iCloud|Knowledge|Network|VirtualMachines|DiskImages|\
      Google|Firefox|BraveSoftware|"Microsoft Edge"|com.operasoftware.Opera|Arc) continue ;;
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

# Resolve DerivedData subfolders to project names (via info.plist WorkspacePath)
# and return a "Proj: 2.3 GB, Other: 1.1 GB +N more" summary of the biggest.
# Mirrors ClearDisk's breakdown so the user sees which projects dominate.
derived_data_project_summary() {
  local dd="$HOME/Library/Developer/Xcode/DerivedData"
  [ -d "$dd" ] || return 0
  local sub plist name ws s
  # Collect "size<TAB>name" rows for each project folder.
  local rows; rows=$(
    for sub in "$dd"/*/; do
      [ -d "$sub" ] || continue
      name=$(basename "$sub")
      case "$name" in
        (ModuleCache.noindex|.*) continue ;;
      esac
      plist="$sub/info.plist"
      ws=""
      if [ -f "$plist" ]; then
        ws=$(/usr/libexec/PlistBuddy -c "Print :WorkspacePath" "$plist" 2>/dev/null) || ws=""
      fi
      if [ -n "$ws" ]; then
        name=$(basename "$ws"); name="${name%.*}"
      else
        # Strip the trailing "-<hash>" Xcode appends to the folder name.
        name="${name%-*}"
      fi
      [ -n "$name" ] || continue
      s=$(get_dir_size_bytes "$sub") || s=0
      [ "$s" -ge 1048576 ] 2>/dev/null || continue   # > 1 MB
      printf '%s\t%s\n' "$s" "$name"
    done | sort -rn -k1,1
  )
  [ -n "$rows" ] || return 0

  local count; count=$(printf '%s\n' "$rows" | grep -c .)
  local summary="" shown=0 sz_b nm sz_h
  while IFS=$'\t' read -r sz_b nm; do
    [ -n "$sz_b" ] || continue
    [ "$shown" -ge 5 ] && break
    sz_h=$(format_bytes "$sz_b")
    [ -n "$summary" ] && summary="$summary, "
    summary="$summary$nm: $sz_h"
    shown=$((shown + 1))
  done <<< "$rows"
  if [ "$count" -gt 5 ]; then
    summary="$summary +$((count - 5)) more"
  fi
  printf '%s' "$summary"
}

# Emit a developer sub-item JSON line (leading comma; skip if path doesn't exist)
emit_dev_subitem() {
  local id="$1" name="$2" path="$3" risk="$4"
  [ -e "$path" ] || return 0
  local s; s=$(get_size_bytes "$path") || s=0
  [ "$s" -le 0 ] 2>/dev/null && return 0
  local sz_h; sz_h=$(format_bytes "$s")
  local age; age=$(dir_age_days "$path")
  local esc_name; esc_name=$(json_escape_str "$name")
  local esc_path; esc_path=$(json_escape_str "$path")
  echo "        ,{\"id\": \"$id\", \"name\": \"$esc_name\", \"path\": \"$esc_path\", \"size_bytes\": $s, \"size_human\": \"$sz_h\", \"risk\": \"$risk\", \"age_days\": $age, \"is_orphaned\": false}"
}

scan_developer_subitems_json() {
  local deriveddata="$HOME/Library/Developer/Xcode/DerivedData"
  local s_derived=0
  if [ -d "$deriveddata" ]; then
    s_derived=$(get_dir_size_bytes "$deriveddata")
  fi
  local sz_derived; sz_derived=$(format_bytes "$s_derived")
  local esc_derived_path; esc_derived_path=$(json_escape_str "$deriveddata")
  local dd_detail; dd_detail=$(derived_data_project_summary)
  local esc_dd_detail; esc_dd_detail=$(json_escape_str "$dd_detail")
  local dd_age; dd_age=$(dir_age_days "$deriveddata")
  echo "        {\"id\": \"derived_data\", \"name\": \"Xcode DerivedData\", \"path\": \"$esc_derived_path\", \"size_bytes\": $s_derived, \"size_human\": \"$sz_derived\", \"detail\": \"$esc_dd_detail\", \"age_days\": $dd_age, \"is_orphaned\": false}"
  
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
  local sz_sym; sz_sym="$broken_count items"
  echo "        ,{\"id\": \"broken_links\", \"name\": \"Broken Symlinks\", \"path\": \"\", \"size_bytes\": $s_sym, \"size_human\": \"$sz_sym\", \"is_orphaned\": true}"

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
  local brew_age; brew_age=$(dir_age_days "$brew_cache_path")
  echo "        ,{\"id\": \"brew_cache\", \"name\": \"Homebrew Cache\", \"path\": \"$esc_brew_path\", \"size_bytes\": $s_brew, \"size_human\": \"$sz_brew\", \"age_days\": $brew_age, \"is_orphaned\": false}"

  # docker data
  local docker_dir="$HOME/Library/Containers/com.docker.docker/Data"
  local s_docker=0
  [ -d "$docker_dir" ] && s_docker=$(get_dir_size_bytes "$docker_dir")
  local sz_docker; sz_docker=$(format_bytes "$s_docker")
  local esc_docker_path; esc_docker_path=$(json_escape_str "$docker_dir")
  local docker_age; docker_age=$(dir_age_days "$docker_dir")
  echo "        ,{\"id\": \"docker_prune\", \"name\": \"Docker Data\", \"path\": \"$esc_docker_path\", \"size_bytes\": $s_docker, \"size_human\": \"$sz_docker\", \"age_days\": $docker_age, \"is_orphaned\": false}"

  # npm cache
  local npm_cache_path="$HOME/.npm/_cacache"
  local s_npm=0
  [ -d "$npm_cache_path" ] && s_npm=$(get_dir_size_bytes "$npm_cache_path")
  local sz_npm; sz_npm=$(format_bytes "$s_npm")
  local esc_npm_path; esc_npm_path=$(json_escape_str "$npm_cache_path")
  local npm_age; npm_age=$(dir_age_days "$npm_cache_path")
  echo "        ,{\"id\": \"npm_cache\", \"name\": \"npm Cache\", \"path\": \"$esc_npm_path\", \"size_bytes\": $s_npm, \"size_human\": \"$sz_npm\", \"age_days\": $npm_age, \"is_orphaned\": false}"

  # pip cache
  local pip_cache_path="$HOME/Library/Caches/pip"
  local s_pip=0
  [ -d "$pip_cache_path" ] && s_pip=$(get_dir_size_bytes "$pip_cache_path")
  local sz_pip; sz_pip=$(format_bytes "$s_pip")
  local esc_pip_path; esc_pip_path=$(json_escape_str "$pip_cache_path")
  local pip_age; pip_age=$(dir_age_days "$pip_cache_path")
  echo "        ,{\"id\": \"pip_cache\", \"name\": \"pip Cache\", \"path\": \"$esc_pip_path\", \"size_bytes\": $s_pip, \"size_human\": \"$sz_pip\", \"age_days\": $pip_age, \"is_orphaned\": false}"

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
  echo "        ,{\"id\": \"simctl_unavailable\", \"name\": \"Delete Unavailable Simulators\", \"path\": \"\", \"size_bytes\": 0, \"size_human\": \"Action\", \"is_orphaned\": false}"

  emit_dev_subitem "xcode_products" "Xcode Products" \
    "$HOME/Library/Developer/Xcode/Products" "caution"
  emit_dev_subitem "simulator_logs" "Simulator Logs" \
    "$HOME/Library/Logs/CoreSimulator" "safe"
  emit_dev_subitem "simulator_devices" "Simulator Devices" \
    "$HOME/Library/Developer/CoreSimulator/Devices" "caution"

  # font_caches
  local s_font_caches=0
  local font_paths=()
  [ -d "$HOME/Library/Caches/com.apple.FontRegistry" ] && font_paths+=("$HOME/Library/Caches/com.apple.FontRegistry")
  local d_font
  for d_font in /var/folders/*/*/*/com.apple.FontRegistry /var/folders/*/*/C/com.apple.FontRegistry; do
    [ -d "$d_font" ] && font_paths+=("$d_font")
  done
  local d_p
  for d_p in "${font_paths[@]+"${font_paths[@]}"}"; do
    local sz; sz=$(get_size_bytes "$d_p")
    s_font_caches=$((s_font_caches + sz))
  done
  if [ ${#font_paths[@]} -gt 0 ] && [ "$s_font_caches" -gt 0 ]; then
    local sz_font_caches; sz_font_caches=$(format_bytes "$s_font_caches")
    local esc_font_path; esc_font_path=$(json_escape_str "$HOME/Library/Caches/com.apple.FontRegistry")
    echo "        ,{\"id\": \"font_caches\", \"name\": \"Font Caches\", \"path\": \"$esc_font_path\", \"size_bytes\": $s_font_caches, \"size_human\": \"$sz_font_caches\", \"risk\": \"safe\", \"is_orphaned\": false}"
  fi

  # brew_cleanup
  if command -v brew &>/dev/null; then
    echo "        ,{\"id\": \"brew_cleanup\", \"name\": \"Homebrew Cleanup (brew cleanup -s)\", \"path\": \"\", \"size_bytes\": 0, \"size_human\": \"Action\", \"risk\": \"safe\", \"is_orphaned\": false}"
  fi

  # swift_pm_cache
  emit_dev_subitem "swift_pm_cache" "Swift Package Manager Cache" \
    "$HOME/Library/Caches/org.swift.swiftpm" "safe"

  # xcode_logs
  local s_xcode_logs=0
  local found_logs=false
  local d_log
  for d_log in "$HOME/Library/Developer/Xcode/DerivedData"/*/Logs; do
    if [ -d "$d_log" ]; then
      local sz_log; sz_log=$(get_size_bytes "$d_log")
      s_xcode_logs=$((s_xcode_logs + sz_log))
      found_logs=true
    fi
  done
  if [ "$found_logs" = true ] && [ "$s_xcode_logs" -gt 0 ]; then
    local sz_xcode_logs; sz_xcode_logs=$(format_bytes "$s_xcode_logs")
    local esc_xcode_logs_path; esc_xcode_logs_path=$(json_escape_str "$HOME/Library/Developer/Xcode/DerivedData/*/Logs")
    echo "        ,{\"id\": \"xcode_logs\", \"name\": \"Xcode Logs\", \"path\": \"$esc_xcode_logs_path\", \"size_bytes\": $s_xcode_logs, \"size_human\": \"$sz_xcode_logs\", \"risk\": \"safe\", \"is_orphaned\": false}"
  fi

  # ── Extended developer caches (safe, rebuildable) ──
  emit_dev_subitem "xcode_previews" "Xcode Previews" \
    "$HOME/Library/Developer/Xcode/UserData/Previews" "safe"
  emit_dev_subitem "carthage_cache" "Carthage Cache" \
    "$HOME/Library/Caches/org.carthage.CarthageKit" "safe"
  emit_dev_subitem "bun_cache" "Bun Cache" \
    "$HOME/.bun/install/cache" "safe"
  emit_dev_subitem "deno_cache" "Deno Cache" \
    "$HOME/Library/Caches/deno" "safe"
  emit_dev_subitem "conda_pkgs" "Conda Packages" \
    "$HOME/.conda/pkgs" "safe"
  emit_dev_subitem "uv_cache" "UV Cache" \
    "$HOME/.cache/uv" "safe"
  emit_dev_subitem "poetry_cache" "Poetry Cache" \
    "$HOME/Library/Caches/pypoetry" "safe"
  emit_dev_subitem "go_modules" "Go Module Cache" \
    "$HOME/go/pkg/mod/cache" "safe"
  emit_dev_subitem "cargo_registry" "Rust Cargo Registry" \
    "$HOME/.cargo/registry" "safe"
  emit_dev_subitem "composer_cache" "Composer Cache" \
    "$HOME/.composer/cache" "safe"
  emit_dev_subitem "gradle_wrapper" "Gradle Wrapper Dists" \
    "$HOME/.gradle/wrapper/dists" "safe"
  emit_dev_subitem "sbt_ivy_cache" "SBT/Ivy Cache" \
    "$HOME/.ivy2/cache" "safe"
  emit_dev_subitem "bazel_cache" "Bazel Cache" \
    "$HOME/.cache/bazel" "safe"
  emit_dev_subitem "flutter_pub_cache" "Flutter/Pub Cache" \
    "$HOME/.pub-cache" "safe"
  emit_dev_subitem "jetbrains_cache" "JetBrains Cache" \
    "$HOME/Library/Caches/JetBrains" "safe"
  emit_dev_subitem "playwright_cache" "Playwright Browsers" \
    "$HOME/Library/Caches/ms-playwright" "safe"
  emit_dev_subitem "puppeteer_cache" "Puppeteer Browsers" \
    "$HOME/.cache/puppeteer" "safe"
  emit_dev_subitem "prisma_cache" "Prisma Engines" \
    "$HOME/.cache/prisma" "safe"
  emit_dev_subitem "huggingface_cache" "HuggingFace Cache" \
    "$HOME/.cache/huggingface" "caution"
}

scan_browser_full_subitems_json() {
  local first=true
  local d path s sz_h esc_id esc_path
  
  local browser_keys=("safari" "cookies" "chrome" "firefox" "brave" "edge" "opera" "arc")
  local browser_names=("Safari" "System Cookies" "Google Chrome" "Firefox" "Brave" "Microsoft Edge" "Opera" "Arc")
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
    mod_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$item" 2>/dev/null || echo "Unknown")
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

get_app_bundle_id() {
  local app_path="$1"
  local plist="$app_path/Contents/Info.plist"
  [ -f "$plist" ] || { echo ""; return; }
  local bid
  bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null) || bid=""
  # Only accept a sane reverse-DNS-style id; reject anything that could
  # widen a leftover path (slashes, dot-dot, spaces, empty).
  case "$bid" in
    ""|*/*|*..*|*" "*) echo "" ;;
    *) echo "$bid" ;;
  esac
}

# Emit the canonical leftover-path candidates for an app, NUL-separated.
# Shared by scan + clean so the two can never drift. Bundle-id-derived paths
# are emitted ONLY when a valid bundle id is known, so an empty id can never
# collapse to a whole Library subdirectory (e.g. ~/Library/Containers).
# Args: $1 = app_name, $2 = bundle_id (may be empty)
app_leftover_paths() {
  local app_name="$1" bundle_id="$2"
  [ -n "$app_name" ] || return 0
  printf '%s\0' "$HOME/Library/Application Support/$app_name"
  printf '%s\0' "$HOME/Library/Caches/$app_name"
  printf '%s\0' "$HOME/Library/Logs/$app_name"
  if [ -n "$bundle_id" ]; then
    printf '%s\0' "$HOME/Library/Caches/$bundle_id"
    printf '%s\0' "$HOME/Library/Containers/$bundle_id"
    printf '%s\0' "$HOME/Library/HTTPStorages/$bundle_id"
    printf '%s\0' "$HOME/Library/Preferences/${bundle_id}.plist"
    printf '%s\0' "$HOME/Library/Saved Application State/${bundle_id}.savedState"
  fi
}

get_app_display_name() {
  local app_path="$1"
  local plist="$app_path/Contents/Info.plist"
  [ -f "$plist" ] || { basename "$app_path" .app; return; }
  local name
  name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$plist" 2>/dev/null)
  [ -z "$name" ] && name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist" 2>/dev/null)
  [ -z "$name" ] && name=$(basename "$app_path" .app)
  
  # Strip trailing .app in case plist returned it
  name="${name%.app}"
  
  if [ "$name" = "zoom.us" ]; then
    name="Zoom"
  elif [ "$name" = "Code" ]; then
    name="Visual Studio Code"
  fi
  echo "$name"
}

scan_app_uninstaller_subitems_json() {
  local first=true
  local app app_name bundle_id leftover_total s sz_h esc_name esc_bundle esc_id disp_name
  local scan_dirs=("/Applications")
  [ -d "$HOME/Applications" ] && scan_dirs+=("$HOME/Applications")
  while IFS= read -r -d '' app; do
    app_name=$(basename "$app" .app)
    bundle_id=$(get_app_bundle_id "$app")
    leftover_total=0
    local dir
    while IFS= read -r -d '' dir; do
      [ -e "$dir" ] || continue
      s=$(get_size_bytes "$dir") || s=0
      leftover_total=$((leftover_total + s))
    done < <(app_leftover_paths "$app_name" "$bundle_id")
    sz_h=$(format_bytes "$leftover_total")
    disp_name=$(get_app_display_name "$app")
    esc_name=$(json_escape_str "$disp_name")
    esc_id=$(json_escape_str "$app_name")
    esc_bundle=$(json_escape_str "$bundle_id")
    if [ "$first" = true ]; then
      first=false
    else
      echo ","
    fi
    echo -n "        {\"id\": \"$esc_id\", \"name\": \"$esc_name\", \"bundle_id\": \"$esc_bundle\", \"size_bytes\": $leftover_total, \"size_human\": \"$sz_h\", \"is_orphaned\": false}"
  done < <(find "${scan_dirs[@]}" -maxdepth 1 -name "*.app" -print0 2>/dev/null | sort -z)
}

scan_mail_downloads_subitems_json() {
  local total=0
  local f sz_h esc_name s
  local first=true
  if [ -d "$MAIL_DOWNLOADS_DIR" ]; then
    while IFS= read -r -d '' f; do
      s=$(get_size_bytes "$f") || s=0
      total=$((total + s))
      sz_h=$(format_bytes "$s")
      esc_name=$(json_escape_str "$(basename "$f")")
      if [ "$first" = true ]; then
        first=false
      else
        echo ","
      fi
      echo -n "        {\"id\": \"$esc_name\", \"name\": \"$esc_name\", \"path\": \"\", \"size_bytes\": $s, \"size_human\": \"$sz_h\", \"is_orphaned\": false}"
    done < <(find "$MAIL_DOWNLOADS_DIR" -maxdepth 1 -mindepth 1 -print0 2>/dev/null | sort -z)
  fi
}

# ─── Project Artifact Scanner ────────────────────────────────────────────────
# Finds stale build/dependency directories (node_modules, target, .build, …)
# sitting next to a project manifest, so they can be reclaimed and rebuilt.

# Map a marker filename → "<TypeLabel> <artifact_dir_name>"
_artifact_type_for_marker() {
  case "$1" in
    package.json)                  echo "Node.js node_modules" ;;
    Cargo.toml)                    echo "Rust target" ;;
    Package.swift)                 echo "Swift .build" ;;
    go.mod)                        echo "Go vendor" ;;
    build.gradle|build.gradle.kts) echo "Gradle build" ;;
    pom.xml)                       echo "Maven target" ;;
    composer.json)                 echo "PHP vendor" ;;
    pubspec.yaml)                  echo "Flutter .dart_tool" ;;
    CMakeLists.txt)                echo "CMake build" ;;
    main.tf)                       echo "Terraform .terraform" ;;
  esac
}

# Discover artifacts; emits "<size_bytes>\t<type_label>\t<artifact_path>" lines.
_find_project_artifacts() {
  local root_rel root marker parent mbase type_info label artifact_name art_path s
  for root_rel in "${_PROJECT_SCAN_ROOTS[@]}"; do
    root="$HOME/$root_rel"
    [ -d "$root" ] || continue
    while IFS= read -r marker; do
      [ -n "$marker" ] || continue
      mbase=$(basename "$marker")
      type_info=$(_artifact_type_for_marker "$mbase")
      [ -z "$type_info" ] && continue
      label="${type_info% *}"
      artifact_name="${type_info##* }"
      parent=$(dirname "$marker")
      art_path="$parent/$artifact_name"
      [ -d "$art_path" ] || continue
      s=$(get_dir_size_bytes "$art_path") || s=0
      [ "$s" -ge "$_PROJECT_ARTIFACT_MIN_BYTES" ] 2>/dev/null || continue
      printf '%s\t%s\t%s\n' "$s" "$label" "$art_path"
    done < <(find "$root" -maxdepth 6 \
        \( -name node_modules -o -name target -o -name .build -o -name build \
           -o -name vendor -o -name .dart_tool -o -name .terraform -o -name .git \
           -o -name Pods -o -name __pycache__ \) -prune -o \
        -type f \( -name package.json -o -name Cargo.toml -o -name Package.swift \
           -o -name go.mod -o -name build.gradle -o -name build.gradle.kts \
           -o -name pom.xml -o -name composer.json -o -name pubspec.yaml \
           -o -name CMakeLists.txt -o -name main.tf \) -print 2>/dev/null)
  done
}

# Cache discovery for the lifetime of the process (scan + subitems share it).
_PROJECT_ARTIFACTS_CACHED=""
_PROJECT_ARTIFACTS_DONE=false
_get_project_artifacts() {
  if [ "$_PROJECT_ARTIFACTS_DONE" = false ]; then
    _PROJECT_ARTIFACTS_CACHED=$(_find_project_artifacts)
    _PROJECT_ARTIFACTS_DONE=true
  fi
  printf '%s\n' "$_PROJECT_ARTIFACTS_CACHED"
}

# Validate an artifact path before deletion: must be an absolute, traversal-free
# path under $HOME whose basename is a recognized artifact dir AND whose parent
# holds a recognized project marker. This is what makes the web API safe — only
# genuine artifact directories adjacent to a project manifest can be removed.
_is_valid_project_artifact() {
  local path="$1"
  case "$path" in
    /*) ;; *) return 1 ;;
  esac
  case "$path" in
    *..*) return 1 ;;
  esac
  case "$path" in
    "$HOME"/*) ;; *) return 1 ;;
  esac
  local base; base=$(basename "$path")
  case "|$_PROJECT_ARTIFACT_NAMES|" in
    *"|$base|"*) ;; *) return 1 ;;
  esac
  [ -d "$path" ] || return 1
  local parent; parent=$(dirname "$path")
  local m
  local IFS='|'
  for m in $_PROJECT_MARKERS; do
    [ -f "$parent/$m" ] && return 0
  done
  return 1
}

# Category scan_fn — sets this category's size from discovered artifacts.
scan_project_artifacts() {
  local total=0 s
  while IFS=$'\t' read -r s _ _; do
    [ -n "$s" ] && total=$((total + s))
  done < <(_get_project_artifacts)
  local i
  for i in "${!CAT_IDS[@]}"; do
    [ "${CAT_IDS[$i]}" = "project_artifacts" ] && { CAT_SIZES[$i]=$total; break; }
  done
}

clean_project_artifacts() {
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=0
  header "$(L hdr_project_artifacts)"

  if $JSON_MODE; then
    if [ -z "$PROJECT_ARTIFACT_CLEAN" ]; then
      info "$(L no_artifact_specified)"
      return
    fi
    local parsed=()
    IFS=',' read -ra parsed <<< "$PROJECT_ARTIFACT_CLEAN"
    local p
    for p in "${parsed[@]}"; do
      p="${p## }"; p="${p%% }"
      [ -z "$p" ] && continue
      if _is_valid_project_artifact "$p"; then
        safe_rm "$p" "Artifact: $p"
      else
        warn "$(L invalid_artifact): $p"
      fi
    done
    return
  fi

  # Interactive CLI mode: list each artifact and confirm individually.
  local s label path sz_h
  while IFS=$'\t' read -r s label path; do
    [ -n "$path" ] || continue
    sz_h=$(format_bytes "$s")
    if confirm "$label · $(basename "$(dirname "$path")") · $sz_h — sil?"; then
      safe_rm "$path" "Artifact: $path"
    fi
  done < <(_get_project_artifacts)
}

scan_project_artifacts_subitems_json() {
  local first=true s label path sz_h esc_id esc_label esc_name proj_name orphaned mtime now days
  now=$(date +%s)
  while IFS=$'\t' read -r s label path; do
    [ -n "$path" ] || continue
    sz_h=$(format_bytes "$s")
    proj_name=$(basename "$(dirname "$path")")
    orphaned=false
    mtime=$(stat -f %m "$path" 2>/dev/null || echo "$now")
    days=$(( (now - mtime) / 86400 ))
    [ "$days" -gt 30 ] && orphaned=true
    esc_id=$(json_escape_str "$path")
    esc_label=$(json_escape_str "$label")
    esc_name=$(json_escape_str "$proj_name")
    if [ "$first" = true ]; then first=false; else echo ","; fi
    echo -n "        {\"id\": \"$esc_id\", \"name\": \"$esc_name\", \"type\": \"$esc_label\", \"path\": \"$esc_id\", \"size_bytes\": $s, \"size_human\": \"$sz_h\", \"days_since\": $days, \"is_orphaned\": $orphaned}"
  done < <(_get_project_artifacts)
}

# ─── Special Action Handlers ────────────────────────────────────────────────

# Emit recent operations grouped by session as JSON for the web UI.
do_ops_json() {
  JSON_MODE=true
  if [ ! -f "$OPLOG_FILE" ]; then
    printf '{"success":true,"sessions":[]}\n'; return 0
  fi
  while IFS=$'\t' read -r id rest; do
    local ts session action bytes source dest category recoverable nf
    # Bash 3.2's `read`/array splitting collapses empty fields with custom
    # IFS, so fields are extracted via awk (which handles empty fields
    # correctly) rather than `read`.
    nf=$(awk -F'\t' '{print NF}' <<<"$rest")
    if [ "$nf" -eq 7 ]; then
      ts=$(awk -F'\t' '{print $1}' <<<"$rest")
      session=$(awk -F'\t' '{print $2}' <<<"$rest")
      action=$(awk -F'\t' '{print $3}' <<<"$rest")
      bytes=$(awk -F'\t' '{print $4}' <<<"$rest")
      source=$(awk -F'\t' '{print $5}' <<<"$rest")
      dest=$(awk -F'\t' '{print $6}' <<<"$rest")
      category=$(awk -F'\t' '{print $7}' <<<"$rest")
    elif [ "$nf" -eq 5 ]; then
      # legacy 5-col line: ts action bytes path category
      ts=$(awk -F'\t' '{print $1}' <<<"$rest")
      action=$(awk -F'\t' '{print $2}' <<<"$rest")
      bytes=$(awk -F'\t' '{print $3}' <<<"$rest")
      source=$(awk -F'\t' '{print $4}' <<<"$rest")
      category=$(awk -F'\t' '{print $5}' <<<"$rest")
      session="legacy"; dest=""
    else
      continue
    fi
    [ -z "$ts" ] && continue
    case "$bytes" in ''|*[!0-9]*) bytes=0 ;; esac
    recoverable=false
    if [ "$action" = "trash" ] && [ -n "$dest" ] && [ -e "$dest" ]; then
      local parent; parent="$(dirname "$source")"
      { [ ! -e "$source" ] || [ -d "$parent" ]; } && recoverable=true
    fi
    local esc_src esc_dest esc_cat esc_session
    esc_src=$(json_escape_str "$source"); esc_dest=$(json_escape_str "$dest")
    esc_cat=$(json_escape_str "$category")
    # Escape session before it enters the awk aggregation pipeline below,
    # since awk can't call the bash json_escape_str helper itself.
    esc_session=$(json_escape_str "$session")
    local item
    item="{\"id\":$id,\"source\":\"$esc_src\",\"trash_dest\":\"$esc_dest\",\"bytes\":${bytes:-0},\"category\":\"$esc_cat\",\"action\":\"$action\",\"recoverable\":$recoverable}"
    # Stash: SESSION<TAB>TS<TAB>BYTES<TAB>REC<TAB>ITEMJSON
    printf '%s\t%s\t%s\t%s\t%s\n' "$esc_session" "${ts:-0}" "${bytes:-0}" "$recoverable" "$item"
  done < <(awk '{printf "%d\t%s\n", NR, $0}' "$OPLOG_FILE") \
    | awk -F'\t' '
        { sess=$1; ts=$2; by=$3; rec=$4; item=$5;
          if (!(sess in firstts)) { order[++k]=sess; firstts[sess]=ts }
          if (ts+0 < firstts[sess]+0) firstts[sess]=ts;
          tot[sess]+=by; cnt[sess]++; if (rec=="true") reccnt[sess]++;
          items[sess]=items[sess] (items[sess]==""?"":",") item;
        }
        END {
          printf "{\"success\":true,\"sessions\":[";
          # newest session first: order[] is file order (old->new); reverse it, cap 20.
          first=1; printed=0;
          for (j=k; j>=1 && printed<20; j--) {
            s=order[j];
            if (!first) printf ","; first=0;
            printf "{\"session_id\":\"%s\",\"start_ts\":%d,\"total_bytes\":%d,\"item_count\":%d,\"recoverable_count\":%d,\"items\":[%s]}",
              s, firstts[s], tot[s], cnt[s], (reccnt[s]+0), items[s];
            printed++;
          }
          printf "]}\n";
        }'
}

do_restore_json() {
  JSON_MODE=true
  local mode="$1" selector="$2"
  local restored="" skipped="" failed=""
  if [ ! -f "$OPLOG_FILE" ]; then
    printf '{"success":true,"restored":[],"skipped":[],"failed":[]}\n'; return 0
  fi
  # Build a quick membership test for explicit item ids.
  local want_ids=",$selector,"
  local id ts session action bytes source dest category nf
  while IFS=$'\t' read -r id rest; do
    # Bash 3.2's `read`/array splitting collapses empty fields with custom
    # IFS, so fields are extracted via awk (which handles empty fields
    # correctly) rather than `read`, mirroring do_ops_json.
    nf=$(awk -F'\t' '{print NF}' <<<"$rest")
    if [ "$nf" -eq 7 ]; then
      ts=$(awk -F'\t' '{print $1}' <<<"$rest")
      session=$(awk -F'\t' '{print $2}' <<<"$rest")
      action=$(awk -F'\t' '{print $3}' <<<"$rest")
      bytes=$(awk -F'\t' '{print $4}' <<<"$rest")
      source=$(awk -F'\t' '{print $5}' <<<"$rest")
      dest=$(awk -F'\t' '{print $6}' <<<"$rest")
      category=$(awk -F'\t' '{print $7}' <<<"$rest")
    else
      continue   # legacy 5-col lines are never restorable
    fi
    [ -z "$ts" ] && continue
    # Selection filter
    if [ "$mode" = "session" ]; then
      [ "$session" = "$selector" ] || continue
    else
      case "$want_ids" in *",$id,"*) : ;; *) continue ;; esac
    fi
    local esc_src; esc_src=$(json_escape_str "$source")
    if [ "$action" != "trash" ]; then
      skipped="$skipped${skipped:+,}{\"source\":\"$esc_src\",\"reason\":\"not_recoverable\"}"; continue
    fi
    # Guard: protected/system source
    case "$source" in
      /System/*|/usr/*|/bin/*|/sbin/*|/etc/*|/private/etc/*)
        skipped="$skipped${skipped:+,}{\"source\":\"$esc_src\",\"reason\":\"protected\"}"; continue ;;
    esac
    # Trash item gone
    if [ -z "$dest" ] || [ ! -e "$dest" ]; then
      skipped="$skipped${skipped:+,}{\"source\":\"$esc_src\",\"reason\":\"trash_missing\"}"; continue
    fi
    # Parent dir gone
    local parent; parent="$(dirname "$source")"
    if [ ! -d "$parent" ]; then
      skipped="$skipped${skipped:+,}{\"source\":\"$esc_src\",\"reason\":\"parent_missing\"}"; continue
    fi
    # Collision -> rename
    local target="$source" reason="ok"
    if [ -e "$source" ]; then
      target="$source (restored)"; reason="renamed"
    fi
    if mv "$dest" "$target" 2>/dev/null; then
      oplog_record "restore" "$bytes" "$target" "" "$category"
      restored="$restored${restored:+,}{\"source\":\"$(json_escape_str "$target")\",\"reason\":\"$reason\"}"
    else
      failed="$failed${failed:+,}{\"source\":\"$esc_src\",\"reason\":\"move_failed\"}"
    fi
  done < <(awk '{printf "%d\t%s\n", NR, $0}' "$OPLOG_FILE")
  printf '{"success":true,"restored":[%s],"skipped":[%s],"failed":[%s]}\n' \
    "$restored" "$skipped" "$failed"
}

do_flush_dns() {
  JSON_MODE=true
  local ok=true
  dscacheutil -flushcache 2>/dev/null || ok=false
  killall -HUP mDNSResponder 2>/dev/null || ok=false
  if $ok; then
    printf '{"success":true,"message":"%s"}\n' "$(L dns_flushed)"
  else
    printf '{"success":false,"error":"%s"}\n' "$(L dns_failed)"
  fi
}

do_purge_ram() {
  JSON_MODE=true
  if purge 2>/dev/null; then
    printf '{"success":true,"message":"%s"}\n' "$(L ram_purged)"
  else
    printf '{"success":false,"error":"%s"}\n' "$(L ram_failed)"
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
    tmutil thinLocalSnapshots / 10000000000 4 >/dev/null 2>&1 || note="no_permission_or_snapshots"
    after=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple.TimeMachine" || true)
    [ -z "$after" ] && after=0
  fi
  printf '{"success":true,"snapshots_before":%s,"snapshots_after":%s,"note":"%s","disk_free":"%s"}\n' \
    "$before" "$after" "$note" "$(get_free_disk)"
}

do_spotlight_reindex() {
  if ! $SUDO_AVAILABLE && [ "$(id -u)" -ne 0 ]; then
    echo '{"success": false, "error": "Spotlight reindexing requires sudo privileges."}'
    exit 1
  fi
  sudo mdutil -i off / >/dev/null 2>&1 || true
  sudo mdutil -E / >/dev/null 2>&1 || true
  sudo mdutil -i on / >/dev/null 2>&1 || true
  printf '{"success": true, "status": "started", "message": "%s"}\n' "$(L spotlight_rebuild)"
}

# ─── JSON Scan ───────────────────────────────────────────────────────────────

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
    local in_total="false"
    [ "${CAT_IN_TOTAL[$i]}" -eq 1 ] && in_total="true"

    echo "    \"$id\": {"
    echo "      \"size_bytes\": ${CAT_SIZES[$i]},"
    echo "      \"size_human\": \"$sz_h\","
    echo "      \"needs_sudo\": $needs_sudo,"
    echo "      \"in_total\": $in_total,"
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
    elif [ "$id" = "project_artifacts" ]; then
      echo "      ,\"subitems\": ["
      scan_project_artifacts_subitems_json
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

# ─── JSON Clean ──────────────────────────────────────────────────────────────

do_clean_json() {
  local cats_csv="$1"
  SUDO_AVAILABLE=false
  JSON_MODE=true

  # ── Robust comma parsing for category numbers ──
  local cat_nums=()
  IFS=',' read -ra cat_nums <<< "$cats_csv"

  # Run scan first (never let a non-zero scan abort JSON emission)
  scan_all >/dev/null 2>&1 || true

  # Reset counters
  TOTAL_FREED=0
  TOTAL_ITEMS=0
  CLEAN_RESULTS=()

  # Pre-clean free space measurement (KB, available on /)
  local df_before
  df_before=$(df -k / 2>/dev/null | awk 'NR==2 {print $4}')

  # Build clean function map
  local fn_map=()
  local _i
  for _i in "${!CAT_IDS[@]}"; do fn_map+=("$(cat_field "$_i" clean_fn)"); done

  local idx
  for idx in "${cat_nums[@]}"; do
    # Trim whitespace
    idx="${idx## }"; idx="${idx%% }"
    [ -z "$idx" ] && continue
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

  # Post-clean free space; real gain = df delta (bytes)
  local df_after real_freed freed_source
  df_after=$(df -k / 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -n "$df_before" ] && [ -n "$df_after" ]; then
    real_freed=$(( (df_after - df_before) * 1024 ))
    [ "$real_freed" -lt 0 ] && real_freed=0
    freed_source="df"
  else
    real_freed=$TOTAL_FREED
    freed_source="estimated"
  fi
  local estimated_bytes=$TOTAL_FREED
  local freed_h; freed_h=$(format_bytes "$real_freed")
  local est_h; est_h=$(format_bytes "$estimated_bytes")

  # JSON output
  local dry_run_json="false"
  [ "$DRYRUN" = "1" ] && dry_run_json="true"
  echo '{'
  echo '  "success": true,'
  echo "  \"dry_run\": $dry_run_json,"
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

# ─── Main ────────────────────────────────────────────────────────────────────
main() {
  local args=("$@")
  local i=0
  local clean_csv=""
  
  while [ $i -lt ${#args[@]} ]; do
    case "${args[$i]}" in
      --lang)
        i=$((i + 1))
        LANG_KEY="${args[$i]}"
        ;;
      --scan-json)
        do_scan_json
        exit 0
        ;;
      --status-json)
        do_status_json
        exit 0
        ;;
      --history)
        do_history
        exit 0
        ;;
      --history-json)
        do_history_json
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
      --project-artifact-sub)
        i=$((i + 1))
        PROJECT_ARTIFACT_CLEAN="${args[$i]}"
        ;;
      --__noop)
        # Test hook: allow `source clean_mac.sh --__noop` to load functions
        # without executing the interactive flow. No-op.
        ;;
      --flush-dns)
        do_flush_dns
        exit 0
        ;;
      --ops-json)
        do_ops_json
        exit 0
        ;;
      --restore-session)
        i=$((i + 1)); do_restore_json session "${args[$i]}"; exit 0
        ;;
      --restore-items)
        i=$((i + 1)); do_restore_json items "${args[$i]}"; exit 0
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
        echo -e "${BOLD}clean_mac v${VERSION}${NC} — $(L version_banner)"
        echo ""
        echo "Usage: bash clean_mac.sh [OPTIONS]"
        echo ""
        echo -e "${BOLD}Categories:${NC}"
        local ci
        for ci in "${!CAT_IDS[@]}"; do
          local dn; dn=$(cat_name "$ci")
          local st=""
          [ "${CAT_NEEDS_SUDO[$ci]}" -eq 1 ] && st=" [sudo]"
          printf "  %-3d  %s%s\n" "$((ci+1))" "$dn" "$st"
        done
        echo ""
        echo -e "${BOLD}Web API:${NC}"
        echo "  --scan-json              Scan results as JSON"
        echo "  --clean-json 1,3,7       Clean specified categories, return JSON"
        echo "  --app-leftovers 'd1,d2'  Leftover folder names to delete"
        echo "  --browser-full-sub 'c,s' Browser keys to reset (chrome, safari...)"
        echo "  --developer-sub 'd,b'    Developer sub-items (derived_data, broken_links...)"
        echo "  --ios-backups-sub 'u1,u2' iOS backup UUIDs to delete"
        echo "  --app-uninstaller-sub 'a' Apps to uninstall"
        echo "  --project-artifact-sub 'p1,p2' Project artifact paths to delete"
        echo "  --status-json            System status as JSON"
        echo "  --thin-snapshots-json    Thin local TM snapshots, return JSON"
        echo "  --ops-json               List restorable operations as JSON"
        echo "  --restore-session <id>   Restore all recoverable items in a run"
        echo "  --restore-items <i,j>    Restore specific operation ids"
        echo "  --flush-dns              Flush DNS cache"
        echo "  --purge-ram              Purge RAM cache"
        echo "  --launchagents-clean     Clean invalid LaunchAgents"
        echo "  --spotlight-reindex      Rebuild Spotlight index"
        echo "  --lang en|tr             Set UI language (default: tr)"
        echo ""
        echo "Env vars:"
        echo "  APPLE_CLEANUP_LANG       UI language (tr|en)"
        echo "  APPLE_CLEANUP_FORCE_RM   Set to 1 to bypass trash-first (CI/testing)"
        echo "  APPLE_CLEANUP_DRYRUN     Set to 1 to preview only (deletes nothing)"
        echo "  APPLE_CLEANUP_EXCLUDE    Colon-separated paths/globs to protect"
        echo ""
        echo "Note: Downloads folder is never touched."
        echo ""
        exit 0
        ;;
    esac
    i=$((i + 1))
  done

  # If clean_csv was captured, run in JSON mode
  if [ -n "$clean_csv" ]; then
    do_clean_json "$clean_csv"
    exit 0
  fi

  # Terminal Interactive Mode
  clear
  header "🍎 clean_mac v${VERSION} — $(L version_banner)"
  echo ""
  echo -e "  macOS     : $(sw_vers -productVersion 2>/dev/null || echo '?')"
  echo -e "  User      : $(whoami)"
  echo -e "  Date      : $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  info "$(L scan_first)"
  warn "$(L critical_protected)"
  echo ""

  sudo_check
  scan_all
  print_scan_table

  echo -e "  ${BOLD}$(L what_to_do)${NC}"
  echo ""
  echo -e "  ${GREEN}1${NC}  $(L quick_clean)"
  echo -e "  ${GREEN}2${NC}  $(L selective_clean)"
  echo -e "  ${RED}3${NC}  $(L cancel)"
  echo ""
  echo -ne "  $(L your_choice) [1/2/3]: "
  local choice; read -r choice

  case "$choice" in
    1)
      echo ""
      warn "$(L safe_clean_info)"
      confirm "$(L continue_prompt)" || { echo ""; info "$(L cancelled)"; exit 0; }
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
        info "$(L no_selection)"
        exit 0
      fi
      echo ""
      confirm "$(L selected_clean_q)" || { info "$(L cancelled)"; exit 0; }
      run_clean "${selected_nums[@]}"
      ;;
    *)
      echo ""
      info "$(L cancelled)"
      exit 0
      ;;
  esac

  print_report
}

# Only run main when executed directly, not when sourced (e.g. by tests).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
