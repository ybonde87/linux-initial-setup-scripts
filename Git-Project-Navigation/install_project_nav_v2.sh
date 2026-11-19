#!/usr/bin/env bash
# install_project_nav_v2.sh
#
# Self-contained installer for the Project Navigator (v2).
# Run it on any WSL/Linux machine with zsh:
#
#   bash install_project_nav_v2.sh
#
# It:
#   1. Backs up an existing project_nav_v2.zsh
#   2. Writes the zsh script cleanly (no copy/paste corruption)
#   3. Checks its syntax with zsh, if zsh is available
#   4. Adds the source line to ~/.zshrc (idempotent)
#   5. Warns if an older project_nav version is still sourced
#
# The zsh script itself is embedded below between PROJNAV_EOF markers.

set -e

TARGET="$HOME/.config/zsh/project_nav_v2.zsh"
ZSHRC="$HOME/.zshrc"
SOURCE_LINE="source $TARGET"
STAMP="$(date +%s)"

mkdir -p "$(dirname "$TARGET")"

if [[ -f "$TARGET" ]]; then
  BACKUP="${TARGET}.bak.${STAMP}"
  cp "$TARGET" "$BACKUP"
  echo "Existing file backed up to: $BACKUP"
fi

cat > "$TARGET" << 'PROJNAV_EOF'
# ~/.config/zsh/project_nav_v2.zsh
#
# Hierarchical, context-aware, case-insensitive project navigation
# + auto git pull, bulk sync, auto-discovery, back-jump, backups,
# and clone-and-register with automatic shortcut derivation from the URL.
#
# Core:
#   proj group region sample-repo  -> jump, checkout main/master, pull
#   proj region sample-repo        -> context-aware (when inside group/)
#   proj -                         -> back to previous project
#   proj                           -> list all
#
# Clone + register:
#   proj-clone <url>                       -> clone into $PWD, auto shortcut
#   proj-clone <url> <key words...>        -> clone into $PWD, manual shortcut
#   proj-clone-into <folder> <url> [keys]  -> clone into <folder>
#   proj-url-key <url>                     -> preview the auto-derived shortcut
#
# Auto shortcut rule for a URL like
#   git@gitlab.com:group-org/platform/services/region/sample-repo.git
#   -> first path segment (client, with -org/-group/-grp stripped) = group
#   -> parent folder of the repo (region)                          = region
#   -> repo name                                                   = sample-repo
#   => proj group region sample-repo
#
# Maintenance:
#   proj-sync-all, proj-scan <folder>, proj-doctor, proj-add, proj-remove,
#   proj-edit, proj-restore, proj-reload, proj-context

PROJECT_DIRS_CONF="${PROJECT_DIRS_CONF:-$HOME/.config/zsh/project_dirs.conf}"
PROJECT_DIRS_BACKUP="${PROJECT_DIRS_CONF}.bak"

# Suffixes stripped from the first URL segment to get the client name.
typeset -ga PROJ_CLIENT_SUFFIXES
PROJ_CLIENT_SUFFIXES=(-org -group -grp)

mkdir -p "$(dirname "$PROJECT_DIRS_CONF")"
[[ -f "$PROJECT_DIRS_CONF" ]] || touch "$PROJECT_DIRS_CONF"

typeset -gA PROJECT_DIRS
typeset -g PROJ_CURR_KEY=""
typeset -g PROJ_PREV_KEY=""

