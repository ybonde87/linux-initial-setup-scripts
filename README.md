# 🚀 Developer Environment Setup Toolkit

> One toolkit to build, configure, and manage your Linux dev shell — from zero install to fully personalized Zsh + Powerlevel10k. 🐧✨

This collection turns a **fresh Linux machine** into a polished developer workstation with just a few commands. It bundles an automated installer plus the config files and interactive tools that make up your daily driver. 🛠️👇

---

## 📁 What's Inside

| File | Type | Purpose |
|------|------|---------|
| `setup-dev-environment.sh` | ⚙️ **Installer** | Automates package installs, fonts, config copy & default shell |
| `.zshrc` | 🧬 **Config** | Main Zsh configuration — themes, plugins, aliases |
| `.p10k.zsh` | 🎨 **Theme** | Powerlevel10k prompt styling (colors, icons, git status) |
| `install_project_nav.sh` | 🗂️ **Tool installer** | Installs the interactive project navigation helper |
| `git-profile-manager-v2.sh` | 🔑 **Interactive tool** | Manage GitLab identities & SSH keys per project |

---

## 1️⃣ ⚙️ `setup-dev-environment.sh` — The All-in-One Installer

The heart of the toolkit. It does everything automatically so you never have to manually juggle packages and config files again. 🤖

### ✅ What it does
- 🔍 **Detects your OS & package manager** (Debian/Ubuntu *or* RHEL/Fedora/CentOS).
- 📦 **Installs required packages** — `zsh`, `git`, and `gh` (GitHub CLI) if missing.
- 🎨 **Installs fonts** so Powerlevel10k icons & emoji render correctly (`fonts-powerline` + `fonts-noto-color-emoji`).
- 👤 **Optionally sets zsh as your default login shell** via `chsh` (with a `/etc/passwd` fallback).
- 📄 **Copies `.zshrc` and `.p10k.zsh` into `$HOME`**, backing up any existing versions first.
- 🔧 **Makes the two interactive tools executable** in its own directory (doesn't run them — you do that manually).
- ✅ **Verifies everything** at the end with a clear pass/fail summary.

### 🎯 Usage & Flags
```bash
sudo ./setup-dev-environment.sh                 # Full install 🔥
sudo ./setup-dev-environment.sh --dry-run       # Preview only, no changes 👀
sudo ./setup-dev-environment.sh --config-dir /path/to/files   # Point at a different folder
sudo ./setup-dev-environment.sh --no-default-shell  # Skip the chsh step
sudo ./setup-dev-environment.sh --skip-packages    # Only copy configs/tools
