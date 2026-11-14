#!/usr/bin/env bash
# Git Profile Manager for WSL/Linux
# Stores its own state beside this script in .gitprofile_manager/.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
APP_DIR="$SCRIPT_DIR/.gitprofile_manager"
DB_DIR="$APP_DIR/db"
BACKUP_DIR="$APP_DIR/backups"
LOG_DIR="$APP_DIR/logs"
ERRORS_DIR="$APP_DIR/errors"
RUN_LOG="$LOG_DIR/run_$(date +%Y%m%d_%H%M%S).log"
SSH_DIR="$HOME/.ssh"

RESET='\033[0m'
BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'

mkdir -p "$DB_DIR" "$BACKUP_DIR" "$LOG_DIR" "$ERRORS_DIR"
touch "$RUN_LOG"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$RUN_LOG"; }
info() { printf '%b%s%b\n' "$CYAN" "$*" "$RESET"; }
success() { printf '%b%s%b\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%b%s%b\n' "$YELLOW" "$*" "$RESET"; }
error() { printf '%b%s%b\n' "$RED" "$*" "$RESET" >&2; }
line() { printf '%s\n' '================================================================================'; }

on_error() {
    local rc=$?
    error "An unexpected error occurred (exit code $rc). See: $RUN_LOG"
    log "ERROR: command failed at line $1 with exit code $rc"
    local err_log="$ERRORS_DIR/err_$(date +%Y%m%d_%H%M%S).log"
    cp "$RUN_LOG" "$err_log"
    exit "$rc"
}
trap 'on_error $LINENO' ERR

log_success() {
    local label="${1:-operation}" stamp file
    stamp="$(date +%Y%m%d_%H%M%S)"
    file="$LOG_DIR/success_${stamp}.log"
    {
        echo "SUCCESS: $label"
        echo "Timestamp: $(date '+%F %T')"
        echo "Run log: $RUN_LOG"
    } > "$file"
    log "Success logged: $label"
}

