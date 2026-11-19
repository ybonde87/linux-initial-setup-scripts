# 🚀 Developer Environment Setup Toolkit

> A Linux workstation toolkit for setting up Zsh, navigating projects, and managing separate Git identities. 🐧✨

This repository turns a fresh Linux, WSL, or distro environment into a personalized developer workspace. It includes an automated Zsh installer plus interactive tools for project navigation and GitLab profile management. 🛠️

---

## 📁 Repository Structure

| Folder | Contents | Purpose |
| --- | --- | --- |
| [`Linux-Initial-Setup/`](Linux-Initial-Setup/) | `initial-setup.sh`, `.zshrc`, `.p10k.zsh` | Installs Zsh, common developer packages, fonts, shell configuration, and Powerlevel10k |
| [`Git-Project-Navigation/`](Git-Project-Navigation/) | `install_project_nav_v2.sh` | Installs fast project-jumping commands and Git repository sync helpers |
| [`Git-Profile-Manager/`](Git-Profile-Manager/) | `git-profile-manager-v3.sh` | Manages per-project Git identities and SSH keys |

---

## 1️⃣ ⚙️ Linux Initial Setup

This is the main setup script. It automates the boring parts so you can focus on building instead of managing shell configuration.
[`initial-setup.sh`](Linux-Initial-Setup/initial-setup.sh) prepares a Zsh + Powerlevel10k development shell.

### ✅ What it does

- Detects Debian/Ubuntu or RHEL/Fedora family distributions
- Detects `apt`, `dnf`, `microdnf`, or `yum`
- Installs `zsh`, `git`, `gh`, and supported Powerlevel10k font packages
- Optionally changes the current user's login shell to Zsh
- Copies `.zshrc` and `.p10k.zsh` into the target user's home directory
- Backs up existing `.zshrc` and `.p10k.zsh` with timestamped `.bak.YYYYMMDD_HHMMSS` files
- Creates `~/.local/bin/env` for compatibility with the included Zsh configuration
- Verifies installed commands and configuration files

### 🚀 Usage

Run from inside `Linux-Initial-Setup/`:

```bash
./initial-setup.sh --dry-run
./initial-setup.sh
./initial-setup.sh --no-default-shell
./initial-setup.sh --skip-packages
./initial-setup.sh --config-dir /path/to/configs
```

The script invokes `sudo` internally when needed. It can run as a normal user, and when called through `sudo`, it resolves the target account from `SUDO_USER`.

Full details: [`Linux-Initial-Setup/README.md`](Linux-Initial-Setup/README.md)

---

## 2️⃣ 🧬 Zsh and Powerlevel10k Configuration

The Linux setup folder contains:

- [`.zshrc`](Linux-Initial-Setup/.zshrc) — Zinit plugin loading, shell history, completion, useful aliases, SSH-agent reuse, and private secrets support
- [`.p10k.zsh`](Linux-Initial-Setup/.p10k.zsh) — colorful Rainbow-style Powerlevel10k prompt settings

On first Zsh startup, Zinit is cloned automatically and Powerlevel10k plus the configured plugins are loaded.

---

## 3️⃣ 🗂️ Project Navigation

This script writes the project navigation helper to your Zsh config directory and sets up quick project switching.
[`install_project_nav_v2.sh`](Git-Project-Navigation/install_project_nav_v2.sh) installs `~/.config/zsh/project_nav_v2.zsh`, checks its syntax when zsh is available, and adds it to `~/.zshrc`.

```bash
cd Git-Project-Navigation
bash install_project_nav_v2.sh
exec zsh
```

It adds commands such as:

```bash
proj acme emea tgw
proj -
proj-sync-all
proj-scan ~/projects
proj-doctor
proj-add acme emea tgw ~/projects/acme/emea/tgw
proj-clone git@gitlab.com:group-org/platform/services/region/sample-repo.git
proj-url-key git@gitlab.com:group-org/platform/services/region/sample-repo.git
proj-clone-into ~/projects/acme/emea git@gitlab.com:acme/emea/tgw-repo.git acme emea tgw
```

Full command and configuration details: [`Git-Project-Navigation/README.md`](Git-Project-Navigation/README.md)

---

## 4️⃣ 🔑 Git Profile Manager

[`git-profile-manager-v3.sh`](Git-Profile-Manager/git-profile-manager-v3.sh) lets you maintain separate Git identities and SSH keys.

```bash
cd Git-Profile-Manager
chmod +x git-profile-manager-v3.sh
./git-profile-manager-v3.sh
```

It can add or edit profiles, generate Ed25519 SSH keys, configure Git `includeIf` routing, create configuration snapshots, restore backups, and test SSH authentication.

Full usage: [`Git-Profile-Manager/Readme.md`](Git-Profile-Manager/Readme.md)

---

## 🚦 Recommended Setup

```bash
# 1. Preview the Linux setup
cd Linux-Initial-Setup
./initial-setup.sh --dry-run

# 2. Apply the Linux and Zsh setup
./initial-setup.sh

# 3. Install project navigation
cd ../Git-Project-Navigation
bash install_project_nav_v2.sh

# 4. Start Zsh
exec zsh

# 5. Optionally configure separate Git identities
cd ../Git-Profile-Manager
./git-profile-manager-v3.sh
```

---

## 💡 Notes and Tips

- Re-running scripts that support it is generally safe; installers create backups before replacing configuration.
- Run `--dry-run` before the Linux setup to inspect actions without changing the machine.
- Powerlevel10k icons require a compatible Nerd or Powerline font and an emoji font.
- Zsh loads private settings from `~/.zsh_secrets` if that file exists; do not commit secrets to this repository.
- Use `p10k configure` to personalize the prompt after setup.
- Open a new terminal or run `exec zsh` after changing shell configuration.

Built for developers who want a beautiful, powerful shell without the manual grunt work. 💻🚀
