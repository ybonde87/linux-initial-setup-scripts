#!/usr/bin/env bash
# =============================================================================
# initial-setup.sh  —  one-shot installer for a Zsh + Powerlevel10k dev shell
# environment, plus your two interactive tools and zsh-as-default-shell.
#
# What it does:
#   1. Detects the OS / package manager (Debian/Ubuntu or RHEL/Fedora/CentOS…).
#   2. Installs required packages if missing: zsh, git, gh (GitHub CLI).
#   3. Installs fonts so Powerlevel10k icons & emoji render correctly.
#   4. Optionally makes zsh your default login shell.
#   5. Copies .zshrc / .p10k.zsh (or zshrc / p10k.zsh) into your home,
#      backing up existing versions first.
#   6. Makes install_project_nav.sh and git-profile-manager-v2.sh executable in
#      the SAME directory as this script (they are NOT run here).
#
# Usage (run as your NORMAL user; sudo is called internally when needed):
#   ./initial-setup.sh                   # full install
#   ./initial-setup.sh --dry-run         # preview only, no changes
#   ./initial-setup.sh --config-dir /path/to/files
#   ./initial-setup.sh --no-default-shell
#   ./initial-setup.sh --skip-packages   # only copy configs/tools
#   ./initial-setup.sh -h                # help
# (Running via 'sudo ./initial-setup.sh' also works: files go to $SUDO_USER's home.)
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_NAME="$(basename -- "${BASH_SOURCE[0]}")"
SRC_DIR="${CONFIG_DIR:-$SCRIPT_DIR}"   # where .zshrc / .p10k.zsh live
SKIP_PACKAGES=0
SET_DEFAULT_SHELL=1                    # --no-default-shell disables
DRY_RUN=0                              # --dry-run enables

PKG_MANAGER=""                         # apt | dnf | yum | microdnf | none
PKG_MANAGER_FAMILY=""                  # debian | rhel | unknown
OS_FAMILY=""                           # debian | rhel | unknown
APT_UPDATED=0

# Resolve the real (non-root) target user and their home directory.
TARGET_USER="${SUDO_USER:-$(id -un)}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
TARGET_HOME="${TARGET_HOME:-$HOME}"

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
Usage: ${SCRIPT_NAME} [options]

Run as your normal user; sudo is invoked internally where required.

Options:
  -h, --help                 Show this help and exit.
      --config-dir DIR       Directory containing .zshrc / .p10k.zsh
                             (default: the directory of this script).
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
    -h|--help)          usage; exit 0 ;;
    --config-dir)       [[ $# -ge 2 ]] || { error "missing argument for --config-dir"; usage; exit 1; }
                        SRC_DIR="$2"; shift 2 ;;
    --no-default-shell) SET_DEFAULT_SHELL=0; shift ;;
    --skip-packages)    SKIP_PACKAGES=1; shift ;;
    --dry-run)          DRY_RUN=1; shift ;;
    *)                  error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# --------------------------------------------------------------------------- #
# Command wrappers. exec_cmd is the single choke-point for --dry-run.
# NOTE: never put redirections outside exec_cmd; use exec_cmd bash -c '...'.
# --------------------------------------------------------------------------- #
exec_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    info "[dry-run] Would run: $*"
    return 0
  fi
  "$@"
}

# Run with root privileges (no sudo needed if already root).
as_root() {
  if [[ $EUID -eq 0 ]]; then exec_cmd "$@"; else exec_cmd sudo "$@"; fi
}

# --------------------------------------------------------------------------- #
# OS / package-manager detection
# --------------------------------------------------------------------------- #
detect_os_family() {
  OS_FAMILY="unknown"
  if [[ -f /etc/os-release ]]; then
    local id like
    id="$(. /etc/os-release; echo "${ID:-}")"
    like="$(. /etc/os-release; echo "${ID_LIKE:-}")"
    case "$id" in
      ubuntu|debian|linuxmint|pop|elementary|raspbian|kali) OS_FAMILY="debian" ;;
      fedora|rhel|centos|rocky|almalinux|ol|amzn|scientific|virtuaux|openEuler) OS_FAMILY="rhel" ;;
      *)
        case " $like " in
          *" debian "*|*" ubuntu "*) OS_FAMILY="debian" ;;
          *" rhel "*|*" fedora "*|*" centos "*) OS_FAMILY="rhel" ;;
        esac ;;
    esac
  fi
  PKG_MANAGER_FAMILY="$OS_FAMILY"
}

detect_package_manager() {
  if   command -v apt-get  >/dev/null 2>&1; then PKG_MANAGER="apt"
  elif command -v dnf      >/dev/null 2>&1; then PKG_MANAGER="dnf"
  elif command -v microdnf >/dev/null 2>&1; then PKG_MANAGER="microdnf"
  elif command -v yum      >/dev/null 2>&1; then PKG_MANAGER="yum"
  else PKG_MANAGER="none"
  fi
}