expand_path() {
    local path="$1"
    path="${path/#\~/$HOME}"
    if [[ "$path" != /* ]]; then
        path="$PWD/$path"
    fi
    printf '%s\n' "$path"
}

confirm_exit() {
    local answer
    read -r -p "Exit the script now? (y/n): " answer
    [[ "$answer" =~ ^[Yy]$ ]] && { log "User exited script"; exit 0; }
}

# Return codes: 0 normal input, 10 back, 11 exit request.
prompt_value() {
    local prompt="$1" value
    read -r -p "$prompt [b=back, x=exit]: " value
    case "${value,,}" in
        b|back|:back) return 10 ;;
        x|exit|:exit) confirm_exit; return 11 ;;
    esac
    REPLY_VALUE="$value"
    return 0
}

pause_submenu() {
    local value
    read -r -p "Press Enter to continue (or x to exit): " value || true
    if [[ "${value,,}" == "x" || "${value,,}" == "exit" ]]; then
        confirm_exit
    fi
    return 0
}

is_valid_profile_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

is_valid_key_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

profile_file() { printf '%s/%s.conf\n' "$DB_DIR" "$1"; }
profile_gitconfig() { printf '%s/.gitconfig-%s\n' "$HOME" "$1"; }

list_profiles() {
    local f
    shopt -s nullglob
    for f in "$DB_DIR"/*.conf; do
        basename "${f%.conf}"
    done
    shopt -u nullglob
}

profile_exists() { [[ -f "$(profile_file "$1")" ]]; }

load_profile() {
    local name="$1" file
    file="$(profile_file "$name")"
    [[ -f "$file" ]] || return 1
    unset PROFILE_NAME PROJECT_DIR KEY_PATH GIT_NAME GIT_EMAIL GITLAB_HOST CREATED_AT UPDATED_AT
    source "$file"
}

save_profile() {
    local name="$1" created="$2" file tmp
    file="$(profile_file "$name")"
    tmp="$(mktemp "$DB_DIR/.${name}.XXXXXX")"
    {
        printf 'PROFILE_NAME=%q\n' "$PROFILE_NAME"
        printf 'PROJECT_DIR=%q\n' "$PROJECT_DIR"
        printf 'KEY_PATH=%q\n' "$KEY_PATH"
        printf 'GIT_NAME=%q\n' "$GIT_NAME"
        printf 'GIT_EMAIL=%q\n' "$GIT_EMAIL"
        printf 'GITLAB_HOST=%q\n' "$GITLAB_HOST"
        printf 'CREATED_AT=%q\n' "$created"
        printf 'UPDATED_AT=%q\n' "$(date '+%FT%T%z')"
    } > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$file"
}

show_profiles() {
    local profiles=() p
    mapfile -t profiles < <(list_profiles)
    if [[ ${#profiles[@]} -eq 0 ]]; then
        warn "No saved profiles were found."
        return
    fi
    printf '%-4s %-18s %-34s %-34s %-28s %-22s\n' '#' 'Profile' 'Project directory' 'SSH private key' 'Git email' 'GitLab host'
    printf '%s\n' '-----------------------------------------------------------------------------------------------------------------------------------------------------'
    local i=1
    for p in "${profiles[@]}"; do
        load_profile "$p"
        printf '%-4s %-18s %-34.34s %-34.34s %-28.28s %-22.22s\n' "$i" "$PROFILE_NAME" "$PROJECT_DIR" "$KEY_PATH" "$GIT_EMAIL" "$GITLAB_HOST"
        ((i++)) || true
    done
}

show_global_glance() {
    local global_name global_email
    global_name="$(git config --global --get user.name 2>/dev/null || true)"
    global_email="$(git config --global --get user.email 2>/dev/null || true)"
    echo "Current global Git identity (profile settings override this inside their directories):"
    echo "  user.name : ${global_name:-'(not set)'}"
    echo "  user.email: ${global_email:-'(not set)'}"
}

create_snapshot() {
    local reason="$1" stamp snap f found=0
    stamp="$(date +%Y%m%d_%H%M%S)"
    snap="$BACKUP_DIR/${stamp}_${reason}"
    mkdir -p "$snap/profile-configs" "$snap/db"

    if [[ -f "$HOME/.gitconfig" ]]; then
        cp -p "$HOME/.gitconfig" "$snap/gitconfig"
        found=1
    fi

    shopt -s nullglob
    for f in "$HOME"/.gitconfig-*; do
        cp -p "$f" "$snap/profile-configs/"
        found=1
    done
    for f in "$DB_DIR"/*.conf; do
        cp -p "$f" "$snap/db/"
        found=1
    done
    shopt -u nullglob

    printf 'reason=%q\ncreated_at=%q\n' "$reason" "$(date '+%FT%T%z')" > "$snap/manifest.conf"
    log "Created snapshot: $snap"
    if [[ "$found" -eq 0 ]]; then
        warn "Snapshot created, but there were no existing Git config/profile files to copy."
    else
        success "Snapshot created: $snap"
    fi
    printf '%s\n' "$snap"
}

remove_include_for_dir() {
    local directory="$1" match
    [[ -n "$directory" ]] || return 0
    match="${directory%/}/"
    git config --global --unset-all "includeIf.gitdir:${match}.path" 2>/dev/null || true
}

set_profile_include() {
    local directory="$1" profile="$2" match config_path
    match="${directory%/}/"
    config_path="$(profile_gitconfig "$profile")"
    git config --global --unset-all "includeIf.gitdir:${match}.path" 2>/dev/null || true
    git config --global "includeIf.gitdir:${match}.path" "$config_path"
}

scan_keys_in_dir() {
    local base="$1" f pub
    [[ -d "$base" ]] || return 0
    while IFS= read -r -d '' pub; do
        f="${pub%.pub}"
        [[ -f "$f" ]] && printf '%s\n' "$f"
    done < <(find "$base" -maxdepth 2 -type f -name '*.pub' -print0 2>/dev/null | sort -z)
}

key_used_by_profiles() {
    local candidate="$1" p users=()
    while IFS= read -r p; do
        load_profile "$p"
        [[ "$KEY_PATH" == "$candidate" ]] && users+=("$p")
    done < <(list_profiles)
    printf '%s\n' "${users[*]:-}"
}

show_key_reuse_warning() {
    local key="$1" current_profile="$2" users filtered=() u
    users="$(key_used_by_profiles "$key")"
    for u in $users; do
        [[ "$u" != "$current_profile" ]] && filtered+=("$u")
    done
    [[ ${#filtered[@]} -gt 0 ]] || return 0
    line
    printf '%b%s%b\n' "$BOLD$RED" '!!! SSH KEY REUSE WARNING !!!' "$RESET"
    printf '%bThis private key is already linked to profile(s): %s%b\n' "$BOLD$YELLOW" "${filtered[*]}" "$RESET"
    printf '%bKey: %s%b\n' "$BOLD$YELLOW" "$key" "$RESET"
    echo "Using one key for multiple GitLab identities can authenticate you as the wrong account."
    line
    local ans
    while true; do
        prompt_value "Proceed with this reused key? (y/n)" || {
            [[ $? -eq 10 ]] && return 10
            return 11
        }
        ans="$REPLY_VALUE"
        case "${ans,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) warn "Please enter y or n." ;;
        esac
    done
}

select_ssh_key() {
    local profile="$1" existing_key="${2:-}" base="$SSH_DIR" keys=() choice key_name path custom_path ans
    while true; do
        echo
        line
        echo "SSH key selection for profile: $profile"
        echo "Current scan folder: $base"
        echo "Default new-key location: $SSH_DIR/$profile/id_ed25519_$profile"
        line
        mapfile -t keys < <(scan_keys_in_dir "$base")
        if [[ ${#keys[@]} -gt 0 ]]; then
            echo "Existing private keys with matching public keys:"
            local i=1
            for path in "${keys[@]}"; do
                printf '  [%d] %s\n' "$i" "$path"
                ((i++)) || true
            done
        else
            warn "No usable SSH key pairs found in this scan folder (up to one subfolder deep)."
        fi
        echo "  [n] Create a new SSH key"
        echo "  [p] Declare/change SSH key folder to scan"
        [[ -n "$existing_key" ]] && echo "  [k] Keep current assigned key: $existing_key"
        echo "  [b] Back"
        echo "  [x] Exit"
        read -r -p "Choose a key option: " choice
        case "${choice,,}" in
            b|back) return 10 ;;
            x|exit) confirm_exit; return 11 ;;
            p)
                prompt_value "Enter SSH key folder to scan" || continue
                base="$(expand_path "$REPLY_VALUE")"
                if [[ ! -d "$base" ]]; then
                    warn "Folder does not exist: $base"
                    prompt_value "Create this folder now? (y/n)" || continue
                    if [[ "$REPLY_VALUE" =~ ^[Yy]$ ]]; then
                        mkdir -p "$base"
                        chmod 700 "$base"
                        success "Created SSH folder: $base"
                    fi
                fi
                ;;
            k)
                [[ -n "$existing_key" ]] || { warn "No current key exists for this profile."; continue; }
                KEY_PATH="$existing_key"
                show_key_reuse_warning "$KEY_PATH" "$profile" || continue
                return 0
                ;;
            n)
                while true; do
                    prompt_value "Enter new key name (no spaces or /)" || break
                    key_name="$REPLY_VALUE"
                    if ! is_valid_key_name "$key_name"; then
                        printf '%b%s%b\n' "$BOLD$RED" 'INVALID KEY NAME: use letters, numbers, dot, underscore, or hyphen only; no spaces or slashes.' "$RESET"
                        continue
                    fi
                    echo "Save new key in:"
                    echo "  [1] Profile default: $SSH_DIR/$profile/id_ed25519_$key_name"
                    echo "  [2] Current/custom scan folder: $base/id_ed25519_$key_name"
                    echo "  [3] Provide a full custom private-key path"
                    echo "  [b] Back"
                    echo "  [x] Exit"
                    read -r -p "Select destination: " ans
                    case "${ans,,}" in
                        1) path="$SSH_DIR/$profile/id_ed25519_$key_name" ;;
                        2) path="$base/id_ed25519_$key_name" ;;
                        3)
                            prompt_value "Enter full private-key path" || continue
                            path="$(expand_path "$REPLY_VALUE")"
                            if ! is_valid_key_name "$(basename "$path")"; then
                                printf '%b%s%b\n' "$BOLD$RED" 'INVALID KEY BASENAME: no spaces or slashes; use letters, numbers, dot, underscore, or hyphen only.' "$RESET"
                                continue
                            fi
                            ;;
                        b|back) break ;;
                        x|exit) confirm_exit; continue ;;
                        *) warn "Invalid selection."; continue ;;
                    esac
                    [[ -n "${path:-}" ]] || continue
                    if [[ -e "$path" || -e "$path.pub" ]]; then
                        warn "A key or public-key file already exists at: $path"
                        prompt_value "Use the existing private key instead? (y/n)" || continue
                        if [[ "$REPLY_VALUE" =~ ^[Yy]$ && -f "$path" && -f "$path.pub" ]]; then
                            KEY_PATH="$path"
                            show_key_reuse_warning "$KEY_PATH" "$profile" || break
                            return 0
                        fi
                        continue
                    fi
                    KEY_PATH="$path"
                    KEY_NEW=1
                    show_key_reuse_warning "$KEY_PATH" "$profile" || break
                    return 0
                done
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#keys[@]} )); then
                    KEY_PATH="${keys[$((choice-1))]}"
                    KEY_NEW=0
                    show_key_reuse_warning "$KEY_PATH" "$profile" || continue
                    return 0
                fi
                warn "Invalid selection."
                ;;
        esac
    done
}

collect_profile() {
    local mode="$1" original_name="${2:-}" created_at="${3:-}" name_input default_dir value
    local prior_dir='' prior_key='' prior_git_name='' prior_git_email='' prior_host=''
    KEY_NEW=0

    if [[ "$mode" == "edit" ]]; then
        load_profile "$original_name"
        prior_dir="$PROJECT_DIR"; prior_key="$KEY_PATH"; prior_git_name="$GIT_NAME"; prior_git_email="$GIT_EMAIL"; prior_host="$GITLAB_HOST"
    fi

    while true; do
        prompt_value "Profile name [${original_name:-example: personal, work}]" || return $?
        name_input="$REPLY_VALUE"
        [[ -n "$name_input" ]] || { warn "Profile name cannot be empty."; continue; }
        if ! is_valid_profile_name "$name_input"; then
            error "Invalid profile name. Use letters, numbers, dot, underscore, or hyphen only; no spaces or slashes."
            continue
        fi
        if [[ "$mode" == "add" && "$name_input" != "$original_name" ]] && profile_exists "$name_input"; then
            warn "A saved profile named '$name_input' already exists. Use Edit instead."
            continue
        fi
        PROFILE_NAME="$name_input"
        break
    done

    default_dir="${prior_dir:-$HOME/projects/$PROFILE_NAME}"
    while true; do
        prompt_value "Project directory [default: $default_dir]" || return $?
        value="${REPLY_VALUE:-$default_dir}"
        PROJECT_DIR="$(expand_path "$value")"
        if [[ ! -d "$PROJECT_DIR" ]]; then
            warn "Directory does not exist: $PROJECT_DIR"
            prompt_value "Create it during final apply? (y/n)" || return $?
            [[ "$REPLY_VALUE" =~ ^[Yy]$ ]] || { warn "Choose an existing directory or approve creation."; continue; }
            DIR_NEW=1
        else
            DIR_NEW=0
        fi
        break
    done

    KEY_PATH=''; KEY_NEW=0
    select_ssh_key "$PROFILE_NAME" "$prior_key" || return $?

    while true; do
        prompt_value "GitLab hostname [default: ${prior_host:-gitlab.com}]" || return $?
        GITLAB_HOST="${REPLY_VALUE:-${prior_host:-gitlab.com}}"
        GITLAB_HOST="${GITLAB_HOST#git@}"
        GITLAB_HOST="${GITLAB_HOST#https://}"
        GITLAB_HOST="${GITLAB_HOST#http://}"
        GITLAB_HOST="${GITLAB_HOST%%/*}"
        [[ -n "$GITLAB_HOST" && "$GITLAB_HOST" != *[[:space:]]* ]] || { warn "Enter a valid hostname without spaces."; continue; }
        break
    done

    while true; do
        prompt_value "Git commit name [default: ${prior_git_name:-$PROFILE_NAME}]" || return $?
        GIT_NAME="${REPLY_VALUE:-${prior_git_name:-$PROFILE_NAME}}"
        [[ -n "$GIT_NAME" ]] && break
    done

    while true; do
        prompt_value "Git commit email [default: ${prior_git_email:-not set}]" || return $?
        GIT_EMAIL="${REPLY_VALUE:-$prior_git_email}"
        [[ -n "$GIT_EMAIL" ]] || { warn "Git email cannot be empty."; continue; }
        [[ "$GIT_EMAIL" == *'@'* ]] || warn "This does not look like a normal email address; it will still be accepted."
        break
    done

    PROFILE_CREATED_AT="${created_at:-$(date '+%FT%T%z')}"
    return 0
}

queue_profile() {
    local mode="$1" name="$2" created="$3" record
    record="$(mktemp "$APP_DIR/.queue.XXXXXX")"
    {
        printf 'MODE=%q\n' "$mode"
        printf 'OLD_PROFILE_NAME=%q\n' "$name"
        printf 'CREATED_AT_QUEUE=%q\n' "$created"
        printf 'PROFILE_NAME=%q\n' "$PROFILE_NAME"
        printf 'PROJECT_DIR=%q\n' "$PROJECT_DIR"
        printf 'KEY_PATH=%q\n' "$KEY_PATH"
        printf 'KEY_NEW=%q\n' "$KEY_NEW"
        printf 'DIR_NEW=%q\n' "$DIR_NEW"
        printf 'GIT_NAME=%q\n' "$GIT_NAME"
        printf 'GIT_EMAIL=%q\n' "$GIT_EMAIL"
        printf 'GITLAB_HOST=%q\n' "$GITLAB_HOST"
        printf 'PROFILE_CREATED_AT=%q\n' "$PROFILE_CREATED_AT"
    } > "$record"
    QUEUE_FILES+=("$record")
}

show_queue_review() {
    local f i=1
    line
    echo "PENDING PROFILE CHANGES (nothing has been applied yet)"
    line
    show_global_glance
    echo
    printf '%-4s %-10s %-16s %-30s %-30s %-25s %-18s\n' '#' 'Action' 'Profile' 'Directory' 'SSH key' 'Email' 'Host'
    printf '%s\n' '-----------------------------------------------------------------------------------------------------------------------------------------------------'
    for f in "${QUEUE_FILES[@]}"; do
        source "$f"
        printf '%-4s %-10s %-16s %-30.30s %-30.30s %-25.25s %-18.18s\n' "$i" "$MODE" "$PROFILE_NAME" "$PROJECT_DIR" "$KEY_PATH" "$GIT_EMAIL" "$GITLAB_HOST"
        echo "     Directory: $([[ -d "$PROJECT_DIR" ]] && echo 'exists' || echo 'will be created') | Key: $([[ -f "$KEY_PATH" ]] && echo 'exists' || echo 'will be generated')"
        ((i++)) || true
    done
    line
}

apply_queue() {
    local snapshot f old_name old_dir created status public_key
    snapshot="$(create_snapshot profile_apply)"
    echo
    info "Applying confirmed changes..."
    for f in "${QUEUE_FILES[@]}"; do
        source "$f"
        old_name="$OLD_PROFILE_NAME"
        old_dir=''
        if [[ "$MODE" == "edit" && -n "$old_name" ]] && load_profile "$old_name"; then
            old_dir="$PROJECT_DIR"
        fi
        source "$f"

        if [[ "$MODE" == "edit" && -n "$old_dir" ]]; then
            remove_include_for_dir "$old_dir"
            if [[ "$old_name" != "$PROFILE_NAME" ]]; then
                rm -f "$(profile_gitconfig "$old_name")" "$(profile_file "$old_name")"
            fi
        fi

        mkdir -p "$PROJECT_DIR"
        if [[ ! -f "$KEY_PATH" ]]; then
            mkdir -p "$(dirname "$KEY_PATH")"
            chmod 700 "$SSH_DIR" "$(dirname "$KEY_PATH")" 2>/dev/null || true
            info "Generating Ed25519 key: $KEY_PATH"
            ssh-keygen -t ed25519 -f "$KEY_PATH" -C "$GIT_EMAIL" -o
            chmod 600 "$KEY_PATH"
            chmod 644 "${KEY_PATH}.pub"
            log "Generated SSH key: $KEY_PATH"
        fi

        cat > "$(profile_gitconfig "$PROFILE_NAME")" <<EOF
# Managed by git-profile-manager. Do not edit profile identity via global Git config.
[user]
    name = $GIT_NAME
    email = $GIT_EMAIL
[core]
    sshCommand = ssh -i $KEY_PATH -o IdentitiesOnly=yes
EOF
        chmod 600 "$(profile_gitconfig "$PROFILE_NAME")"
        set_profile_include "$PROJECT_DIR" "$PROFILE_NAME"
        save_profile "$PROFILE_NAME" "$PROFILE_CREATED_AT"

        status='FAILED'
        if [[ -f "$KEY_PATH" ]]; then
            set +e
            ssh_output="$(ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i "$KEY_PATH" -T "git@$GITLAB_HOST" 2>&1)"
            ssh_rc=$?
            set -e
            if [[ "$ssh_output" == *'Welcome to GitLab'* || "$ssh_output" == *'successfully authenticated'* ]]; then
                status='SUCCESS'
            else
                status='NOT CONFIRMED'
            fi
            log "SSH test profile=$PROFILE_NAME host=$GITLAB_HOST rc=$ssh_rc output=$ssh_output"
        fi
        printf '%s|%s\n' "$PROFILE_NAME" "$status" >> "$APP_DIR/.last_status"
        success "Applied profile '$PROFILE_NAME' (SSH test: $status)"
    done

    echo
    line
    echo "FINAL APPLIED CONFIGURATION"
    line
    show_profiles
    echo
    echo "Public keys (add the appropriate key to each GitLab account):"
    local p
    while IFS= read -r p; do
        load_profile "$p"
        echo
        echo "[$PROFILE_NAME] $KEY_PATH.pub"
        echo '--------------------------------------------------------------------------------'
        if [[ -f "${KEY_PATH}.pub" ]]; then
            cat "${KEY_PATH}.pub"
        else
            warn "Public key not found."
        fi
    done < <(list_profiles)
    line
    success "Done. A pre-change snapshot was saved at: $snapshot"
    log "Applied queued profile changes successfully"
    log_success "Profile changes applied"
}

cleanup_queue() {
    local f
    for f in "${QUEUE_FILES[@]:-}"; do rm -f "$f"; done
    QUEUE_FILES=()
}

profile_wizard() {
    QUEUE_FILES=()
    local action choice profiles=() index selected created
    while true; do
        clear
        line
        echo "PROFILE MANAGEMENT"
        line
        show_profiles
        echo
        echo "  [a] Add a profile"
        echo "  [e] Edit a profile"
        echo "  [r] Remove/unlink a profile"
        echo "  [d] Review pending changes"
        echo "  [b] Back to main menu"
        echo "  [x] Exit script"
        read -r -p "Choose an option: " choice
        case "${choice,,}" in
            b|back) cleanup_queue; return ;;
            x|exit) cleanup_queue; confirm_exit ;;
            a)
                if collect_profile add '' ''; then
                    queue_profile add '' ''
                    success "Profile '$PROFILE_NAME' added to pending changes."
                fi
                ;;
            e)
                mapfile -t profiles < <(list_profiles)
                if [[ ${#profiles[@]} -eq 0 ]]; then warn "No saved profiles to edit."; pause_submenu; continue; fi
                show_profiles
                prompt_value "Enter profile number to edit" || continue
                index="$REPLY_VALUE"
                if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#profiles[@]} )); then
                    selected="${profiles[$((index-1))]}"
                    load_profile "$selected"; created="$CREATED_AT"
                    if collect_profile edit "$selected" "$created"; then
                        queue_profile edit "$selected" "$created"
                        success "Profile '$PROFILE_NAME' update added to pending changes."
                    fi
                else
                    warn "Invalid profile number."
                fi
                ;;
            r) remove_profile_menu ;;
            d)
                if [[ ${#QUEUE_FILES[@]} -eq 0 ]]; then warn "No pending changes."; pause_submenu; continue; fi
                review_and_apply
                ;;
            *) warn "Invalid option."; sleep 1 ;;
        esac
    done
}

review_and_apply() {
    local choice index
    while true; do
        clear
        show_queue_review
        echo "  [y] Apply all pending changes"
        echo "  [e] Re-edit a pending item"
        echo "  [c] Cancel all pending changes"
        echo "  [b] Back to profile management"
        echo "  [x] Exit script"
        read -r -p "Choose an option: " choice
        case "${choice,,}" in
            y|yes)
                : > "$APP_DIR/.last_status"
                apply_queue
                cleanup_queue
                pause_submenu
                return
                ;;
            e)
                prompt_value "Enter pending item number" || continue
                index="$REPLY_VALUE"
                if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#QUEUE_FILES[@]} )); then
                    local f="${QUEUE_FILES[$((index-1))]}"
                    source "$f"
                    if collect_profile "$MODE" "$OLD_PROFILE_NAME" "$PROFILE_CREATED_AT"; then
                        rm -f "$f"
                        QUEUE_FILES[$((index-1))]=''
                        local newf
                        queue_profile "$MODE" "$OLD_PROFILE_NAME" "$PROFILE_CREATED_AT"
                        QUEUE_FILES[$((index-1))]="${QUEUE_FILES[-1]}"
                        unset 'QUEUE_FILES[-1]'
                    fi
                else
                    warn "Invalid pending item number."
                fi
                ;;
            c)
                cleanup_queue
                success "All pending changes discarded; nothing was applied."
                pause_submenu
                return
                ;;
            b|back) return ;;
            x|exit) cleanup_queue; confirm_exit ;;
            *) warn "Invalid option." ;;
        esac
    done
}

remove_profile_menu() {
    local profiles=() selected index choice key ans confirm_name key_path
    mapfile -t profiles < <(list_profiles)
    [[ ${#profiles[@]} -gt 0 ]] || { warn "No saved profiles to remove."; pause_submenu; return; }
    clear
    line
    echo "REMOVE / UNLINK PROFILE"
    line
    show_profiles
    prompt_value "Enter profile number" || return
    index="$REPLY_VALUE"
    if ! [[ "$index" =~ ^[0-9]+$ ]] || (( index < 1 || index > ${#profiles[@]} )); then
        warn "Invalid profile number."; pause_submenu; return
    fi
    selected="${profiles[$((index-1))]}"
    load_profile "$selected"
    key_path="$KEY_PATH"
    echo
    echo "Selected profile: $selected"
    echo "  Directory: $PROJECT_DIR"
    echo "  Key:       $key_path"
    echo "  [1] Unlink profile only (remove Git config and database record; keep keys)"
    echo "  [2] Unlink profile and delete its SSH key pair (double confirmation)"
    echo "  [b] Back"
    echo "  [x] Exit"
    read -r -p "Choose action: " choice
    case "${choice,,}" in
        b|back) return ;;
        x|exit) confirm_exit; return ;;
        1)
            prompt_value "Unlink '$selected'? This removes its Git config/database entry, not the key. (y/n)" || return
            [[ "$REPLY_VALUE" =~ ^[Yy]$ ]] || { warn "Cancelled."; return; }
            create_snapshot before_unlink >/dev/null
            remove_include_for_dir "$PROJECT_DIR"
            rm -f "$(profile_gitconfig "$selected")" "$(profile_file "$selected")"
            success "Unlinked profile '$selected'. SSH key retained: $key_path"
            log "Unlinked profile: $selected"
            log_success "Profile unlinked: $selected"
            ;;
        2)
            line
            printf '%b%s%b\n' "$BOLD$RED" 'DANGER: THIS WILL DELETE THE PRIVATE SSH KEY AND ITS PUBLIC KEY.' "$RESET"
            echo "Profile: $selected"
            echo "Private key: $key_path"
            echo "Public key:  $key_path.pub"
            line
            prompt_value "First confirmation: continue with deletion? (y/n)" || return
            [[ "$REPLY_VALUE" =~ ^[Yy]$ ]] || { warn "Cancelled."; return; }
            prompt_value "Second confirmation: type DELETE to permanently delete this key pair" || return
            [[ "$REPLY_VALUE" == 'DELETE' ]] || { warn "Deletion cancelled: confirmation text did not match."; return; }
            create_snapshot before_delete_profile >/dev/null
            remove_include_for_dir "$PROJECT_DIR"
            rm -f "$(profile_gitconfig "$selected")" "$(profile_file "$selected")"
            rm -f "$key_path" "${key_path}.pub"
            success "Profile '$selected' unlinked and key pair deleted."
            log "Deleted profile and key pair: $selected / $key_path"
            log_success "Profile and key deleted: $selected"
            ;;
        *) warn "Invalid action." ;;
    esac
    pause_submenu
}

manage_global_config() {
    local choice key value current
    while true; do
        clear
        line
        echo "GLOBAL GIT CONFIGURATION"
        line
        echo "The global config applies outside profile directories. Profile-specific settings override it inside managed project folders."
        echo
        for key in user.name user.email init.defaultBranch pull.rebase core.editor; do
            current="$(git config --global --get "$key" 2>/dev/null || true)"
            printf '%-22s %s\n' "$key:" "${current:-'(not set)'}"
        done
        echo
        echo "Full current global configuration:"
        git config --global --list 2>/dev/null || echo "(No global Git configuration found.)"
        echo
        echo "  [1] Set user.name"
        echo "  [2] Set user.email"
        echo "  [3] Set init.defaultBranch"
        echo "  [4] Set pull.rebase"
        echo "  [5] Set core.editor"
        echo "  [6] Set any arbitrary global key"
        echo "  [7] Unset a global key"
        echo "  [b] Back to main menu"
        echo "  [x] Exit script"
        read -r -p "Choose an option: " choice
        case "${choice,,}" in
            b|back) return ;;
            x|exit) confirm_exit ;;
            1) key='user.name' ;;
            2) key='user.email' ;;
            3) key='init.defaultBranch' ;;
            4) key='pull.rebase' ;;
            5) key='core.editor' ;;
            6)
                prompt_value "Enter Git config key (example: alias.lg)" || continue
                key="$REPLY_VALUE"
                ;;
            7)
                prompt_value "Enter global Git config key to unset" || continue
                key="$REPLY_VALUE"
                prompt_value "Unset '$key'? (y/n)" || continue
                [[ "$REPLY_VALUE" =~ ^[Yy]$ ]] || continue
                create_snapshot global_unset >/dev/null
                git config --global --unset-all "$key" 2>/dev/null || warn "Key was not set."
                success "Unset global key: $key"
                log "Unset global config key: $key"
                log_success "Global config key unset: $key"
                continue
                ;;
            *) warn "Invalid option."; sleep 1; continue ;;
        esac
        current="$(git config --global --get "$key" 2>/dev/null || true)"
        prompt_value "Enter new value for '$key' [current: ${current:-not set}]" || continue
        value="$REPLY_VALUE"
        [[ -n "$value" ]] || { warn "No value entered; unchanged."; continue; }
        echo "Proposed change: $key = $value"
        prompt_value "Apply this global Git setting? (y/n)" || continue
        [[ "$REPLY_VALUE" =~ ^[Yy]$ ]] || { warn "Not changed."; continue; }
        create_snapshot global_update >/dev/null
        git config --global "$key" "$value"
        success "Updated global setting: $key = $value"
        log "Updated global config: $key=$value"
        log_success "Global config updated: $key=$value"
    done
}

manual_backup() {
    clear
    line
    echo "MANUAL FULL SNAPSHOT BACKUP"
    line
    create_snapshot manual
    log_success "Manual backup created"
    pause_submenu
}

list_backups() {
    local dirs=() d manifest profiles
    clear
    line
    echo "AVAILABLE BACKUP SNAPSHOTS"
    line
    mapfile -t dirs < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r)
    if [[ ${#dirs[@]} -eq 0 ]]; then warn "No snapshots exist yet."; pause_submenu; return; fi
    local i=1
    for d in "${dirs[@]}"; do
        profiles="$(find "$BACKUP_DIR/$d/db" -maxdepth 1 -type f -name '*.conf' -printf '%f ' 2>/dev/null | sed 's/\.conf//g')"
        printf '[%d] %s | profiles: %s\n' "$i" "$d" "${profiles:-none}"
        ((i++)) || true
    done
    pause_submenu
}

restore_backup() {
    local dirs=() d choice index selected ans f
    clear
    line
    echo "RESTORE BACKUP SNAPSHOT"
    line
    mapfile -t dirs < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r)
    if [[ ${#dirs[@]} -eq 0 ]]; then warn "No snapshots exist yet."; pause_submenu; return; fi
    local i=1
    for d in "${dirs[@]}"; do echo "[$i] $d"; ((i++)) || true; done
    echo "[b] Back"; echo "[x] Exit"
    read -r -p "Select snapshot: " choice
    case "${choice,,}" in b|back) return;; x|exit) confirm_exit; return;; esac
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#dirs[@]} )); then warn "Invalid selection."; pause_submenu; return; fi
    selected="$BACKUP_DIR/${dirs[$((choice-1))]}"
    echo "Selected: $selected"
    echo "SSH private/public keys are never restored or changed by this operation."
    prompt_value "Restore Git config files from this snapshot? (y/n)" || return
    [[ "$REPLY_VALUE" =~ ^[Yy]$ ]] || { warn "Restore cancelled."; return; }
    create_snapshot before_restore >/dev/null
    [[ -f "$selected/gitconfig" ]] && cp -p "$selected/gitconfig" "$HOME/.gitconfig" || rm -f "$HOME/.gitconfig"
    shopt -s nullglob
    for f in "$HOME"/.gitconfig-*; do rm -f "$f"; done
    for f in "$selected/profile-configs"/.gitconfig-*; do cp -p "$f" "$HOME/"; done
    shopt -u nullglob
    success "Restored global and profile Git config files."
    prompt_value "Also restore the saved profile database to match this snapshot? (y/n)" || return
    if [[ "$REPLY_VALUE" =~ ^[Yy$ ]]; then
        rm -f "$DB_DIR"/*.conf
        shopt -s nullglob
        for f in "$selected/db"/*.conf; do cp -p "$f" "$DB_DIR/"; done
        shopt -u nullglob
        success "Restored profile database."
    else
        warn "Profile database was left unchanged."
    fi
    log "Restored snapshot: $selected"
    log_success "Backup restored: $selected"
    pause_submenu
}

main_menu() {
    local choice profile_count
    while true; do
        clear
        profile_count="$(list_profiles | wc -l | tr -d ' ')"
        line
        echo "GIT CONFIGURATION PROFILE MANAGER (WSL/Linux)"
        line
        echo "State folder: $APP_DIR"
        echo "Saved profiles: $profile_count"
        echo
        echo "  [1] Manage Git profiles (add/edit/remove/review)"
        echo "  [2] Manage global Git configuration"
        echo "  [3] Create a full configuration backup"
        echo "  [4] List backup snapshots"
        echo "  [5] Restore a backup snapshot"
        echo "  [6] Exit"
        line
        read -r -p "Select an option [1-6]: " choice
        case "$choice" in
            1) profile_wizard ;;
            2) manage_global_config ;;
            3) manual_backup ;;
            4) list_backups ;;
            5) restore_backup ;;
            6) log "Normal script exit"; echo "Goodbye."; exit 0 ;;
            *) warn "Invalid option. Please choose 1 through 6."; sleep 1 ;;
        esac
    done
}

if [[ ! -d "$DB_DIR" || -z "$(list_profiles)" ]]; then
    printf '%b%s%b\n' "$BOLD$YELLOW" 'WARNING: No previous profile database was found. Starting fresh setup.' "$RESET"
    log "No prior profiles found; initial setup state"
    sleep 2
fi

main_menu