#!/usr/bin/env bash
# Installer for project_nav.zsh — writes the file cleanly via heredoc
# to avoid clipboard/editor corruption issues seen with manual paste.
#
# Usage:
#   bash install_project_nav.sh

set -e
TARGET="$HOME/.config/zsh/project_nav.zsh"
mkdir -p "$HOME/.config/zsh"

if [[ -f "$TARGET" ]]; then
  cp "$TARGET" "${TARGET}.broken.$(date +%s)"
  echo "Existing (possibly broken) file backed up to ${TARGET}.broken.<timestamp>"
fi

cat > "$TARGET" << 'PROJNAV_EOF'
# ~/.config/zsh/project_nav.zsh
#
# Hierarchical, context-aware, case-insensitive project navigation
# + auto git pull for zsh, with error handling, bulk sync, auto-discovery,
# back-jump history, post-pull change summaries, and config backups.
#
# Core usage:
#   proj acme emea tgw     -> exact match (any case, works from anywhere)
#   proj emea tgw          -> context-aware shortcut if already inside acme/
#   proj acme              -> lists all repos under acme
#   proj                   -> lists every registered project key
#   proj -                 -> jump back to the previously visited project
#
# Bulk / maintenance:
#   proj-sync-all           -> pull latest on every registered repo
#   proj-scan <base-folder> -> auto-discover & register all git repos under a folder
#   proj-doctor             -> audit all mappings for missing/broken repos
#   proj-restore            -> restore project_dirs.conf from its last backup
#
#   proj-add Acme EMEA TGW ~/projects/work/Acme/EMEA/TGW-repo
#   proj-remove acme emea tgw
#   proj-edit / proj-reload

PROJECT_DIRS_CONF="${PROJECT_DIRS_CONF:-$HOME/.config/zsh/project_dirs.conf}"
PROJECT_DIRS_BACKUP="${PROJECT_DIRS_CONF}.bak"

mkdir -p "$(dirname "$PROJECT_DIRS_CONF")"
[[ -f "$PROJECT_DIRS_CONF" ]] || touch "$PROJECT_DIRS_CONF"

typeset -gA PROJECT_DIRS
typeset -g PROJ_CURR_KEY=""
typeset -g PROJ_PREV_KEY=""

_proj_load_map() {
  PROJECT_DIRS=()
  local line key path
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    key="${line%%|*}"
    path="${line#*|}"
    key="${key:l}"
    PROJECT_DIRS[$key]="$path"
  done < "$PROJECT_DIRS_CONF"
}

_proj_load_map

_proj_backup_conf() {
  cp "$PROJECT_DIRS_CONF" "$PROJECT_DIRS_BACKUP" 2>/dev/null
}

_proj_update_history() {
  local key="$1"
  if [[ "$key" != "$PROJ_CURR_KEY" ]]; then
    PROJ_PREV_KEY="$PROJ_CURR_KEY"
    PROJ_CURR_KEY="$key"
  fi
}

_proj_git_sync() {
  local key="$1"
  local target="$2"

  if [[ -z "$target" ]]; then
    echo "Error: no path recorded for '$key'."
    return 1
  fi

  if [[ ! -d "$target" ]]; then
    echo "Error: folder for '$key' does not exist:"
    echo "  $target"
    echo "It may have been deleted, moved, or renamed. Fix the mapping with:"
    echo "  proj-remove $key"
    echo "  proj-add $key <new-path>"
    echo "or edit directly: proj-edit"
    return 1
  fi

  if [[ ! -r "$target" || ! -x "$target" ]]; then
    echo "Error: no permission to access folder for '$key':"
    echo "  $target"
    return 1
  fi

  if ! cd "$target" 2>/dev/null; then
    echo "Error: failed to cd into '$target' (unknown reason)."
    return 1
  fi

  if ! command -v git &>/dev/null; then
    echo "Warning: git is not installed or not in PATH. Skipping sync."
    return 0
  fi

  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Note: '$target' is not a git repository. Just cd'd there, no sync performed."
    return 0
  fi

  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [[ -z "$current_branch" ]]; then
    echo "Warning: could not determine current branch (detached HEAD or corrupted repo?)."
    return 1
  fi

  local default_branch=""
  if git show-ref --verify --quiet refs/heads/main; then
    default_branch="main"
  elif git show-ref --verify --quiet refs/heads/master; then
    default_branch="master"
  elif git show-ref --verify --quiet refs/remotes/origin/main; then
    default_branch="main"
  elif git show-ref --verify --quiet refs/remotes/origin/master; then
    default_branch="master"
  fi

  if [[ -z "$default_branch" ]]; then
    echo "Warning: could not detect a main/master branch. Staying on '$current_branch'."
    local old_rev new_rev
    old_rev="$(git rev-parse HEAD 2>/dev/null)"
    if ! git pull 2>&1; then
      echo "Error: git pull failed on '$current_branch'. Check network access or upstream config."
      return 1
    fi
    new_rev="$(git rev-parse HEAD 2>/dev/null)"
    _proj_print_pull_summary "$old_rev" "$new_rev"
    return 0
  fi

  if [[ "$current_branch" != "$default_branch" ]]; then
    echo "Switching '$current_branch' -> '$default_branch'..."
    if ! git checkout "$default_branch" 2>&1; then
      echo "Error: git checkout '$default_branch' failed. You likely have uncommitted changes."
      echo "Commit or stash them, then re-run: proj $key"
      return 1
    fi
  fi

  echo "Pulling latest '$default_branch' in $target ..."
  local old_rev new_rev
  old_rev="$(git rev-parse HEAD 2>/dev/null)"
  if ! git pull origin "$default_branch" 2>&1; then
    echo "Error: git pull failed. Possible causes: no network, auth/SSH key issue, or merge conflict."
    echo "Run 'git status' in $target to investigate."
    return 1
  fi
  new_rev="$(git rev-parse HEAD 2>/dev/null)"
  _proj_print_pull_summary "$old_rev" "$new_rev"
}