# --------------------------------------------------------------------------- #
# Package helpers (idempotent)
# --------------------------------------------------------------------------- #
is_pkg_installed() {
  local pkg="$1"
  case "$PKG_MANAGER_FAMILY" in
    debian) dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" ;;
    rhel)   rpm -q "$pkg" >/dev/null 2>&1 ;;
    *)      return 1 ;;
  esac
}

install_one() {
  local pkg="$1"
  info "Installing ${C_BOLD}${pkg}${C_RESET}"
  case "$PKG_MANAGER" in
    apt)      as_root apt-get install -y "$pkg" ;;
    dnf)      as_root dnf install -y "$pkg" ;;
    yum)      as_root yum install -y "$pkg" ;;
    microdnf) as_root microdnf install -y "$pkg" ;;
    *)        return 1 ;;
  esac
}

# Add GitHub's official apt repo if 'gh' isn't available in the default repos.
ensure_gh_repo_apt() {
  if apt-cache show gh >/dev/null 2>&1; then return 0; fi
  info "gh not in default repos; adding GitHub CLI apt repository..."
  as_root mkdir -p -m 755 /etc/apt/keyrings
  as_root bash -c 'curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg'
  as_root bash -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list'
  as_root apt-get update -y
}

# --------------------------------------------------------------------------- #
# Fonts for Powerlevel10k (box-drawing glyphs + emoji)
# --------------------------------------------------------------------------- #
install_fonts() {
  info "Checking fonts..."
  local pkgs=() f
  case "$OS_FAMILY" in
    debian) pkgs=(fonts-powerline fonts-noto-color-emoji) ;;
    rhel)   pkgs=(powerline-fonts) ;;
    *)      return 0 ;;
  esac
  for f in "${pkgs[@]}"; do
    if is_pkg_installed "$f"; then
      info "Font package already installed: ${C_BOLD}${f}${C_RESET}"
    elif ! install_one "$f"; then
      warn "Could not install font package '${f}'; continuing."
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
      continue
    fi
    if [[ "$PKG_MANAGER" == apt && "$APT_UPDATED" != "1" ]]; then
      info "Updating apt package lists..."
      if as_root apt-get update -y; then
        APT_UPDATED=1
      else
        warn "apt-get update failed; package installs may fail."
      fi
    fi
    if [[ "$p" == "gh" && "$PKG_MANAGER" == apt ]]; then
      ensure_gh_repo_apt || warn "Could not add GitHub CLI repo."
    fi
    if ! install_one "$p"; then
      if [[ "$p" == "gh" ]]; then
        warn "Could not install gh. See https://github.com/cli/cli#installation (continuing)."
      else
        error "Failed to install required package: $p"
        exit 1
      fi
    fi
  done
}

# --------------------------------------------------------------------------- #
# Make zsh the default login shell (chsh only; no /etc/passwd editing)
# --------------------------------------------------------------------------- #
set_default_shell() {
  local newshell
  newshell="$(command -v zsh || true)"
  if [[ -z "$newshell" ]]; then
    warn "zsh is not installed yet; skipping default-shell change."
    return 0
  fi
  if ! command -v chsh >/dev/null 2>&1; then
    warn "chsh not found; run manually: chsh -s ${newshell}"
    return 0
  fi
  if [[ "$(getent passwd "$TARGET_USER" | cut -d: -f7)" == "$newshell" ]]; then
    info "zsh is already the default shell for '${TARGET_USER}'."
    return 0
  fi
  if ! grep -qxF "$newshell" /etc/shells 2>/dev/null; then
    info "Adding ${newshell} to /etc/shells..."
    as_root bash -c "echo '$newshell' >> /etc/shells"
  fi
  info "Setting default shell for '${TARGET_USER}' to zsh via chsh..."
  if as_root chsh -s "$newshell" "$TARGET_USER"; then
    success "Default shell updated to zsh (applies to new sessions)."
  else
    warn "chsh failed. Try manually: sudo chsh -s ${newshell} ${TARGET_USER}"
  fi
}

# --------------------------------------------------------------------------- #
# Copy config files into the target home (with backup of existing versions)
# --------------------------------------------------------------------------- #
fix_owner() {
  if [[ $EUID -eq 0 && "$TARGET_USER" != "root" ]]; then
    exec_cmd chown "$TARGET_USER": "$@"
  fi
}

# Find a config file in SRC_DIR, accepting either ".name" or "name".
find_src() {
  local base="$1" cand
  for cand in "${SRC_DIR}/.${base}" "${SRC_DIR}/${base}"; do
    if [[ -f "$cand" ]]; then printf '%s\n' "$cand"; return 0; fi
  done
  printf '%s\n' "${SRC_DIR}/.${base}"   # fallback so the error names a real path
}

