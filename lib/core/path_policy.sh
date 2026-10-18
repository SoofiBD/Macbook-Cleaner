#!/usr/bin/env bash
# Shared deletion-path and live-file policy. This file is sourced by
# clean_mac.sh after localization and global cleanup state are initialized.

# Classify the only filesystem scopes the cleaner is allowed to mutate. The
# value is used both before and after resolving parent symlinks; a scope change
# is treated as an escape and rejected.
_removal_scope() {
  local path="$1"
  # APFS is case-insensitive, so "$HOME/downloads" is the protected folder too.
  local downloads_scope="" had_nocase=0
  shopt -q nocasematch && had_nocase=1
  shopt -s nocasematch
  case "$path" in
    "$HOME/Downloads") downloads_scope="protected" ;;
    "$HOME/Downloads"/*) downloads_scope="installer_download" ;;
  esac
  [ "$had_nocase" -eq 1 ] || shopt -u nocasematch
  if [ -n "$downloads_scope" ]; then
    echo "$downloads_scope"
    return 0
  fi
  case "$path" in
    "$HOME") echo "protected" ;;
    "$HOME"/*) echo "home" ;;
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) echo "temporary" ;;
    /Library/Caches/*) echo "system_cache" ;;
    /Library/Logs/*) echo "system_logs" ;;
    /Library/LaunchAgents/*|/Library/LaunchDaemons/*) echo "launchagents" ;;
    /Applications/*.app) echo "applications" ;;
    /Volumes/*/.Trashes/*) echo "external_trash" ;;
    *) echo "protected" ;;
  esac
}

_scope_allowed_for_context() {
  local scope="$1"
  case "$scope" in
    home|temporary) return 0 ;;
    system_cache) [ "$_CURRENT_CATEGORY" = "system_cache" ] ;;
    system_logs) [ "$_CURRENT_CATEGORY" = "logs" ] ;;
    launchagents) [ "$_CURRENT_CATEGORY" = "launchagents" ] ;;
    applications) [ "$_CURRENT_CATEGORY" = "app_uninstaller" ] ;;
    external_trash) [ "$_CURRENT_CATEGORY" = "other_trash" ] ;;
    installer_download) [ "$_CURRENT_CATEGORY" = "installer_artifacts" ] ;;
    *) return 1 ;;
  esac
}

# Validate a deletion target without resolving the final component. Removing a
# leaf symlink removes the link itself; resolving its parent catches ancestor
# symlink escapes that could redirect rm to a different filesystem scope.
# Mode "contents" additionally rejects a symlink target and resolves the target
# directory itself because its children are about to be traversed.
_validate_removal_path() {
  local path="$1"
  local mode="${2:-leaf}"
  local label="${3:-$1}"
  local reason=""

  if [ -z "$path" ]; then
    reason="$(L empty_path): $label"
  elif [ "${path#/}" = "$path" ]; then
    reason="$(L protected_path): relative path: $path"
  elif printf '%s' "$path" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    reason="$(L protected_path): control character in path"
  else
    case "$path" in
      */../*|*/..) reason="$(L protected_path): parent traversal: $path" ;;
      /|//*) reason="$(L protected_path): $path" ;;
    esac
  fi

  local logical_scope=""
  if [ -z "$reason" ]; then
    logical_scope=$(_removal_scope "$path")
    if ! _scope_allowed_for_context "$logical_scope"; then
      reason="$(L protected_path): $path"
    fi
  fi

  local physical_path="" parent base physical_parent physical_scope
  if [ -z "$reason" ]; then
    if [ "$mode" = "contents" ]; then
      if [ -L "$path" ]; then
        reason="$(L protected_path): symlinked directory: $path"
      else
        physical_path=$(cd -P "$path" 2>/dev/null && pwd -P) || \
          reason="$(L protected_path): unresolved path: $path"
      fi
    else
      parent=$(dirname "$path")
      base=$(basename "$path")
      physical_parent=$(cd -P "$parent" 2>/dev/null && pwd -P) || \
        reason="$(L protected_path): unresolved parent: $path"
      [ -n "$physical_parent" ] && physical_path="$physical_parent/$base"
    fi
  fi

  if [ -z "$reason" ]; then
    physical_scope=$(_removal_scope "$physical_path")
    if [ "$logical_scope" != "$physical_scope" ] || \
       ! _scope_allowed_for_context "$physical_scope"; then
      reason="$(L protected_path): symlink scope escape: $path"
    fi
  fi

  if [ -n "$reason" ]; then
    err "$reason"
    record_clean_error "$reason"
    return 1
  fi
  return 0
}