_proj_print_pull_summary() {
  local old_rev="$1" new_rev="$2"
  if [[ -n "$old_rev" && -n "$new_rev" && "$old_rev" != "$new_rev" ]]; then
    echo "New commits pulled:"
    git log "$old_rev..$new_rev" --oneline
  else
    echo "No new commits. Already up to date."
  fi
}

_proj_detect_context() {
  local -a clients
  local k
  for k in "${(@k)PROJECT_DIRS}"; do
    clients+=("${k%% *}")
  done
  clients=(${(u)clients})

  local pwd_lower="${PWD:l}"
  local c
  for c in "${clients[@]}"; do
    if [[ "$pwd_lower" == *"/$c/"* || "$pwd_lower" == *"/$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

_proj_list_matches() {
  local prefix="$1"
  local -a matches
  local k
  for k in "${(@k)PROJECT_DIRS}"; do
    if [[ "$k" == "$prefix "* ]]; then
      matches+=("$k")
    fi
  done
  printf '%s\n' "${matches[@]}"
}

proj() {
  if [[ ${#PROJECT_DIRS[@]} -eq 0 && "$1" != "-" ]]; then
    echo "No projects registered yet. Add one with: proj-add <key words> <path>"
    return 0
  fi

  if [[ "$1" == "-" && $# -eq 1 ]]; then
    if [[ -z "$PROJ_PREV_KEY" ]]; then
      echo "No previous project to jump back to."
      return 1
    fi
    local target_key="$PROJ_PREV_KEY"
    local target_path="${PROJECT_DIRS[$target_key]}"
    if [[ -z "$target_path" ]]; then
      echo "Previous project '$target_key' is no longer registered."
      return 1
    fi
    echo "Jumping back to '$target_key'..."
    _proj_git_sync "$target_key" "$target_path"
    [[ "$PWD" -ef "$target_path" ]] && _proj_update_history "$target_key"
    return
  fi

  if [[ $# -eq 0 ]]; then
    echo "Registered projects:"
    for k in "${(@k)PROJECT_DIRS}"; do
      printf "  %-30s -> %s\n" "$k" "$PROJECT_DIRS[$k]"
    done
    return 0
  fi

  local raw_key="${(L)*}"

  if [[ -n "${PROJECT_DIRS[$raw_key]}" ]]; then
    _proj_git_sync "$raw_key" "${PROJECT_DIRS[$raw_key]}"
    [[ "$PWD" -ef "${PROJECT_DIRS[$raw_key]}" ]] && _proj_update_history "$raw_key"
    return
  fi

  local context
  context="$(_proj_detect_context)"
  local ctx_key=""
  if [[ -n "$context" ]]; then
    ctx_key="$context $raw_key"
    if [[ -n "${PROJECT_DIRS[$ctx_key]}" ]]; then
      echo "(context: $context) resolved '$raw_key' -> '$ctx_key'"
      _proj_git_sync "$ctx_key" "${PROJECT_DIRS[$ctx_key]}"
      [[ "$PWD" -ef "${PROJECT_DIRS[$ctx_key]}" ]] && _proj_update_history "$ctx_key"
      return
    fi
  fi

  local -a raw_matches
  raw_matches=("${(@f)$(_proj_list_matches "$raw_key")}")
  raw_matches=(${raw_matches:#})

  local -a ctx_matches
  if [[ -n "$context" ]]; then
    ctx_matches=("${(@f)$(_proj_list_matches "$ctx_key")}")
    ctx_matches=(${ctx_matches:#})
  fi

  if [[ ${#raw_matches[@]} -eq 1 && ${#ctx_matches[@]} -eq 0 ]]; then
    echo "Only one match under '$raw_key' -> ${raw_matches[1]}"
    _proj_git_sync "${raw_matches[1]}" "${PROJECT_DIRS[${raw_matches[1]}]}"
    [[ "$PWD" -ef "${PROJECT_DIRS[${raw_matches[1]}]}" ]] && _proj_update_history "${raw_matches[1]}"
  elif [[ ${#ctx_matches[@]} -eq 1 && ${#raw_matches[@]} -eq 0 ]]; then
    echo "(context: $context) only one match -> ${ctx_matches[1]}"
    _proj_git_sync "${ctx_matches[1]}" "${PROJECT_DIRS[${ctx_matches[1]}]}"
    [[ "$PWD" -ef "${PROJECT_DIRS[${ctx_matches[1]}]}" ]] && _proj_update_history "${ctx_matches[1]}"
  elif [[ ${#raw_matches[@]} -gt 0 || ${#ctx_matches[@]} -gt 0 ]]; then
    if [[ ${#raw_matches[@]} -gt 0 ]]; then
      echo "Multiple projects under '$raw_key':"
      for m in "${raw_matches[@]}"; do
        printf "  %-30s -> %s\n" "$m" "$PROJECT_DIRS[$m]"
      done
    fi
    if [[ ${#ctx_matches[@]} -gt 0 ]]; then
      echo "Multiple projects under context '$ctx_key':"
      for m in "${ctx_matches[@]}"; do
        printf "  %-30s -> %s\n" "$m" "$PROJECT_DIRS[$m]"
      done
    fi
  else
    echo "No project found for: '$raw_key'"
    [[ -n "$context" ]] && echo "(also tried context-prefixed key: '$ctx_key')"
  fi
}

proj-add() {
  if [[ $# -lt 2 ]]; then
    echo "Usage: proj-add <key words...> <path>"
    echo "Example: proj-add Acme EMEA TGW ~/projects/work/Acme/EMEA/TGW-repo"
    return 1
  fi
  local path="${@[-1]}"
  local key="${(L)*:1:-1}"
  path="${path/#\~/$HOME}"

  if [[ ! -d "$path" ]]; then
    echo "Warning: '$path' does not exist yet. Adding the mapping anyway,"
    echo "but 'proj $key' will fail until the folder exists."
  fi

  if [[ -n "${PROJECT_DIRS[$key]}" ]]; then
    echo "Key '$key' already exists -> ${PROJECT_DIRS[$key]}. Overwrite? (y/n)"
    read -r ans
    [[ "$ans" != "y" ]] && return 1
    proj-remove "$key" >/dev/null
  fi

  echo "${key}|${path}" >> "$PROJECT_DIRS_CONF"
  _proj_load_map
  echo "Added: '$key' -> $path"
}

proj-remove() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: proj-remove <key words...>"
    return 1
  fi
  local key="${(L)*}"
  if [[ -z "${PROJECT_DIRS[$key]}" ]]; then
    echo "No such exact key: '$key'"
    return 1
  fi
  _proj_backup_conf
  grep -vF "${key}|" "$PROJECT_DIRS_CONF" > "${PROJECT_DIRS_CONF}.tmp" && mv "${PROJECT_DIRS_CONF}.tmp" "$PROJECT_DIRS_CONF"
  _proj_load_map
  echo "Removed: '$key' (backup saved to $PROJECT_DIRS_BACKUP)"
}

proj-edit() {
  _proj_backup_conf
  "${EDITOR:-vim}" "$PROJECT_DIRS_CONF"
  _proj_load_map
  echo "(backup saved to $PROJECT_DIRS_BACKUP before edit)"
}

proj-restore() {
  if [[ ! -f "$PROJECT_DIRS_BACKUP" ]]; then
    echo "No backup found at $PROJECT_DIRS_BACKUP"
    return 1
  fi
  cp "$PROJECT_DIRS_CONF" "${PROJECT_DIRS_CONF}.pre-restore" 2>/dev/null
  cp "$PROJECT_DIRS_BACKUP" "$PROJECT_DIRS_CONF"
  _proj_load_map
  echo "Restored from $PROJECT_DIRS_BACKUP"
  echo "(your pre-restore state was saved to ${PROJECT_DIRS_CONF}.pre-restore)"
}

proj-reload() {
  _proj_load_map
  echo "Reloaded ${#PROJECT_DIRS[@]} project mapping(s)."
}

proj-context() {
  local ctx
  ctx="$(_proj_detect_context)"
  if [[ -n "$ctx" ]]; then
    echo "Detected context: $ctx"
  else
    echo "No known client context detected for: $PWD"
  fi
}

proj-doctor() {
  if [[ ${#PROJECT_DIRS[@]} -eq 0 ]]; then
    echo "No projects registered yet."
    return 0
  fi

  local ok=0 missing=0 notgit=0
  local k path

  echo "Checking ${#PROJECT_DIRS[@]} registered project(s)...\n"

  for k in "${(@k)PROJECT_DIRS}"; do
    path="${PROJECT_DIRS[$k]}"
    if [[ ! -d "$path" ]]; then
      printf "  [MISSING]  %-25s -> %s\n" "$k" "$path"
      ((missing++))
    elif ! git -C "$path" rev-parse --is-inside-work-tree &>/dev/null; then
      printf "  [NOT GIT]  %-25s -> %s\n" "$k" "$path"
      ((notgit++))
    else
      printf "  [OK]       %-25s -> %s\n" "$k" "$path"
      ((ok++))
    fi
  done

  echo "\nSummary: $ok OK, $missing missing, $notgit not-a-git-repo."
  if [[ $missing -gt 0 ]]; then
    echo "Fix missing ones with: proj-remove <key>  followed by  proj-add <key> <new-path>"
  fi
}

proj-sync-all() {
  if [[ ${#PROJECT_DIRS[@]} -eq 0 ]]; then
    echo "No projects registered yet."
    return 0
  fi

  local start_dir="$PWD"
  local ok=0 fail=0 skip=0
  local k path

  echo "Syncing ${#PROJECT_DIRS[@]} registered project(s)...\n"

  for k in "${(@k)PROJECT_DIRS}"; do
    path="${PROJECT_DIRS[$k]}"
    echo "== $k =="
    if _proj_git_sync "$k" "$path"; then
      ((ok++))
    else
      if [[ ! -d "$path" ]]; then
        ((skip++))
      else
        ((fail++))
      fi
    fi
    echo
  done

  cd "$start_dir" 2>/dev/null
  echo "Sync summary: $ok OK, $fail failed, $skip skipped (missing folder)."
}

proj-scan() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: proj-scan <base-folder>"
    echo "Example: proj-scan ~/projects/work"
    return 1
  fi

  local base="${1/#\~/$HOME}"
  base="${base:A}"

  if [[ ! -d "$base" ]]; then
    echo "Error: '$base' is not a directory."
    return 1
  fi

  echo "Scanning '$base' for git repositories...\n"

  local added=0 skipped=0
  local git_dir repo_path rel key

  while IFS= read -r -d '' git_dir; do
    repo_path="${git_dir:h}"
    rel="${repo_path#$base/}"
    [[ "$rel" == "$repo_path" ]] && rel="${repo_path:t}"
    key="${(L)${rel//\// }}"

    if [[ -n "${PROJECT_DIRS[$key]}" ]]; then
      echo "  [SKIP]  '$key' already registered -> ${PROJECT_DIRS[$key]}"
      ((skipped++))
      continue
    fi

    echo "${key}|${repo_path}" >> "$PROJECT_DIRS_CONF"
    echo "  [ADDED] '$key' -> $repo_path"
    ((added++))
  done < <(find "$base" -type d -name ".git" -print0 2>/dev/null)

  _proj_load_map
  echo "\nScan complete: $added added, $skipped skipped (already registered)."
}

_proj_complete() {
  local -a typed
  typed=("${(L)words[2,-2]}")
  local prefix="${(j: :)typed}"

  local context=""
  [[ -z "$prefix" ]] && context="$(_proj_detect_context)"

  local -a next_tokens
  local k remainder token

  for k in "${(@k)PROJECT_DIRS}"; do
    if [[ -z "$prefix" ]]; then
      remainder="$k"
    elif [[ "$k" == "$prefix "* ]]; then
      remainder="${k#$prefix }"
    elif [[ -n "$context" && "$k" == "$context $prefix "* ]]; then
      remainder="${k#$context $prefix }"
    elif [[ -n "$context" && "$k" == "$context $prefix" ]]; then
      continue
    elif [[ "$k" == "$prefix" ]]; then
      continue
    else
      continue
    fi
    token="${remainder%% *}"
    next_tokens+=("$token")
  done

  next_tokens=(${(u)next_tokens})
  _describe 'project' next_tokens
}
compdef _proj_complete proj
compdef _proj_complete proj-remove
PROJNAV_EOF

echo "Installed clean project_nav.zsh to $TARGET"
echo "Now run: exec zsh"
