#!/usr/bin/env bash
# shellcheck disable=SC2034
# Explicit, identity-bound cleanup for installer files in ~/Downloads.
# Nothing is selected automatically and bulk deletion is intentionally absent.

_INSTALLER_ARTIFACT_MIN_BYTES=10485760
_INSTALLER_ARTIFACTS_CACHED=""
_INSTALLER_ARTIFACTS_DONE=false

_installer_artifact_identity() {
  local path="$1" parent physical_parent physical_downloads
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  [ ! -L "$HOME/Downloads" ] || return 1
  case "$path" in
    "$HOME"/Downloads/*.dmg|"$HOME"/Downloads/*.DMG|\
    "$HOME"/Downloads/*.pkg|"$HOME"/Downloads/*.PKG|\
    "$HOME"/Downloads/*.iso|"$HOME"/Downloads/*.ISO) ;;
    *) return 1 ;;
  esac
  case "$path" in *','*|*$'\t'*|*$'\n'*|*$'\r'*|*'/../'*|*'/./'*|*'//'*) return 1 ;; esac
  parent=$(dirname "$path")
  [ "$parent" = "$HOME/Downloads" ] || return 1
  physical_parent=$(cd -P "$parent" 2>/dev/null && pwd -P) || return 1
  physical_downloads=$(cd -P "$HOME/Downloads" 2>/dev/null && pwd -P) || return 1
  [ "$physical_parent" = "$physical_downloads" ] || return 1
  stat -f '%d:%i:%z:%m' "$path" 2>/dev/null || \
    stat -c '%d:%i:%s:%Y' "$path" 2>/dev/null
}

_find_installer_artifacts() {
  local downloads="$HOME/Downloads" path size identity mtime now days kind
  [ -d "$downloads" ] && [ ! -L "$downloads" ] || return 0
  now=$(date +%s)
  while IFS= read -r -d '' path; do
    case "$path" in *','*|*$'\t'*|*$'\n'*|*$'\r'*) continue ;; esac
    identity=$(_installer_artifact_identity "$path") || continue
    size=$(get_size_bytes "$path") || size=0
    [ "$size" -ge "$_INSTALLER_ARTIFACT_MIN_BYTES" ] 2>/dev/null || continue
    mtime=$(stat -f %m "$path" 2>/dev/null || stat -c %Y "$path" 2>/dev/null || echo "$now")
    days=$(( (now - mtime) / 86400 ))
    case "$path" in
      *.dmg|*.DMG) kind="Disk image" ;;
      *.pkg|*.PKG) kind="Installer package" ;;
      *) kind="ISO image" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$size" "$days" "$kind" "$path" "$identity"
  done < <(find "$downloads" -maxdepth 1 -mindepth 1 -type f \
    \( -name '*.dmg' -o -name '*.DMG' -o -name '*.pkg' -o -name '*.PKG' \
       -o -name '*.iso' -o -name '*.ISO' \) -print0 2>/dev/null)
}

_get_installer_artifacts() {
  if [ "$_INSTALLER_ARTIFACTS_DONE" = false ]; then
    _INSTALLER_ARTIFACTS_CACHED=$(_find_installer_artifacts)
    _INSTALLER_ARTIFACTS_DONE=true
  fi
  printf '%s\n' "$_INSTALLER_ARTIFACTS_CACHED"
}

scan_installer_artifacts() {
  local total=0 size i
  while IFS=$'\t' read -r size _; do
    [ -n "$size" ] && total=$((total + size))
  done < <(_get_installer_artifacts)
  i=$(cat_index_by_id installer_artifacts)
  CAT_SIZES[i]=$total
}

clean_installer_artifacts() {
  _CURRENT_NEEDS_SUDO=0; _CURRENT_IS_TRASH_EMPTY=0
  header "$(L hdr_installer_artifacts)"
  if [ -z "$INSTALLER_ARTIFACT_CLEAN" ]; then
    warn "$(L no_installer_artifact_specified)"
    record_clean_warning "$(L no_installer_artifact_specified)"
    return
  fi

  local paths=() identities=() path expected index=0
  IFS=',' read -ra paths <<< "$INSTALLER_ARTIFACT_CLEAN"
  IFS=',' read -ra identities <<< "$INSTALLER_ARTIFACT_IDENTITIES"
  for path in "${paths[@]}"; do
    expected="${identities[$index]:-}"
    index=$((index + 1))
    if [ -n "$expected" ] && \
       [ "$(_installer_artifact_identity "$path" 2>/dev/null || true)" = "$expected" ]; then
      safe_rm "$path" "Installer: $(basename "$path")" "$expected" installer_artifact
    else
      warn "$(L invalid_installer_artifact): $path"
      record_clean_error "$(L invalid_installer_artifact): missing or changed scan identity: $path"
    fi
  done
}

scan_installer_artifacts_subitems_json() {
  local first=true size days kind path identity sz_h esc_path esc_name esc_kind
  while IFS=$'\t' read -r size days kind path identity; do
    [ -n "$path" ] || continue
    sz_h=$(format_bytes "$size")
    esc_path=$(json_escape_str "$path")
    esc_name=$(json_escape_str "$(basename "$path")")
    esc_kind=$(json_escape_str "$kind")
    if [ "$first" = true ]; then first=false; else echo ","; fi
    echo -n "        {\"id\": \"$esc_path\", \"identity\": \"$identity\", \"name\": \"$esc_name\", \"type\": \"$esc_kind\", \"path\": \"$esc_path\", \"size_bytes\": $size, \"size_human\": \"$sz_h\", \"days_since\": $days, \"is_orphaned\": false}"
  done < <(_get_installer_artifacts)
}