_requires_live_guard() {
  case "$1" in
    "$HOME/Library/Caches"/*|\
    "$HOME/Library/Safari"|"$HOME/Library/Safari"/*|\
    "$HOME/Library/Cookies"|"$HOME/Library/Cookies"/*|\
    "$HOME/Library/WebKit"/*|"$HOME/Library/HTTPStorages"/*|\
    "$HOME/Library/Application Support/Google/Chrome"|\
    "$HOME/Library/Application Support/Google/Chrome"/*|\
    "$HOME/Library/Application Support/Firefox"|\
    "$HOME/Library/Application Support/Firefox"/*|\
    "$HOME/Library/Application Support/BraveSoftware"|\
    "$HOME/Library/Application Support/BraveSoftware"/*|\
    "$HOME/Library/Application Support/Microsoft Edge"|\
    "$HOME/Library/Application Support/Microsoft Edge"/*|\
    "$HOME/Library/Application Support/Arc"|\
    "$HOME/Library/Application Support/Arc"/*) return 0 ;;
  esac
  return 1
}

_path_contains_database() {
  local path="$1"
  [ -d "$path" ] || return 1
  find "$path" -maxdepth 4 -type f \
    \( -name '*.sqlite' -o -name '*.sqlite3' -o -name '*.db' \
       -o -name '*-wal' -o -name '*-shm' \) -print -quit 2>/dev/null | \
    grep -q .
}

# Return 0 when lsof found an open file, 1 when it found none, and 2 when the
# inspection was unavailable or exceeded its deadline. The deadline prevents a
# recursive lsof walk from hanging a cleanup on large browser profiles.
# One system-wide open-file snapshot, reused for up to 2 seconds. Running
# `lsof +D <dir>` per cleaned directory walked each tree and cost 0.15-1.3 s
# per call; a full `lsof -F n` listing costs ~0.1 s and covers every path.
_OPEN_FILES_SNAPSHOT=""
_OPEN_FILES_AT=-100

_refresh_open_files_snapshot() {
  [ -n "$_OPEN_FILES_SNAPSHOT" ] && [ $((SECONDS - _OPEN_FILES_AT)) -lt 2 ] && return 0
  local lsof_bin pid loops=0
  lsof_bin=$(command -v lsof 2>/dev/null) || return 1
  if [ -z "$_OPEN_FILES_SNAPSHOT" ]; then
    _OPEN_FILES_SNAPSHOT=$(mktemp "${TMPDIR:-/tmp}/apple-cleanup-lsof.XXXXXX") || return 1
    trap 'rm -f "$_OPEN_FILES_SNAPSHOT"' EXIT
  fi
  # Every guarded path is under $HOME, so keep only those lines (resolved,
  # as lsof reports them); per-path greps then scan a few KB, not megabytes.
  local home_physical
  home_physical=$(cd -P "$HOME" 2>/dev/null && pwd -P) || home_physical="$HOME"
  # awk fails when lsof printed nothing at all (it always lists itself), so a
  # broken lsof reads as "cannot verify", never as "nothing open".
  { "$lsof_bin" -nP -F n 2>/dev/null | P="n$home_physical/" awk '
      BEGIN { p = ENVIRON["P"] } index($0, p) == 1 { print } END { exit NR == 0 }
    ' >"$_OPEN_FILES_SNAPSHOT"; } &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$loops" -ge 60 ]; then  # 3 s cap
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      _OPEN_FILES_AT=-100
      return 1
    fi
    sleep 0.05
    loops=$((loops + 1))
  done
  wait "$pid" 2>/dev/null || { _OPEN_FILES_AT=-100; return 1; }
  _OPEN_FILES_AT=$SECONDS
}

# 0 = something under path is open, 1 = nothing open, 2 = cannot verify.
_path_has_open_files() {
  local path="$1" physical status
  _refresh_open_files_snapshot || return 2
  # lsof reports resolved paths.
  physical=$(cd -P "$path" 2>/dev/null && pwd -P) || physical="$path"
  # Lines are "n<path>". A substring hit elsewhere in a line can only cause a
  # false positive, which skips the item: the safe direction.
  status=0
  grep -qF -e "n$physical/" "$_OPEN_FILES_SNAPSHOT" && return 0 || status=$?
  [ "$status" -eq 1 ] || return 2
  grep -qxF -e "n$physical" "$_OPEN_FILES_SNAPSHOT" && return 0 || status=$?
  [ "$status" -eq 1 ] && return 1
  return 2
}

_RUNNING_APPS=""
_RUNNING_APPS_AT=-100

_path_owner_is_running() {
  local path="$1" owner bundle_id=""
  owner=$(basename "$path")
  case "$path" in
    "$HOME/Library/Safari"*) bundle_id="com.apple.Safari" ;;
    *"/Google/Chrome"*) bundle_id="com.google.Chrome" ;;
    *"/Firefox"*) bundle_id="org.mozilla.firefox" ;;
    *"/BraveSoftware"*) bundle_id="com.brave.Browser" ;;
    *"/Microsoft Edge"*) bundle_id="com.microsoft.edgemac" ;;
    *"/Arc"*) bundle_id="company.thebrowser.Browser" ;;
    *)
      case "$owner" in
        com.*|org.*|net.*|io.*|dev.*) bundle_id="$owner" ;;
      esac
      ;;
  esac
  [ -n "$bundle_id" ] || return 1
  [ -x /usr/bin/lsappinfo ] || return 1
  # Cached for 2 seconds: this runs once per cleaned directory.
  if [ $((SECONDS - _RUNNING_APPS_AT)) -ge 2 ]; then
    _RUNNING_APPS=$(/usr/bin/lsappinfo list 2>/dev/null) || return 1
    _RUNNING_APPS_AT=$SECONDS
  fi
  case "$_RUNNING_APPS" in *"$bundle_id"*) return 0 ;; esac
  return 1
}

_guard_live_path() {
  local path="$1" label="${2:-$1}" open_status
  _requires_live_guard "$path" || return 0

  if _path_owner_is_running "$path"; then
    warn "$label: $(L active_path_skipped)"
    record_clean_warning "$label: $(L active_path_skipped)"
    return 1
  fi

  if _path_has_open_files "$path"; then
    open_status=0
  else
    open_status=$?
  fi
  if [ "$open_status" -eq 0 ]; then
    warn "$label: $(L active_path_skipped)"
    record_clean_warning "$label: $(L active_path_skipped)"
    return 1
  fi
  if [ "$open_status" -eq 2 ] && _path_contains_database "$path"; then
    warn "$label: $(L live_check_failed)"
    record_clean_warning "$label: $(L live_check_failed)"
    return 1
  fi
  return 0
}
