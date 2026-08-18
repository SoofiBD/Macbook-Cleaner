#!/usr/bin/env bash
# shellcheck disable=SC2034
# CAT_SIZES is consumed by the parent scan router after this sourced module
# updates the shared category registry.
# Project artifact discovery, identity binding, scan output, and cleanup.
# Sourced by clean_mac.sh after shared executor helpers are initialized.

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

# Portable device/inode identity for macOS (BSD stat) and test hosts (GNU stat).
_file_identity() {
  stat -f '%d:%i' "$1" 2>/dev/null || stat -c '%d:%i' "$1" 2>/dev/null
}

# Return an identity bound to the artifact directory, its parent, and the exact
# manifest that authorizes this artifact type. Ancestor symlinks may remain
# inside HOME, but resolving outside HOME is always rejected.
_project_artifact_identity() {
  local path="$1"
  local requested_marker="${2:-}"
  [ -d "$path" ] && [ ! -L "$path" ] || return 1
  case "$path" in
    "$HOME"/*) ;;
    *) return 1 ;;
  esac
  case "$path" in
    "$HOME/Downloads"/*|*/../*|*/..) return 1 ;;
  esac

  local parent base physical_parent physical_home marker type_info artifact_name
  local artifact_id parent_id marker_id
  parent=$(dirname "$path")
  base=$(basename "$path")
  physical_parent=$(cd -P "$parent" 2>/dev/null && pwd -P) || return 1
  physical_home=$(cd -P "$HOME" 2>/dev/null && pwd -P) || return 1
  case "$physical_parent" in
    "$physical_home"/*) ;;
    *) return 1 ;;
  esac

  local IFS='|'
  for marker in $_PROJECT_MARKERS; do
    [ -z "$requested_marker" ] || [ "$marker" = "$requested_marker" ] || continue
    type_info=$(_artifact_type_for_marker "$marker")
    artifact_name="${type_info##* }"
    [ "$artifact_name" = "$base" ] || continue
    [ -f "$parent/$marker" ] && [ ! -L "$parent/$marker" ] || continue
    artifact_id=$(_file_identity "$path") || return 1
    parent_id=$(_file_identity "$parent") || return 1
    marker_id=$(_file_identity "$parent/$marker") || return 1
    printf '%s:%s:%s:%s\n' \
      "$artifact_id" "$parent_id" "$marker_id" \
      "$marker"
    return 0
  done
  return 1
}

# Discover artifacts; emits
# "<size>\t<type>\t<path>\t<identity>" lines. Paths containing delimiters used
# by the CLI transport are skipped rather than ambiguously reinterpreted.
_find_project_artifacts() {
  local root_rel root marker parent mbase type_info label artifact_name art_path s identity
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
      case "$art_path" in *','*|*$'\t'*|*$'\n'*) continue ;; esac
      identity=$(_project_artifact_identity "$art_path" "$mbase") || continue
      s=$(get_dir_size_bytes "$art_path") || s=0
      [ "$s" -ge "$_PROJECT_ARTIFACT_MIN_BYTES" ] 2>/dev/null || continue
      printf '%s\t%s\t%s\t%s\n' "$s" "$label" "$art_path" "$identity"
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
  local expected_identity="${2:-}"
  case "$path" in
    /*) ;; *) return 1 ;;
  esac
  case "$path" in */../*|*/..) return 1 ;; esac
  case "$path" in
    "$HOME"/*) ;; *) return 1 ;;
  esac
  local base; base=$(basename "$path")
  case "|$_PROJECT_ARTIFACT_NAMES|" in
    *"|$base|"*) ;; *) return 1 ;;
  esac
  _validate_removal_path "$path" contents "Artifact: $path" || return 1
  local actual_identity
  actual_identity=$(_project_artifact_identity "$path") || return 1
  [ -z "$expected_identity" ] || [ "$actual_identity" = "$expected_identity" ]
}

# Category scan_fn — sets this category's size from discovered artifacts.
scan_project_artifacts() {
  local total=0 s
  while IFS=$'\t' read -r s _ _; do
    [ -n "$s" ] && total=$((total + s))
  done < <(_get_project_artifacts)
  local i
  for i in "${!CAT_IDS[@]}"; do
    [ "${CAT_IDS[$i]}" = "project_artifacts" ] && { CAT_SIZES[i]=$total; break; }
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
    local parsed=() identities=()
    IFS=',' read -ra parsed <<< "$PROJECT_ARTIFACT_CLEAN"
    IFS=',' read -ra identities <<< "$PROJECT_ARTIFACT_IDENTITIES"
    local p expected_identity artifact_index=0
    for p in "${parsed[@]}"; do
      p="${p## }"; p="${p%% }"
      [ -z "$p" ] && continue
      expected_identity="${identities[$artifact_index]:-}"
      artifact_index=$((artifact_index + 1))
      if [ -n "$expected_identity" ] && \
         _is_valid_project_artifact "$p" "$expected_identity"; then
        safe_rm "$p" "Artifact: $p" "$expected_identity"
      else
        warn "$(L invalid_artifact): $p"
        record_clean_error "$(L invalid_artifact): missing or changed scan identity: $p"
      fi
    done
    return
  fi

  # Interactive CLI mode: list each artifact and confirm individually.
  local s label path identity sz_h
  while IFS=$'\t' read -r s label path identity; do
    [ -n "$path" ] || continue
    sz_h=$(format_bytes "$s")
    if confirm "$label · $(basename "$(dirname "$path")") · $sz_h — sil?"; then
      if _is_valid_project_artifact "$path" "$identity"; then
        safe_rm "$path" "Artifact: $path" "$identity"
      else
        warn "$(L invalid_artifact): $path"
      fi
    fi
  done < <(_get_project_artifacts)
}

scan_project_artifacts_subitems_json() {
  local first=true s label path identity sz_h esc_id esc_label esc_name proj_name orphaned mtime now days
  now=$(date +%s)
  while IFS=$'\t' read -r s label path identity; do
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
    echo -n "        {\"id\": \"$esc_id\", \"identity\": \"$identity\", \"name\": \"$esc_name\", \"type\": \"$esc_label\", \"path\": \"$esc_id\", \"size_bytes\": $s, \"size_human\": \"$sz_h\", \"days_since\": $days, \"is_orphaned\": $orphaned}"
  done < <(_get_project_artifacts)
}
