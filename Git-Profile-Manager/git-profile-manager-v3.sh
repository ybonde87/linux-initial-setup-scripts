#!/usr/bin/env bash
# Git Profile Manager — Bash / WSL / Linux
#
# State lives beside this script in .gitprofile_manager/.
# Existing shell-escaped profile .conf files remain compatible.
# Do not place untrusted files in the database or backup directories.
#
# Deliberately avoids "set -e": expected menu cancellations and SSH
# failures are handled explicitly instead of terminating the application.

set -uo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" ||
    exit 1

APP_DIR="$SCRIPT_DIR/.gitprofile_manager"
DB_DIR="$APP_DIR/db"
BACKUP_DIR="$APP_DIR/backups"
OUTPUT_DIR="$APP_DIR/outputs"
LOG_DIR="$APP_DIR/logs"
ERRORS_DIR="$APP_DIR/errors"
SSH_DIR="$HOME/.ssh"

RUN_ID="$(date +%Y%m%d_%H%M%S)_$$"
RUN_LOG="$LOG_DIR/run_$RUN_ID.log"
SUCCESS_LOG="$LOG_DIR/success_$RUN_ID.log"
ERROR_LOG="$ERRORS_DIR/error_$RUN_ID.log"

FIRST_RUN=0
[[ -d "$DB_DIR" ]] || FIRST_RUN=1

mkdir -p "$DB_DIR" "$BACKUP_DIR" "$OUTPUT_DIR" \
    "$LOG_DIR" "$ERRORS_DIR" || exit 1

chmod 700 "$APP_DIR" "$DB_DIR" "$BACKUP_DIR" \
    "$OUTPUT_DIR" "$LOG_DIR" "$ERRORS_DIR"

if [[ -t 1 ]]; then
    RED=$'\033[1;31m'
    YELLOW=$'\033[1;33m'
    GREEN=$'\033[1;32m'
    CYAN=$'\033[1;36m'
    RESET=$'\033[0m'
else
    RED='' YELLOW='' GREEN='' CYAN='' RESET=''
fi

REPLY_VALUE=''
declare -a PROFILES=()
declare -A P=()

line() {
    printf '%s\n' \
        '========================================================================'
}

info() { printf '%s%s%s\n' "$CYAN" "$*" "$RESET"; }
warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$RESET"; }

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$RUN_LOG"
}

ok() {
    printf '%s%s%s\n' "$GREEN" "$*" "$RESET"
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$SUCCESS_LOG"
    log "SUCCESS: $*"
}

fail() {
    printf '%s%s%s\n' "$RED" "$*" "$RESET" >&2
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$ERROR_LOG"
    log "ERROR: $*"
    return 1
}

finish() {
    log "Application exited."
    printf '\nGoodbye. Logs: %s\n' "$LOG_DIR"
    exit 0
}

trap 'printf "\nInterrupted.\n"; exit 130' INT
trap 'exit 143' TERM

for command in git ssh ssh-keygen realpath flock stat find sort; do
    command -v "$command" >/dev/null 2>&1 || {
        fail "Missing required command: $command"
        exit 1
    }
done

# Prevent two instances changing the same database simultaneously.
exec 9>"$APP_DIR/.lock"
flock -n 9 || {
    fail "Another instance is already running."
    exit 1
}

# Reserved navigation tokens use ":" so names such as "b" and "x"
# remain usable as ordinary values.
ask() {
    local answer
    while true; do
        if ! read -r -p "$1 [:b=back, :x=exit]: " answer; then
            finish
        fi
        case "$answer" in
            :b|:back) return 10 ;;
            :x|:exit)
                read -r -p "Exit now? [y/N]: " answer || finish
                [[ "${answer,,}" == y ]] && finish
                ;;
            *)
                REPLY_VALUE="$answer"
                return 0
                ;;
        esac
    done
}

yes() {
    ask "$1 [y/N]" || return 1
    [[ "${REPLY_VALUE,,}" == y ||
       "${REPLY_VALUE,,}" == yes ]]
}

pause() {
    ask "Press Enter to continue" || true
    return 0
}

valid_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

path_value() {
    local path="$1"
    [[ "$path" == "~" ]] && path="$HOME"
    [[ "$path" == "~/"* ]] && path="$HOME/${path:2}"

    [[ -n "$path" && "$path" != *$'\n'* &&
       "$path" != *$'\r'* ]] || return 1

    realpath -m -- "$path"
}