copy_config_file() {
  local src="$1" dest="$2" label="$3"
  if [[ ! -f "$src" ]]; then
    error "Config file not found: ${src} (${label})"
    return 1
  fi
  local backup=""
  if [[ -e "$dest" ]]; then
    backup="${dest}.bak.$(date +%Y%m%d_%H%M%S)"
    exec_cmd cp -p "$dest" "$backup"
    info "Backed up existing ${label} -> ${backup}"
  fi
  exec_cmd cp "$src" "$dest"
  fix_owner "$dest"
  if [[ "$DRY_RUN" == "1" ]]; then
    info "[dry-run] Would install ${label} -> ${dest}"
  else
    success "Installed ${label} -> ${dest}"
    if [[ -n "$backup" ]]; then log "        (previous version saved to $backup)"; fi
  fi
}

copy_configs() {
  info "Copying configuration files..."
  copy_config_file "$(find_src zshrc)"    "${TARGET_HOME}/.zshrc"    "zshrc"    || return 1
  copy_config_file "$(find_src p10k.zsh)" "${TARGET_HOME}/.p10k.zsh" "p10k.zsh" || return 1

  # .zshrc sources ~/.local/bin/env — make sure it exists.
  local env_file="${TARGET_HOME}/.local/bin/env"
  exec_cmd mkdir -p "${TARGET_HOME}/.local/bin"
  if [[ ! -f "$env_file" ]]; then
    exec_cmd touch "$env_file"
    fix_owner "${TARGET_HOME}/.local" "${TARGET_HOME}/.local/bin" "$env_file"
    if [[ "$DRY_RUN" == "1" ]]; then
      info "[dry-run] Would create empty ${env_file} (sourced by .zshrc)."
    else
      success "Created empty ${env_file} (sourced by .zshrc)."
    fi
  fi
}

# --------------------------------------------------------------------------- #
# Make the two interactive tools executable in THIS script's directory.
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
  local ok=0 fail=0 check f theme_dir="${TARGET_HOME}/.local/share/zsh/themes/powerlevel10k"
  for check in zsh git gh; do
    if command -v "$check" >/dev/null 2>&1; then
      success "${check}: present ($(command -v "$check"))"; ok=$((ok + 1))
    else
      error "${check}: NOT FOUND"; fail=$((fail + 1))
    fi
  done
  for f in "${TARGET_HOME}/.zshrc" "${TARGET_HOME}/.p10k.zsh"; do
    if [[ -f "$f" ]]; then success "config present: $f"; ok=$((ok + 1))
    else error "config missing: $f"; fail=$((fail + 1)); fi
  done
  if [[ -d "$theme_dir" ]]; then
    success "Powerlevel10k theme found at ${theme_dir}"
  else
    warn "Powerlevel10k theme not present yet. Your .zshrc installs it via zinit on first prompt load (needs network)."
    echo "       Or pre-install with: gh repo clone romkatv/powerlevel10k ~/.local/share/zsh/themes/powerlevel10k"
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
    echo "2. Refresh font cache: sudo fc-cache -f   # then restart your terminal"
  fi
  if [[ "$SET_DEFAULT_SHELL" == "1" ]]; then
    echo "3. zsh is set as your default login shell (new sessions use it;"
    echo "   on WSL, run 'wsl --shutdown' from Windows to fully apply)."
  fi
  echo ""
  echo "Interactive tools — run these MANUALLY later:"
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
  info "Target user / home : ${TARGET_USER} / ${TARGET_HOME}"

  if [[ "$DRY_RUN" == "1" ]]; then
    warn "${C_BOLD}DRY-RUN MODE${C_RESET} — no changes will be made. Reviewing actions below."
  fi
  if [[ "$SKIP_PACKAGES" == "1" ]]; then
    warn "Skipping package/font installation (--skip-packages)."
  fi

  if [[ "$SKIP_PACKAGES" != "1" && "$PKG_MANAGER" == "none" ]]; then
    error "No supported package manager found (apt/dnf/yum/microdnf); cannot install zsh/git/gh."
    exit 1
  fi

  # Step 1: packages + fonts
  if [[ "$SKIP_PACKAGES" != "1" ]]; then
    install_dependencies
    install_fonts
  else
    info "Assuming zsh/git/gh are already installed."
  fi

  # Step 2: default shell
  if [[ "$SET_DEFAULT_SHELL" == "1" ]]; then
    set_default_shell
  else
    info "Skipping default-shell change (--no-default-shell)."
  fi

  # Step 3: copy configs
  copy_configs || { error "Failed to copy configuration files."; exit 1; }

  # Step 4: make interactive tools executable
  place_tools

  # Step 5: verify + next steps
  verify
  print_next_steps
}

main "$@"
