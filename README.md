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

💡 Tip: Run --dry-run first to see exactly what will happen, then run it for real! 🧪

2️⃣ 🧬 .zshrc — Main Zsh Configuration
The master config file that loads everything into your shell session. 🌐

✅ What it does
⚡ Instant prompt — sources Powerlevel10k's instant-prompt cache for snappy rendering.
🔌 Zinit plugin manager — installs Powerlevel10k + core plugins (autosuggestions, syntax highlighting, completions).
🗂️ Sources project_nav.zsh — loads your hierarchical project navigation tool.
📜 History settings — 10,000 entries, shared history, ignores duplicate commands.
🎛️ Completion tuning — case-insensitive matching, menu selection, original sorting preserved.
🔑 Environment & aliases — defines claude-server and run-claude for your local AI server (API keys are commented out as placeholders).
⚠️ Requires the Powerlevel10k theme to be present in $HOME/.local/share/zsh/themes/ (installed automatically by the setup script via zinit on first load). 🎨

3️⃣ 🎨 .p10k.zsh — Powerlevel10k Theme Configuration
Defines how your prompt looks and feels. This is where all the colors, icons, and layout magic lives. ✨

✅ What it does
🌈 Rainbow powerline style with colorful backgrounds and angled separators.
⬅️ Left prompt: current directory + git status (branch name with per-branch emoji like 👑 for main, 🔩 for infra, etc.).
➡️ Right prompt: exit code, command time, background jobs, and a stack of environment indicators — Python (pyenv/virtualenv/conda), Node, Go, Ruby, AWS, Azure, GCP, kubectl context, and more. 🧰
🕒 24h clock that updates on Enter.
📁 Custom directory classes with emoji icons for work/personal/infra/config/SSH/etc directories.
🔧 Custom git formatter (my_git_formatter) showing ahead/behind, stashes, conflicts, and staged/unstaged counts — all with themed colors.
4️⃣ 🗂️ install_project_nav.sh — Project Navigation Installer
An installer that drops in an interactive helper for jumping between your projects. 🧭

✅ What it does
📝 Writes ~/.config/zsh/project_nav.zsh (the actual tool, sourced by .zshrc).
🔒 Backs up any existing broken file before overwriting.
▶️ Is itself interactive — run it to register your projects and configure mappings.
🚀 The proj command (once installed)
bash
proj acme emea tgw     # Jump to a project (case-insensitive, from anywhere) 🎯
proj                   # List all registered projects 📋
proj -                 # Jump back to the previous project ⬅️
proj-sync-all          # Auto 'git pull' every registered repo 🔄
proj-scan <folder>     # Auto-discover & register git repos under a folder 🔎
proj-doctor            # Audit mappings for missing/broken repos 🩺
5️⃣ 🔑 git-profile-manager-v2.sh — GitLab Profile Manager
A menu-driven tool for managing multiple GitLab identities across projects. Perfect for teams who need different names/emails per project. 👥

✅ What it does
🆔 Manages per-project Git identities (user name, email) via includeIf config — profile settings override the global config inside their directories.
🔐 Generates & assigns SSH keys (Ed25519), with a ⚠️ reuse warning if a key is linked to multiple profiles.
🌍 Manages global Git config (user.name, user.email, init.defaultBranch, pull.rebase, core.editor).
💾 Full snapshot backups before every change — restore anytime from a backup folder.
✅ Verifies SSH authentication against your GitLab host after applying each profile.
🎛️ Run it:
bash
./git-profile-manager-v2.sh    # Opens the interactive menu 🔧
🚦 Quick Start (TL;DR)
bash
# 1. Preview what will be installed 👀
sudo ./setup-dev-environment.sh --dry-run

# 2. Apply everything for real 🔥
sudo ./setup-dev-environment.sh

# 3. Open a NEW terminal (or run 'exec zsh') to load your new prompt 🖥️

# 4. Set up project navigation & Git profiles manually — each has its own installer:
./install_project_nav.sh          # Project jumps + auto git pull 🧭
./git-profile-manager-v2.sh       # Multi-identity GitLab management 🔑
💡 Notes & Tips
🔄 Idempotent: Re-running the setup script only installs what's missing and refreshes your config — safe to run anytime.
🎨 Fonts matter: Powerlevel10k needs fonts-powerline (box-drawing glyphs) + an emoji font for icons to render correctly. The installer handles this automatically.
👤 Default shell: After setup, new login shells use zsh. Your current session stays bash until you run exec zsh.
🧪 Customize freely: Edit .p10k.zsh and re-run p10k configure to tweak your prompt anytime.
✨ Built for developers who want a beautiful, powerful shell without the manual grunt work. Happy hacking! 💻🚀