profile_file() { printf '%s/%s.conf\n' "$DB_DIR" "$1"; }
config_file() { printf '%s/.gitconfig-%s\n' "$HOME" "$1"; }

refresh_profiles() {
    local file
    PROFILES=()
    shopt -s nullglob
    for file in "$DB_DIR"/*.conf; do
        PROFILES+=("$(basename "${file%.conf}")")
    done
    shopt -u nullglob
}

load_profile() {
    local file
    file="$(profile_file "$1")"

    [[ -f "$file" && ! -L "$file" && -O "$file" ]] ||
        { fail "Unsafe or missing profile file: $file"; return 1; }

    # Compatibility with the previous script's printf %q database.
    # These files contain executable Bash: only trust your own database.
    local PROFILE_NAME='' PROJECT_DIR='' KEY_PATH=''
    local GIT_NAME='' GIT_EMAIL='' GITLAB_HOST=''
    local CREATED_AT='' UPDATED_AT=''

    source "$file" || return 1

    [[ "$PROFILE_NAME" == "$1" &&
       -n "$PROJECT_DIR" && -n "$KEY_PATH" ]] ||
        { fail "Invalid profile record: $file"; return 1; }

    P=(
        [PROFILE_NAME]="$PROFILE_NAME"
        [PROJECT_DIR]="$PROJECT_DIR"
        [KEY_PATH]="$KEY_PATH"
        [GIT_NAME]="$GIT_NAME"
        [GIT_EMAIL]="$GIT_EMAIL"
        [GITLAB_HOST]="${GITLAB_HOST:-gitlab.com}"
        [CREATED_AT]="${CREATED_AT:-$(date -Is)}"
        [UPDATED_AT]="$UPDATED_AT"
    )
}

save_profile() {
    local tmp key
    tmp="$(mktemp "$DB_DIR/.profile.XXXXXX")" || return 1
    P[UPDATED_AT]="$(date -Is)"

    for key in PROFILE_NAME PROJECT_DIR KEY_PATH GIT_NAME \
        GIT_EMAIL GITLAB_HOST CREATED_AT UPDATED_AT; do
        printf '%s=%q\n' "$key" "${P[$key]}" >> "$tmp" ||
            { rm -f -- "$tmp"; return 1; }
    done

    mv -- "$tmp" "$(profile_file "${P[PROFILE_NAME]}")"
}

show_profile() {
    local key
    line
    for key in PROFILE_NAME PROJECT_DIR KEY_PATH \
        GITLAB_HOST GIT_NAME GIT_EMAIL; do
        printf '%-16s %s\n' "$key:" "${P[$key]}"
    done
    line
}

choose_profile() {
    local i
    refresh_profiles
    ((${#PROFILES[@]})) || {
        warn "No saved profiles. Add one first."
        return 1
    }

    for i in "${!PROFILES[@]}"; do
        printf '[%d] %s\n' "$((i + 1))" "${PROFILES[$i]}"
    done

    ask "Select profile number" || return 1
    [[ "$REPLY_VALUE" =~ ^[1-9][0-9]{0,5}$ ]] || return 1
    i=$((10#$REPLY_VALUE - 1))
    ((i < ${#PROFILES[@]})) || return 1
    load_profile "${PROFILES[$i]}"
}

# Print profiles referencing the same canonical key path.
key_users() (
    local target="$1" exclude="${2:-}" name candidate
    refresh_profiles
    for name in "${PROFILES[@]}"; do
        [[ "$name" == "$exclude" ]] && continue
        load_profile "$name" || continue
        candidate="$(path_value "${P[KEY_PATH]}")" || continue
        [[ "$candidate" == "$target" ]] && printf '%s\n' "$name"
    done
)

snapshot() {
    local reason="$1" destination name cfg
    destination="$(mktemp -d \
        "$BACKUP_DIR/$(date +%Y%m%d_%H%M%S)_${reason}_XXXXXX")" ||
        return 1

    mkdir -p "$destination/db" "$destination/configs" || return 1

    if [[ -f "$HOME/.gitconfig" ]]; then
        cp -p -- "$HOME/.gitconfig" "$destination/gitconfig" ||
            return 1
    else
        touch "$destination/global-absent"
    fi

    refresh_profiles
    for name in "${PROFILES[@]}"; do
        cp -p -- "$(profile_file "$name")" "$destination/db/" ||
            return 1
        cfg="$(config_file "$name")"
        if [[ -f "$cfg" ]]; then
            cp -p -- "$cfg" "$destination/configs/" || return 1
        fi
    done

    printf 'Created: %s\nReason: %s\n' "$(date -Is)" "$reason" \
        > "$destination/manifest.txt"
    log "Snapshot: $destination"
    LAST_SNAPSHOT="$destination"
}

remove_include() {
    local directory="$1" target="$2" value rc
    local key="includeIf.gitdir:${directory%/}/.path"
    local -a retained=()

    # Preserve other includes attached to the same directory condition.
    while IFS= read -r value; do
        [[ "$value" == "$target" ]] || retained+=("$value")
    done < <(git config --global --get-all "$key" 2>/dev/null)

    git config --global --unset-all "$key" 2>/dev/null
    rc=$?
    [[ "$rc" == 0 || "$rc" == 5 ]] || return 1

    for value in "${retained[@]}"; do
        git config --global --add "$key" "$value" || return 1
    done
    return 0
}

# SSH commands pass through a shell; quote paths accordingly.
shell_quote() {
    local value="${1//\'/\'\\\'\'}"
    printf "'%s'" "$value"
}

write_profile_config() {
    local cfg tmp command
    cfg="$(config_file "${P[PROFILE_NAME]}")"
    [[ ! -L "$cfg" ]] || {
        fail "Refusing to overwrite a symlink: $cfg"
        return 1
    }

    tmp="$(mktemp "$HOME/.gpm-config.XXXXXX")" || return 1
    [[ ! -f "$cfg" ]] || cp -p -- "$cfg" "$tmp" ||
        { rm -f "$tmp"; return 1; }

    command="ssh -o IdentitiesOnly=yes -i $(shell_quote "${P[KEY_PATH]}")"

    git config --file "$tmp" user.name "${P[GIT_NAME]}" &&
    git config --file "$tmp" user.email "${P[GIT_EMAIL]}" &&
    git config --file "$tmp" core.sshCommand "$command" &&
    chmod 600 "$tmp" &&
    mv -- "$tmp" "$cfg" || {
        rm -f -- "$tmp"
        return 1
    }

    remove_include "${P[PROJECT_DIR]}" "$cfg" || return 1
    git config --global --add \
        "includeIf.gitdir:${P[PROJECT_DIR]%/}/.path" "$cfg"
}

show_global() {
    info "Current explicit global Git configuration:"
    git config --global --show-origin --list 2>/dev/null ||
        warn "No readable global configuration."
    warn "Settings above may contain sensitive values. They are not logged."
}

check_directory_conflict() (
    local proposed="${P[PROJECT_DIR]}" current="${P[PROFILE_NAME]}" name
    refresh_profiles
    for name in "${PROFILES[@]}"; do
        [[ "$name" == "$current" ]] && continue
        load_profile "$name" || continue
        if [[ "$proposed/" == "${P[PROJECT_DIR]%/}/"* ||
              "${P[PROJECT_DIR]%/}/" == "${proposed%/}/"* ]]; then
            printf 'Conflicting/overlapping directory: %s (%s)\n' \
                "$name" "${P[PROJECT_DIR]}"
            return 1
        fi
    done
)

edit_fields() {
    local field default value
    for field in PROJECT_DIR GITLAB_HOST GIT_NAME GIT_EMAIL; do
        while true; do
            default="${P[$field]}"
            ask "$field [$default]" || return 1
            value="${REPLY_VALUE:-$default}"

            case "$field" in
                PROJECT_DIR)
                    value="$(path_value "$value")" || continue
                    # Git directory conditions interpret these as patterns.
                    if [[ "$value" == *[\*\?\[]* ]]; then
                        warn "Directory names containing *, ? or [ are unsupported."
                        continue
                    fi
                    if [[ -e "$value" && ! -d "$value" ]]; then
                        warn "That path is not a directory."
                        continue
                    fi
                    if [[ ! -d "$value" ]]; then
                        yes "Directory missing. Create during apply?" ||
                            continue
                    fi
                    ;;
                GITLAB_HOST)
                    [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] ||
                        { warn "Enter a hostname only."; continue; }
                    ;;
                GIT_NAME|GIT_EMAIL)
                    [[ -n "$value" ]] || continue
                    ;;
            esac

            P[$field]="$value"
            break
        done
    done
}

select_key() {
    local choice path name folder pub users i
    local -a keys=()
    folder="$SSH_DIR"

    while true; do
        keys=()
        if [[ -d "$folder" ]]; then
            while IFS= read -r -d '' pub; do
                [[ -f "${pub%.pub}" ]] && keys+=("${pub%.pub}")
            done < <(
                find "$folder" -maxdepth 2 -type f \
                    -name '*.pub' -print0 2>/dev/null | sort -z
            )
        fi

        info "SSH key folder: $folder"
        for i in "${!keys[@]}"; do
            printf '[%d] %s\n' "$((i + 1))" "${keys[$i]}"
        done
        echo '[n] New key'
        echo '[p] Change scan folder'
        echo '[f] Enter existing private-key path'
        echo '[k] Keep current key'

        ask "Select key option" || return 1
        choice="$REPLY_VALUE"

        case "$choice" in
            p)
                ask "Folder to scan [$SSH_DIR]" || continue
                folder="$(path_value "${REPLY_VALUE:-$SSH_DIR}")" ||
                    continue
                continue
                ;;
            k)
                path="${P[KEY_PATH]}"
                [[ -f "$path" ]] ||
                    { warn "Current key does not exist."; continue; }
                ;;
            f)
                ask "Existing private-key path" || continue
                path="$(path_value "$REPLY_VALUE")" || continue
                [[ -f "$path" && -r "$path" ]] ||
                    { warn "Key missing or unreadable."; continue; }
                ;;
            n)
                ask "Key filename [id_ed25519_${P[PROFILE_NAME]}]" ||
                    continue
                name="${REPLY_VALUE:-id_ed25519_${P[PROFILE_NAME]}}"
                valid_name "$name" || {
                    warn "No spaces/slashes. Use letters, digits, ., _ or -."
                    continue
                }

                path="$SSH_DIR/${P[PROFILE_NAME]}/$name"
                echo "[1] Profile default: $path"
                echo "[2] Scan folder: $folder/$name"
                echo '[3] Full custom path'
                ask "Destination [1]" || continue

                case "${REPLY_VALUE:-1}" in
                    1) ;;
                    2) path="$folder/$name" ;;
                    3)
                        ask "Full private-key path" || continue
                        path="$REPLY_VALUE"
                        ;;
                    *) continue ;;
                esac

                path="$(path_value "$path")" || continue
                valid_name "$(basename "$path")" || {
                    warn "Invalid key filename: no spaces or slashes."
                    continue
                }

                if [[ -e "$path" || -L "$path" ||
                      -e "$path.pub" || -L "$path.pub" ]]; then
                    warn "Target already exists. Choose another filename."
                    continue
                fi
                ;;
            *)
                [[ "$choice" =~ ^[1-9][0-9]{0,5}$ ]] || continue
                i=$((10#$choice - 1))
                ((i < ${#keys[@]})) || continue
                path="${keys[$i]}"
                ;;
        esac

        path="$(path_value "$path")" || continue
        users="$(key_users "$path" "${P[PROFILE_NAME]}")"

        if [[ -n "$users" ]]; then
            line
            printf '%s!!! SHARED SSH KEY WARNING !!!%s\n' "$RED" "$RESET"
            printf 'Also assigned to:\n%s\n' "$users"
            line
            yes "Use this shared key anyway?" || continue
        fi

        P[KEY_PATH]="$path"
        return 0
    done
}

delete_old_key() {
    local old="$1" users
    [[ -n "$old" && "$old" != "${P[KEY_PATH]}" ]] || return 0

    users="$(key_users "$old")"
    if [[ -n "$users" ]]; then
        warn "Old key remains assigned to these profiles:"
        printf '%s\n' "$users"
        warn "Deletion blocked. The old key has been retained."
        return 0
    fi

    printf '\nOld key: %s\n' "$old"
    echo '[1] Keep on disk — no longer assigned to this profile (default)'
    echo '[2] Permanently delete private and public files'
    ask "Old-key action [1]" || return 0
    [[ "$REPLY_VALUE" == 2 ]] || return 0

    warn "No snapshot contains these SSH keys. Deletion cannot be undone."
    yes "Delete this old key pair?" || return 0
    ask "Type DELETE to confirm" || return 0
    [[ "$REPLY_VALUE" == DELETE ]] || return 0

    # Check again immediately before deletion.
    [[ -z "$(key_users "$old")" ]] || {
        fail "Key is referenced by a saved profile; deletion blocked."
        return 1
    }

    rm -f -- "$old" "$old.pub" &&
        ok "Deleted old key pair: $old" ||
        fail "Could not delete the old key pair."

    warn "This does not revoke the key in GitLab or unload ssh-agent."
}

public_key() {
    local path="${P[KEY_PATH]}"
    printf '\nProfile: %s\nPublic key: %s.pub\n' \
        "${P[PROFILE_NAME]}" "$path"

    if [[ -r "$path.pub" ]]; then
        cat -- "$path.pub"
        ssh-keygen -lf "$path.pub"
    else
        warn "Public-key file missing. Private key has not been changed."
    fi
}

apply_profile() {
    local old="${1:-}" old_dir="${2:-}" path="${P[KEY_PATH]}"
    local cfg
    cfg="$(config_file "${P[PROFILE_NAME]}")"

    check_directory_conflict || {
        fail "Choose non-overlapping project directories."
        return 1
    }

    show_global
    show_profile
    printf 'Key action: %s\n' \
        "$([[ -f "$path" ]] && echo 'Use existing key' || echo 'Generate Ed25519 key')"

    yes "Apply this profile configuration?" || return 0

    snapshot profile_apply ||
        { fail "Backup failed; nothing applied."; return 1; }

    info "Pre-change snapshot: $LAST_SNAPSHOT"

    if [[ ! -f "$path" ]]; then
        [[ ! -e "$path" && ! -L "$path" &&
           ! -e "$path.pub" && ! -L "$path.pub" ]] || {
            fail "Key target appeared since review; refusing overwrite."
            return 1
        }

        mkdir -p -- "$(dirname "$path")" || return 1
        chmod 700 -- "$(dirname "$path")" || return 1

        info "ssh-keygen will ask for an optional passphrase."
        ssh-keygen -t ed25519 -f "$path" -C "${P[GIT_EMAIL]}" || {
            fail "Key generation failed; profile not updated."
            return 1
        }
        chmod 600 "$path"
    fi

    mkdir -p -- "${P[PROJECT_DIR]}" || return 1

    write_profile_config && save_profile || {
        fail "Apply incomplete. Inspect snapshot: $LAST_SNAPSHOT"
        return 1
    }

    if [[ -n "$old_dir" && "$old_dir" != "${P[PROJECT_DIR]}" ]]; then
        remove_include "$old_dir" "$cfg" || {
            fail "Profile saved, but old include cleanup failed."
            return 1
        }
    fi

    ok "Profile applied: ${P[PROFILE_NAME]}"
    show_profile
    public_key

    if [[ -n "$old" && "$old" != "$path" ]]; then
        delete_old_key "$old"
    fi

    warn "Register the public key in the correct GitLab account."
    yes "Test SSH connectivity now?" && test_connection
    return 0
}

add_profile() {
    local name
    ask "New profile name" || return 0
    name="$REPLY_VALUE"
    valid_name "$name" || {
        warn "Invalid name: use letters, digits, ., _ or -."
        return 0
    }
    [[ ! -e "$(profile_file "$name")" ]] ||
        { warn "Profile already exists."; return 0; }

    P=(
        [PROFILE_NAME]="$name"
        [PROJECT_DIR]="$HOME/projects/$name"
        [KEY_PATH]="$SSH_DIR/$name/id_ed25519_$name"
        [GIT_NAME]="$name"
        [GIT_EMAIL]=''
        [GITLAB_HOST]='gitlab.com'
        [CREATED_AT]="$(date -Is)"
        [UPDATED_AT]=''
    )

    edit_fields && select_key && apply_profile
    return 0
}

edit_profile() {
    local old old_dir
    choose_profile || return 0
    old="${P[KEY_PATH]}"
    old_dir="${P[PROJECT_DIR]}"
    show_profile

    edit_fields && select_key && apply_profile "$old" "$old_dir"
    return 0
}

replace_key() {
    local old old_dir choice
    choose_profile || return 0
    old="${P[KEY_PATH]}"
    old_dir="${P[PROJECT_DIR]}"
    show_profile

    echo '[1] Replace key only — keep other parameters'
    echo '[2] Modify parameters, then replace key'
    ask "Replacement mode [1]" || return 0
    choice="${REPLY_VALUE:-1}"

    case "$choice" in
        1) ;;
        2) edit_fields || return 0 ;;
        *) return 0 ;;
    esac

    select_key || return 0
    apply_profile "$old" "$old_dir"
    return 0
}

remove_profile() {
    local name key dir
    choose_profile || return 0
    show_profile
    name="${P[PROFILE_NAME]}"
    key="${P[KEY_PATH]}"
    dir="${P[PROJECT_DIR]}"

    yes "Unlink profile '$name'? Project directory and keys are retained." ||
        return 0
    snapshot unlink || { fail "Backup failed."; return 1; }

    remove_include "$dir" "$(config_file "$name")" &&
    rm -f -- "$(config_file "$name")" "$(profile_file "$name")" || {
        fail "Unlink failed. Snapshot: $LAST_SNAPSHOT"
        return 1
    }

    ok "Unlinked profile: $name"
    P[KEY_PATH]=''
    delete_old_key "$key"
}

profiles_menu() {
    while true; do
        line
        info "MANAGE GIT PROFILES"
        refresh_profiles
        printf 'Saved: %s\n' "${PROFILES[*]:-(none)}"
        echo '[a] Add profile'
        echo '[e] Edit profile'
        echo '[r] Remove/unlink profile'
        echo '[v] View profile'
        ask "Action" || return 0

        case "$REPLY_VALUE" in
            a)
                while true; do
                    add_profile
                    yes "Add another custom profile?" || break
                done
                ;;
            e) edit_profile ;;
            r) remove_profile ;;
            v) choose_profile && show_profile ;;
        esac
    done
}

view_metadata() {
    local path
    choose_profile || return 0
    path="${P[KEY_PATH]}"
    show_profile

    if [[ -f "$path" ]]; then
        stat -c 'Private key permissions: %a; owner: %U' -- "$path"
        info "Passphrase protection is not inferred from file permissions."
    else
        warn "Private key is missing."
    fi

    public_key
    pause
}

view_all_public() (
    local name
    refresh_profiles
    for name in "${PROFILES[@]}"; do
        load_profile "$name" && public_key
    done
    pause
)

reveal_private() (
    local path answer ttyfd
    choose_profile || return 0
    path="${P[KEY_PATH]}"

    [[ -f "$path" && -r "$path" ]] ||
        { fail "Private key missing/unreadable."; return 1; }

    # Use the controlling terminal, not redirected standard output.
    exec {ttyfd}<>/dev/tty || {
        fail "Private-key viewing requires an interactive terminal."
        return 1
    }

    line
    warn "PRIVATE KEY EXPOSURE WARNING"
    warn "Stop recording, streaming, terminal logging and screen sharing."
    warn "Anyone obtaining an unencrypted private key may impersonate you."
    warn "Screen clearing cannot erase recordings or guarantee scrollback removal."
    printf 'Private key: %s\n' "$path"

    printf 'Type SHOW PRIVATE KEY to reveal, or Enter to cancel: ' >&"$ttyfd"
    IFS= read -r answer <&"$ttyfd" || return 0
    [[ "$answer" == 'SHOW PRIVATE KEY' ]] || return 0

    # Also clear on interruption while the key is visible.
    trap 'printf "\033[2J\033[3J\033[H" >&'"$ttyfd" EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    log "Private-key reveal requested: ${P[PROFILE_NAME]} (content not logged)"
    cat -- "$path" >&"$ttyfd"
    printf '\nPress Enter to clear: ' >&"$ttyfd"
    IFS= read -r answer <&"$ttyfd" || true
)

change_passphrase() {
    local users
    choose_profile || return 0
    show_profile
    users="$(key_users "${P[KEY_PATH]}" "${P[PROFILE_NAME]}")"
    [[ -z "$users" ]] || {
        warn "This key is shared with:"
        printf '%s\n' "$users"
    }

    warn "This modifies the private key in place. Keys are not in snapshots."
    warn "Keep a separate secure backup if needed."
    yes "Continue to add/change/remove the passphrase?" || return 0

    # OpenSSH reads passphrases directly; never pass them as arguments.
    if ssh-keygen -p -f "${P[KEY_PATH]}"; then
        ok "Passphrase operation completed: ${P[PROFILE_NAME]}"
        warn "An ssh-agent may still hold an already-unlocked identity."
    else
        fail "Passphrase operation failed or was cancelled."
    fi
}

test_connection() {
    local target user host port=22 output rc authority remainder

    ask "SSH URL/host [git@${P[GITLAB_HOST]}]" || return 0
    target="${REPLY_VALUE:-git@${P[GITLAB_HOST]}}"
    user=git

    # Supported:
    # gitlab.com
    # git@gitlab.com
    # git@gitlab.com:group/repo.git
    # https://gitlab.com/group/repo
    # ssh://git@gitlab.com:2222/group/repo.git
    case "$target" in
        ssh://*)
            authority="${target#ssh://}"
            authority="${authority%%/*}"
            if [[ "$authority" == *@* ]]; then
                user="${authority%%@*}"
                authority="${authority#*@}"
            fi
            host="${authority%%:*}"
            [[ "$authority" != *:* ]] || port="${authority##*:}"
            ;;
        https://*|http://*)
            authority="${target#*://}"
            authority="${authority%%/*}"
            host="${authority%%:*}"
            ;;
        *)
            remainder="$target"
            if [[ "$remainder" == *@* ]]; then
                user="${remainder%%@*}"
                remainder="${remainder#*@}"
            fi
            host="${remainder%%[:/]*}"
            ;;
    esac

    [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ &&
       "$user" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ &&
       "$port" =~ ^[0-9]{1,5}$ ]] || {
        fail "Unsupported target. Use a hostname or SSH/HTTPS repository URL."
        return 1
    }
    port=$((10#$port))
    ((port >= 1 && port <= 65535)) || return 1

    printf 'Testing %s@%s:%s using %s\n' \
        "$user" "$host" "$port" "${P[KEY_PATH]}"
    warn "Verify any first-connection host fingerprint before accepting it."

    # Interactive SSH permits encrypted-key passphrase prompts.
    # -t 1 avoids piping prompts; SSH stdout is captured for classification.
    if output="$(ssh -T -p "$port" \
        -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 \
        -o StrictHostKeyChecking=ask \
        -o IdentitiesOnly=yes \
        -i "${P[KEY_PATH]}" "$user@$host")"; then
        rc=0
    else
        rc=$?
    fi

    printf '%s\n' "$output"
    if [[ "$output" == *"Welcome to GitLab"* ]]; then
        ok "GitLab SSH authentication confirmed: ${P[PROFILE_NAME]}"
    elif ((rc == 0)); then
        ok "SSH command completed successfully."
    else
        warn "Authentication not confirmed (SSH exit $rc)."
        log "SSH test not confirmed: ${P[PROFILE_NAME]} host=$host rc=$rc"
    fi
    return 0
}

ssh_menu() {
    while true; do
        line
        info "MANAGE SSH KEYS"
        echo '[1] View one profile: metadata and public key'
        echo '[2] View all public keys'
        echo '[3] Reveal a private key'
        echo '[4] Replace a profile key'
        echo '[5] Add/change/remove key passphrase'
        echo '[6] Test SSH connectivity'
        ask "Action" || return 0

        case "$REPLY_VALUE" in
            1) view_metadata ;;
            2) view_all_public ;;
            3) reveal_private ;;
            4) replace_key; pause ;;
            5) change_passphrase; pause ;;
            6) choose_profile && test_connection; pause ;;
        esac
    done
}

global_menu() {
    local key value action
    while true; do
        line
        show_global
        echo '[s] Set a global key'
        echo '[u] Unset a global key'
        ask "Action" || return 0
        action="$REPLY_VALUE"
        [[ "$action" == s || "$action" == u ]] || continue

        ask "Setting name, e.g. user.name or init.defaultBranch" || continue
        key="$REPLY_VALUE"
        [[ "$key" =~ ^[A-Za-z][A-Za-z0-9.-]*\.[A-Za-z][A-Za-z0-9-]*$ ]] ||
            { warn "Invalid/unsupported setting name."; continue; }

        case "${key,,}" in
            include.*|includeif.*)
                warn "Include settings are managed by the profile workflow."
                continue
                ;;
        esac

        value=''
        if [[ "$action" == s ]]; then
            ask "New value" || continue
            value="$REPLY_VALUE"
            printf 'Proposed: %s = %s\n' "$key" "$value"
        else
            printf 'Proposed: unset %s\n' "$key"
        fi

        yes "Apply global change?" || continue
        snapshot global_change ||
            { fail "Backup failed."; continue; }

        if [[ "$action" == s ]]; then
            git config --global --replace-all "$key" "$value" &&
                ok "Updated global setting: $key" ||
                fail "Global setting update failed: $key"
        else
            if git config --global --unset-all "$key"; then
                ok "Unset global setting: $key"
            else
                warn "Setting absent or could not be unset."
            fi
        fi
    done
}

choose_backup() {
    local entry i
    local -a backups=()
    while IFS= read -r entry; do
        backups+=("$entry")
    done < <(
        find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 \
            -type d -printf '%f\n' | sort -r
    )

    ((${#backups[@]})) ||
        { warn "No backups."; return 1; }

    for i in "${!backups[@]}"; do
        printf '[%d] %s\n' "$((i + 1))" "${backups[$i]}"
    done
    ask "Snapshot number" || return 1
    [[ "$REPLY_VALUE" =~ ^[1-9][0-9]{0,5}$ ]] || return 1
    i=$((10#$REPLY_VALUE - 1))
    ((i < ${#backups[@]})) || return 1
    SELECTED_BACKUP="$BACKUP_DIR/${backups[$i]}"
}

restore_backup() {
    local selected name file
    choose_backup || return 0
    selected="$SELECTED_BACKUP"

    # Old snapshots use profile-configs/ rather than configs/.
    local configs="$selected/configs"
    [[ -d "$configs" ]] || configs="$selected/profile-configs"

    [[ -d "$selected/db" && -d "$configs" ]] || {
        fail "Incomplete snapshot; restore refused."
        return 1
    }

    warn "Restore replaces managed profile configs AND the matching database."
    warn "SSH key files are never restored or deleted."
    warn "Other global configuration changes since this snapshot will roll back."
    yes "Restore $selected?" || return 0
    snapshot before_restore ||
        { fail "Safety snapshot failed."; return 1; }

    # Remove only currently tracked profile configs.
    refresh_profiles
    for name in "${PROFILES[@]}"; do
        rm -f -- "$(config_file "$name")" || return 1
    done

    if [[ -f "$selected/gitconfig" ]]; then
        cp -p -- "$selected/gitconfig" "$HOME/.gitconfig" || return 1
    else
        rm -f -- "$HOME/.gitconfig" || return 1
    fi

    shopt -s nullglob
    for file in "$DB_DIR"/*.conf; do
        rm -f -- "$file" || return 1
    done
    for file in "$selected/db"/*.conf; do
        cp -p -- "$file" "$DB_DIR/" || return 1
    done

    # Restore configs referenced by the restored database only.
    refresh_profiles
    for name in "${PROFILES[@]}"; do
        file="$configs/.gitconfig-$name"
        [[ ! -f "$file" ]] ||
            cp -p -- "$file" "$(config_file "$name")" || return 1
    done
    shopt -u nullglob

    ok "Restored configuration and database: $selected"
    warn "Check referenced SSH keys still exist before using restored profiles."
}

main_menu() {
    local choice
    while true; do
        line
        info "GIT PROFILE MANAGER — WSL / LINUX"
        printf 'State: %s\n' "$APP_DIR"
        echo '[1] Manage Git profiles (add/edit/remove/review)'
        echo '[2] Manage global Git configuration'
        echo '[3] Manage SSH Keys'
        echo '[4] Create a full configuration backup'
        echo '[5] List backup snapshots'
        echo '[6] Restore a backup snapshot'
        echo '[7] Exit'

        read -r -p "Select [1-7]: " choice || finish
        case "$choice" in
            1) profiles_menu ;;
            2) global_menu ;;
            3) ssh_menu ;;
            4)
                if snapshot manual; then
                    ok "Backup created: $LAST_SNAPSHOT"
                else
                    fail "Backup failed."
                fi
                pause
                ;;
            5)
                find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 \
                    -type d -printf '%f\n' | sort -r
                pause
                ;;
            6)
                restore_backup || fail "Restore did not complete."
                pause
                ;;
            7) finish ;;
            *) warn "Choose a number from 1 to 7." ;;
        esac
    done
}

log "Application started."
if ((FIRST_RUN)); then
    warn "No previous database folder found. Starting fresh."
    warn "Existing keys and directories will still be checked."
fi

main_menu