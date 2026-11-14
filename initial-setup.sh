#!/usr/bin/env bash
# =============================================================================
# setup-dev-environment.sh  —  one-shot installer for a Zsh + Powerlevel10k dev
# shell environment, plus your two interactive tools and zsh-as-default-shell.
#
# What it does automatically:
#   1. Detects the OS / package manager (Debian/Ubuntu or RHEL/Fedora/CentOS…).
#   2. Installs required packages if missing: zsh, git, gh (GitHub CLI).
#   3. Installs fonts so Powerlevel10k icons & emoji render correctly.
#   4. Optionally makes zsh your default login shell (needs root).
#   5. Copies .zshrc / .p10k.zsh into $HOME, backing up existing versions first.
#   6. Makes install_project_nav.sh and git-profile-manager-v2.sh executable in
#      the SAME directory as this script (they are NOT run here — each has its
#      own interactive installer).
#
# Usage:
#   sudo ./setup-dev-environment.sh                 # full install
#   sudo ./setup-dev-environment.sh --dry-run       # preview only, no changes
#   sudo ./setup-dev-environment.sh --config-dir /path/to/files
#   sudo ./setup-dev-environment.sh --no-default-shell
#   sudo ./setup-dev-environment.sh --skip-packages  # only copy configs/tools
#   sudo ./setup-dev-environment.sh -h              # help
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SRC_DIR="${CONFIG_DIR:-.}"          # where p10k.zsh / zshrc live on disk
SKIP_PACKAGES=0
SET_DEFAULT_SHELL=1                 # set via --no-default-shell to disable
DRY_RUN=0                           # set via --dry-run

PKG_MANAGER=""                      # apt | dnf | yum | microdnf | none
OS_FAMILY=""                        # debian | rhel | unknown
APT_UPDATED=0

# --------------------------------------------------------------------------- #
# Output helpers (colour aware, respects NO_COLOR)
# --------------------------------------------------------------------------- #
if [[ -t 2 && "${NO_COLOR:-}" != "1" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_CYAN=$'\033[96m'
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

log()    { printf '%s\n' "$*"; }
info()   { printf '%b%s%b\n' "$C_CYAN" "$*" "$C_RESET"; }
success(){ printf '%b%s%b\n' "$C_GREEN" "$*" "$C_RESET"; }
warn()   { printf '%b%s%b\n' "$C_YELLOW" "$*" "$C_RESET"; }
error()  { printf '%b%s%b\n' "$C_RED" "$*" "$C_RESET" >&2; }

hr() { printf '%s\n' "------------------------------------------------------------------------"; }

usage() {
  cat <<EOF
Usage: sudo ${SCRIPT_NAME} [options]

Options:
  -h, --help                 Show this help and exit.
      --config-dir DIR       Directory containing p10k.zsh / zshrc (default: .).
      --no-default-shell     Skip changing the default shell to zsh.
      --skip-packages        Skip package & font installation; only copy files/tools.
      --dry-run              Preview every action without making any changes.
EOF
}

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)                 usage; exit 0 ;;
    --config-dir)              [[ $# -ge 2 ]] || { error "missing argument for --config-dir"; usage; exit 1; }; SRC_DIR="$2"; shift ;;
    --no-default-shell)        SET_DEFAULT_SHELL=0; shift ;;
    --skip-packages)           SKIP_PACKAGES=1; shift ;;
    --dry-run)                 DRY_RUN=1; shift ;;
    *)                         error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# --------------------------------------------------------------------------- #
# Run a command, or just log it when in dry-run mode.
# This is the single choke-point that makes --dry-run safe and simple.
# --------------------------------------------------------------------------- #
exec_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    info "[dry-run] Would run: $*"
    return 0
  fi
  "$@"
}

# --------------------------------------------------------------------------- #
# OS / package-manager detection
# --------------------------------------------------------------------------- #
detect_os_family() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "$ID" in
      ubuntu|debian|linuxmint|pop|elementary|raspbian|kali) OS_FAMILY="debian";;
      fedora|rhel|centos|rocky|almalinux|ol|amzn|scientific|virtuaux|openEuler) OS_FAMILY="rhel";;
      *) OS_FAMILY="unknown";;
    esac
  else
    OS_FAMILY="unknown"
  fi
  PKG_MANAGER_FAMILY="$OS_FAMILY"   # keep in sync with is_pkg_installed()
}

detect_package_manager() {
  if   command -v apt-get >/dev/null 2>&1; then PKG_MANAGER="apt"
  elif command -v dnf     >/dev/null 2>&1; then PKG_MANAGER="dnf"
  elif command -v microdnf>/dev/null 2>&1; then PKG_MANAGER="microdnf"
  elif command -v yum     >/dev/null 2>&1; then PKG_MANAGER="yum"
  else PKG_MANAGER="none"
  fi
}

# --------------------------------------------------------------------------- #
# Package helpers (idempotent)
# --------------------------------------------------------------------------- #
is_pkg_installed() {
  local pkg="$1" status=""
  case "$PKG_MANAGER_FAMILY" in
    debian) status="$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)" ;;
    rhel)   status="$(rpm -q "$pkg" 2>/dev/null && echo installed || true)" ;;
    *)      return 1 ;;
  esac
  case "$status" in
    *installed*) return 0 ;;
    *)           return 1 ;;
  esac
}