# NOTE: never name a local variable "path" in zsh - it is tied to $PATH.
_proj_load_map() {
  PROJECT_DIRS=()
  local line key dir
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    key="${line%%|*}"
    dir="${line#*|}"
    key="${key:l}"
    PROJECT_DIRS[$key]="$dir"
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

_proj_print_pull_summary() {
  local old_rev="$1" new_rev="$2"
  if [[ -n "$old_rev" && -n "$new_rev" && "$old_rev" != "$new_rev" ]]; then
    echo "New commits pulled:"
    git log "$old_rev..$new_rev" --oneline
  else
    echo "No new commits. Already up to date."
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

  local old_rev new_rev

  if [[ -z "$default_branch" ]]; then
    echo "Warning: could not detect a main/master branch. Staying on '$current_branch'."
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
  old_rev="$(git rev-parse HEAD 2>/dev/null)"
  if ! git pull origin "$default_branch" 2>&1; then
    echo "Error: git pull failed. Possible causes: no network, auth/SSH key issue, or merge conflict."
    echo "Run 'git status' in $target to investigate."
    return 1
  fi
  new_rev="$(git rev-parse HEAD 2>/dev/null)"
  _proj_print_pull_summary "$old_rev" "$new_rev"
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
    local target_dir="${PROJECT_DIRS[$target_key]}"
    if [[ -z "$target_dir" ]]; then
      echo "Previous project '$target_key' is no longer registered."
      return 1
    fi
    echo "Jumping back to '$target_key'..."
    _proj_git_sync "$target_key" "$target_dir"
    [[ "$PWD" -ef "$target_dir" ]] && _proj_update_history "$target_key"
    return
  fi

  if [[ $# -eq 0 ]]; then
    echo "Registered projects:"
    for k in "${(@k)PROJECT_DIRS}"; do
      printf "  %-40s -> %s\n" "$k" "$PROJECT_DIRS[$k]"
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
        printf "  %-40s -> %s\n" "$m" "$PROJECT_DIRS[$m]"
      done
    fi
    if [[ ${#ctx_matches[@]} -gt 0 ]]; then
      echo "Multiple projects under context '$ctx_key':"
      for m in "${ctx_matches[@]}"; do
        printf "  %-40s -> %s\n" "$m" "$PROJECT_DIRS[$m]"
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
  local dir="${@[-1]}"
  local key="${(L)*:1:-1}"
  dir="${dir/#\~/$HOME}"

  if [[ ! -d "$dir" ]]; then
    echo "Warning: '$dir' does not exist yet. Adding the mapping anyway,"
    echo "but 'proj $key' will fail until the folder exists."
  fi

  if [[ -n "${PROJECT_DIRS[$key]}" ]]; then
    echo "Key '$key' already exists -> ${PROJECT_DIRS[$key]}. Overwrite? (y/n)"
    read -r ans
    [[ "$ans" != "y" ]] && return 1
    proj-remove "$key" >/dev/null
  fi

  echo "${key}|${dir}" >> "$PROJECT_DIRS_CONF"
  _proj_load_map
  echo "Added: '$key' -> $dir"
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
  local k dir

  echo "Checking ${#PROJECT_DIRS[@]} registered project(s)...\n"

  for k in "${(@k)PROJECT_DIRS}"; do
    dir="${PROJECT_DIRS[$k]}"
    if [[ ! -d "$dir" ]]; then
      printf "  [MISSING]  %-40s -> %s\n" "$k" "$dir"
      ((missing++))
    elif ! git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
      printf "  [NOT GIT]  %-40s -> %s\n" "$k" "$dir"
      ((notgit++))
    else
      printf "  [OK]       %-40s -> %s\n" "$k" "$dir"
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
  local k dir

  echo "Syncing ${#PROJECT_DIRS[@]} registered project(s)...\n"

  for k in "${(@k)PROJECT_DIRS}"; do
    dir="${PROJECT_DIRS[$k]}"
    echo "== $k =="
    if _proj_git_sync "$k" "$dir"; then
      ((ok++))
    else
      if [[ ! -d "$dir" ]]; then
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
  local git_dir repo_dir rel key

  while IFS= read -r -d '' git_dir; do
    repo_dir="${git_dir:h}"
    rel="${repo_dir#$base/}"
    [[ "$rel" == "$repo_dir" ]] && rel="${repo_dir:t}"
    key="${(L)${rel//\// }}"

    if [[ -n "${PROJECT_DIRS[$key]}" ]]; then
      echo "  [SKIP]  '$key' already registered -> ${PROJECT_DIRS[$key]}"
      ((skipped++))
      continue
    fi

    echo "${key}|${repo_dir}" >> "$PROJECT_DIRS_CONF"
    echo "  [ADDED] '$key' -> $repo_dir"
    ((added++))
  done < <(find "$base" -type d -name ".git" -print0 2>/dev/null)

  _proj_load_map
  echo "\nScan complete: $added added, $skipped skipped (already registered)."
}

# ---------------------------------------------------------------------------
# Clone + register
# ---------------------------------------------------------------------------

# Splits a git URL (scp-style ssh, ssh://, https://, http://) into path
# segments, returned in the array $reply. Strips trailing ".git" and "/".
_proj_url_segments() {
  local url="$1" p
  url="${url%/}"
  url="${url%.git}"

  if [[ "$url" == *://* ]]; then
    p="${url#*://}"
    p="${p#*/}"
  elif [[ "$url" == *:* ]]; then
    p="${url#*:}"
  else
    return 1
  fi

  p="${p#/}"
  reply=("${(@s:/:)p}")
  reply=(${reply:#})
  [[ ${#reply[@]} -gt 0 ]]
}

# Derives "client parent repo" from a URL, lowercased.
#   group-org/.../region/sample-repo  ->  group region sample-repo
#   group/repo                       ->  group repo
#   repo                             ->  repo
_proj_key_from_url() {
  _proj_url_segments "$1" || return 1
  local -a segs
  segs=("${reply[@]}")
  local n=${#segs[@]}
  local repo="${segs[-1]}"

  if [[ $n -eq 1 ]]; then
    echo "${repo:l}"
    return 0
  fi

  local client="${segs[1]}"
  local s
  for s in "${PROJ_CLIENT_SUFFIXES[@]}"; do
    if [[ "$client" == *"$s" ]]; then
      client="${client%$s}"
      break
    fi
  done

  if [[ $n -eq 2 ]]; then
    echo "${client:l} ${repo:l}"
  else
    local parent="${segs[-2]}"
    echo "${client:l} ${parent:l} ${repo:l}"
  fi
}

# Preview the shortcut a URL would get.
proj-url-key() {
  if [[ $# -ne 1 ]]; then
    echo "Usage: proj-url-key <git-url>"
    return 1
  fi
  local key
  key="$(_proj_key_from_url "$1")"
  if [[ -z "$key" ]]; then
    echo "Error: could not parse URL: $1"
    return 1
  fi
  echo "proj $key"
}

# Shared worker: _proj_clone_core <target-dir> <url> [key words...]
_proj_clone_core() {
  local target_dir="$1" url="$2"
  shift 2

  # Tolerate a leading literal "proj" in the key words.
  [[ "$1" == "proj" ]] && shift

  local key
  if [[ $# -gt 0 ]]; then
    key="${(L)*}"
  else
    key="$(_proj_key_from_url "$url")"
  fi

  if [[ -z "$key" ]]; then
    echo "Error: could not derive a shortcut from URL: $url"
    echo "Pass one explicitly: proj-clone <url> <key words...>"
    return 1
  fi

  if [[ -n "${PROJECT_DIRS[$key]}" ]]; then
    echo "Error: shortcut '$key' already exists -> ${PROJECT_DIRS[$key]}"
    echo "Nothing cloned. Use a different shortcut: proj-clone <url> <key words...>"
    return 1
  fi

  local repo_name="${url%/}"
  repo_name="${repo_name%.git}"
  repo_name="${repo_name:t}"
  repo_name="${repo_name##*:}"

  if [[ -z "$repo_name" ]]; then
    echo "Error: could not determine repo name from URL: $url"
    return 1
  fi

  local target="$target_dir/$repo_name"
  if [[ -e "$target" ]]; then
    echo "Error: already exists: $target"
    echo "Register it instead: proj-add $key $target"
    return 1
  fi

  echo "Cloning $url"
  echo "     -> $target"
  if ! git clone "$url" "$target" 2>&1; then
    echo "Error: git clone failed. Check the URL, your SSH key/auth, or network access."
    return 1
  fi

  echo "${key}|${target}" >> "$PROJECT_DIRS_CONF"
  _proj_load_map
  echo "Added shortcut: proj $key"
}

# proj-clone <url> [key words...]  -> clones into the current directory
proj-clone() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: proj-clone <url> [key words...]"
    echo "  Auto shortcut : proj-clone git@gitlab.com:group-org/platform/services/region/sample-repo.git"
    echo "  Manual shortcut: proj-clone <url> group region sample-repo"
    return 1
  fi
  local url="$1"
  shift
  _proj_clone_core "$PWD" "$url" "$@"
}

# proj-clone-into <folder> <url> [key words...]
proj-clone-into() {
  if [[ $# -lt 2 ]]; then
    echo "Usage: proj-clone-into <target-folder> <url> [key words...]"
    return 1
  fi
  local target_dir="${1/#\~/$HOME}"
  target_dir="${target_dir:A}"
  local url="$2"
  shift 2

  if [[ ! -d "$target_dir" ]]; then
    echo "Error: target folder does not exist: $target_dir"
    echo "Create it first: mkdir -p $target_dir"
    return 1
  fi
  _proj_clone_core "$target_dir" "$url" "$@"
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

# Remove Windows CRLF line endings, just in case.
sed -i 's/\r$//' "$TARGET"

# Syntax check with zsh, if available.
if command -v zsh >/dev/null 2>&1; then
  if zsh -n "$TARGET"; then
    echo "Syntax check: OK"
  else
    echo "Syntax check: FAILED - do not source this file until fixed."
    exit 1
  fi
else
  echo "zsh not found in PATH; skipped syntax check."
fi

touch "$ZSHRC"

# Add the source line only if it is not already present.
if grep -qF "$SOURCE_LINE" "$ZSHRC"; then
  echo ".zshrc already sources: $SOURCE_LINE"
else
  printf '\n# Project navigator (v2)\n%s\n' "$SOURCE_LINE" >> "$ZSHRC"
  echo "Added to .zshrc: $SOURCE_LINE"
fi

# Warn about older project_nav versions that would be sourced too.
if grep -nE '^[[:space:]]*source[[:space:]]+.*project_nav(\.zsh|_final_v1\.zsh)' "$ZSHRC"; then
  echo "WARNING: the line(s) above load an older version."
  echo "Comment them out in $ZSHRC so only project_nav_v2.zsh is loaded."
fi

echo "Installed: $TARGET"
echo "Now run: exec zsh"
echo "Then test: proj-url-key git@gitlab.com:group-org/platform/services/region/sample-repo.git"

touch "$ZSHRC"

# Replace the old conditional project_nav source line, if present.
OLD_SOURCE='[[ -f ~/.config/zsh/project_nav.zsh ]] && source ~/.config/zsh/project_nav.zsh'
OLD_SOURCE_ESCAPED='source ~/.config/zsh/project_nav.zsh'

if grep -qF "$OLD_SOURCE" "$ZSHRC"; then
  cp "$ZSHRC" "${ZSHRC}.bak.${STAMP}"
  sed -i "s|${OLD_SOURCE}|${SOURCE_LINE}|" "$ZSHRC"
  echo "Replaced old project_nav source line in $ZSHRC"
  echo "Backup saved to: ${ZSHRC}.bak.${STAMP}"
elif grep -qF "$OLD_SOURCE_ESCAPED" "$ZSHRC"; then
  cp "$ZSHRC" "${ZSHRC}.bak.${STAMP}"
  sed -i "s|${OLD_SOURCE_ESCAPED}|${SOURCE_LINE}|" "$ZSHRC"
  echo "Replaced old project_nav source line in $ZSHRC"
  echo "Backup saved to: ${ZSHRC}.bak.${STAMP}"
fi

# Add the v2 source line only if it is not already present.
if grep -qF "$SOURCE_LINE" "$ZSHRC"; then
  echo ".zshrc already sources: $SOURCE_LINE"
else
  printf '\n# Project navigator (v2)\n%s\n' "$SOURCE_LINE" >> "$ZSHRC"
  echo "Added to .zshrc: $SOURCE_LINE"
fi

# Warn if any other old project_nav version is still sourced.
if grep -nE '^[[:space:]]*(\[\[ -f .*project_nav(\.zsh|_final_v1\.zsh).*\]\][[:space:]]*&&[[:space:]]*)?source[[:space:]]+.*project_nav(\.zsh|_final_v1\.zsh)' "$ZSHRC"; then
  echo "WARNING: the line(s) above load an older project_nav version."
  echo "Comment them out in $ZSHRC so only project_nav_v2.zsh is loaded."
fi