install_one() {
  local pkg="$1"
  info "Installing ${C_BOLD}${pkg}${C_RESET}"
  case "$PKG_MANAGER" in
    apt)      exec_cmd sudo apt-get install -y "$pkg" ;;
    dnf)      exec_cmd sudo dnf install -y "$pkg" ;;
    yum)      exec_cmd sudo yum install -y "$pkg" ;;
    microdnf) exec_cmd sudo microdnf install -y "$pkg" ;;
  esac
}

# --------------------------------------------------------------------------- #
# Fonts for Powerlevel10k (box-drawing glyphs + emoji)
# --------------------------------------------------------------------------- #
install_fonts() {
  info "Checking fonts..."
  local pkgs=()
  case "$OS_FAMILY" in
    debian) pkgs=(fonts-powerline fonts-noto-color-emoji) ;;
    rhel)   pkgs=(powerline-fonts) ;;
    *)      return 0 ;;
  esac
  for f in "${pkgs[@]}"; do
    if is_pkg_installed "$f"; then
      info "Font package already installed: ${C_BOLD}${f}${C_RESET}"
    else
      install_one "$f"
    fi
  done
}

# --------------------------------------------------------------------------- #
# Install required packages (zsh, git, gh)
# --------------------------------------------------------------------------- #
install_dependencies() {
  local pkgs=(zsh git gh) p
  for p in "${pkgs[@]}"; do
    if is_pkg_installed "$p"; then
      info "Already installed: ${C_BOLD}${p}${C_RESET}"
    else
      if [[ "$PKG_MANAGER" == apt && "$APT_UPDATED" != "1" ]]; then
        info "Updating apt package lists..."
        if exec_cmd sudo apt-get update -y; then APT_UPDATED=1
        else warn "[dry-run] Would run 'sudo apt-get update' (skipped)"; fi
      fi
      install_one "$p"
    fi
  done
}

# --------------------------------------------------------------------------- #
# Make zsh the default login shell (requires root in real mode; previewable)
# --------------------------------------------------------------------------- #
set_default_shell() {
  if [[ "$DRY_RUN" != "1" && $EUID -ne 0 ]]; then
    warn "Setting the default shell requires root; skipping."
    return 0
  fi
  local user uid newshell tmp shown
  user="$(id -un)"
  uid="$(id -u "$user")"
  newshell="$(command -v zsh || true)"
  if [[ -z "$newshell" ]]; then
    warn "zsh is not installed yet; skipping default-shell change."
    return 0
  fi

  # Preferred: chsh (NSS-aware, handles the entry cleanly)
  if command -v chsh >/dev/null 2>&1; then
    info "Setting default shell for '$user' to zsh via chsh..."
    if exec_cmd chsh -s "$newshell" "$user"; then
      success "Default shell updated to zsh."
      return 0
    else
      warn "chsh failed; falling back to editing /etc/passwd."
    fi
  fi

  # Fallback: rewrite only the shell field (field 7) for this uid in /etc/passwd
  tmp="$(mktemp)"
  awk -F: -v u="$uid" -v s="$newshell" 'BEGIN{OFS=":"} $3==u{$7=s} {print}' /etc/passwd > "$tmp" \
    && exec_cmd cat "$tmp" > /etc/passwd || { rm -f "$tmp"; error "Failed to update /etc/passwd."; return 1; }
  rm -f "$tmp"

  shown="$(getent passwd "$user" | cut -d: -f7)"
  if [[ "$shown" == "$newshell" ]]; then
    success "Default shell for '$user' is now zsh."
  else
    warn "Could not confirm the /etc/passwd change (field 7 = '${shown:-?}'). Try 'chsh -s $(command -v zsh) $user' manually."
  fi
}

# --------------------------------------------------------------------------- #
# Copy config files into $HOME (with backup of existing versions)
# --------------------------------------------------------------------------- #
copy_config_file() {
  local src="$1" dest="$2" label="$3"
  if [[ ! -f "$src" ]]; then
    error "Config file not found in ${SRC_DIR}/: ${label}"
    return 1
  fi
  local backup=""
  if [[ -e "$dest" ]]; then
    backup="${dest}.bak.$(date +%Y%m%d_%H%M%S)"
    exec_cmd cp -p "$dest" "$backup"
    info "Backed up existing ${label} -> ${backup}"
  fi
  exec_cmd cp "$src" "$dest"
  if [[ "$DRY_RUN" == "1" ]]; then
    info "[dry-run] Would install ${label} -> ${dest}"
    [[ -n "$backup" ]] && info "[dry-run]   (existing version would be backed up to $backup)"
  else
    success "Installed ${label} -> ${dest}"
    [[ -n "$backup" ]] && log "        (previous version saved to $backup)"
  fi
}

copy_configs() {
  info "Copying configuration files..."
  if ! copy_config_file "${SRC_DIR}/zshrc"      "$HOME/.zshrc"       "zshrc"; then return 1; fi
  if ! copy_config_file "${SRC_DIR}/p10k.zsh"   "$HOME/.p10k.zsh"    "p10k.zsh"; then return 1; fi

  # .zshrc sources $HOME/.local/bin/env — make sure it exists so the login shell
  # doesn't error out.
  local env_file="$HOME/.local/bin/env"
  mkdir -p "$HOME/.local/bin"
  if [[ ! -f "$env_file" ]]; then
    info "[dry-run] Would create empty ${env_file} (sourced by .zshrc)."
    exec_cmd : > "$env_file"
    success "Created empty ${env_file} (sourced by .zshrc)."
  fi
}

# --------------------------------------------------------------------------- #
# Make the two interactive tools executable in THIS script's directory.
# They are NOT run here — each has its own interactive installer.
# --------------------------------------------------------------------------- #
place_tools() {
  info "Preparing interactive tools..."
  local tool
  for tool in install_project_nav.sh git-profile-manager-v2.sh; do
    if [[ -f "${SCRIPT_DIR}/${tool}" ]]; then
      exec_cmd chmod +x "${SCRIPT_DIR}/${tool}"
      if [[ "$DRY_RUN" == "1" ]]; then
        info "[dry-run] Would make ${tool} executable -> ${SCRIPT_DIR}/"
      else
        success "Made ${tool} executable -> ${SCRIPT_DIR}/"
      fi
    else
      warn "Not found next to this script: ${SCRIPT_DIR}/${tool}"
    fi
  done
}

# --------------------------------------------------------------------------- #
# Verification
# --------------------------------------------------------------------------- #
verify() {
  info "Verifying installation..."
  local ok=0 fail=0 check f theme_dir="$HOME/.local/share/zsh/themes/powerlevel10k"
  for check in zsh git gh; do
    if command -v "$check" >/dev/null 2>&1; then success "zsh/git/gh: present ($(command -v "$check"))"; ok=$((ok + 1))
    else error "zsh/git/gh: NOT FOUND"; fail=$((fail + 1)); fi
  done
  for f in "$HOME/.zshrc" "$HOME/.p10k.zsh"; do
    if [[ -f "$f" ]]; then success "config present: $f"; ok=$((ok + 1))
    else error "config missing: $f"; fail=$((fail + 1)); fi
  done
  if [[ -d "$theme_dir" ]]; then
    success "Powerlevel10k theme found at ${theme_dir}"
  else
    warn "Powerlevel10k theme not present yet. Your .zshrc installs it via zinit on first prompt load (needs network)."
    echo "       Or pre-install with: gh repo clone romkatv/powerlevel10k ~/.local/share/zsh/themes"
  fi
  hr
  info "Checks passed: ${C_GREEN}${ok}${C_RESET}   failed: ${C_RED}${fail}${C_RESET}"
  hr
}

# --------------------------------------------------------------------------- #
# Next steps / summary
# --------------------------------------------------------------------------- #
print_next_steps() {
  hr; info "NEXT STEPS"; hr
  echo "1. Open a NEW terminal (or run 'exec zsh') to load the new .zshrc."
  echo ""
  if [[ "$OS_FAMILY" == rhel ]]; then
    echo "2. Refresh font cache: sudo fc-cache -f && systemctl restart gdm   # GNOME/Fontconfig only"
  fi
  echo "3. zsh is now your default login shell (new sessions use it)."
  echo ""
  echo "Interactive tools — run these MANUALLY later from this directory:"
  echo "       ${SCRIPT_DIR}/install_project_nav.sh     # project navigation + auto 'git pull'"
  echo "       ${SCRIPT_DIR}/git-profile-manager-v2.sh  # manage GitLab profiles & SSH keys"
  hr
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
main() {
  detect_os_family
  detect_package_manager

  info "${C_BOLD}${SCRIPT_NAME}${C_RESET}"
  info "Detected OS family : ${OS_FAMILY:-unknown}"
  info "Package manager    : ${PKG_MANAGER:-none}"

  if [[ "$DRY_RUN" == "1" ]]; then
    warn "${C_BOLD}DRY-RUN MODE${C_RESET} — no changes will be made. Reviewing actions below."
  fi
  if [[ "$SKIP_PACKAGES" == "1" ]]; then
    warn "Skipping package/font installation (--skip-packages)."
  fi

  # If we're not skipping packages, a missing package manager is fatal.
  if [[ "$SKIP_PACKAGES" != "1" && "$PKG_MANAGER" == "none" ]]; then
    error "No supported package manager found (apt/dnf/yum/microdnf); cannot install zsh/git/gh."
  fi

  # Step 1: packages + fonts (unless skipped)
  if [[ "$SKIP_PACKAGES" != "1" ]]; then
    install_dependencies
    install_fonts
  else
    info "Assuming zsh/git/gh are already installed."
  fi

  # Step 2: default shell (needs root in real mode; previewable without it)
  set_default_shell

  # Step 3: copy configs
  copy_configs || { error "Failed to copy configuration files."; exit 1; }

  # Step 4: make interactive tools executable in this directory
  place_tools

  # Step 5: verify + next steps
  verify
  print_next_steps
}

main "$@"
