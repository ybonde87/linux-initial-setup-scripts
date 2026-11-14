# 🚀 Developer Environment Setup Toolkit

> One toolkit to build, configure, and manage your Linux dev shell — from a fresh install to a fully personalized Zsh + Powerlevel10k setup. 🐧✨

This collection turns a fresh Linux machine into a polished developer workstation with just a few commands. It bundles an automated installer, configuration files, and interactive tools for daily development. 🛠️

---

## 📁 What's Inside

| File | Type | Purpose |
| --- | --- | --- |
| `initial-setup.sh` | ⚙️ Installer | Installs packages, config files, fonts, and shell defaults |
| `.zshrc` | 🧬 Configuration | Main Zsh setup with plugins, aliases, and prompt loading |
| `.p10k.zsh` | 🎨 Theme | Powerlevel10k prompt styling, icons, and git indicators |
| `install_project_nav.sh` | 🗂️ Tool installer | Installs the interactive project navigation helper |
| `git-profile-manager-v2.sh` | 🔑 Interactive tool | Manages Git identities and SSH keys per project |

---

## 1️⃣ ⚙️ `initial-setup.sh` — The All-in-One Installer

This is the main setup script. It automates the boring parts so you can focus on building instead of managing shell configuration.

### ✅ What it does

- Detects the OS and package manager (Debian/Ubuntu or RHEL/Fedora/CentOS)
- Installs required packages such as `zsh`, `git`, and `gh` if they are missing
- Installs Powerlevel10k font support so symbols and emoji render correctly
- Optionally sets Zsh as the default login shell via `chsh`
- Copies `.zshrc` and `.p10k.zsh` into `$HOME`, backing up any current versions first
- Makes the interactive helper scripts executable in the project directory
- Verifies the final setup and prints a summary

### 🎯 Usage

```bash
sudo ./initial-setup.sh                 # Full install
sudo ./initial-setup.sh --dry-run       # Preview actions without changing anything
sudo ./initial-setup.sh --config-dir /path/to/files
sudo ./initial-setup.sh --no-default-shell
sudo ./initial-setup.sh --skip-packages
```

> Tip: Run `--dry-run` first to preview exactly what will happen before applying changes.

---

## 2️⃣ 🧬 `.zshrc` — Main Zsh Configuration

This is the master configuration file for the shell. It loads the theme, plugin manager, aliases, and project navigation helper.

### ✅ What it does

- Loads Powerlevel10k's instant prompt cache for faster startup
- Configures Zinit and loads essential plugins such as autosuggestions and syntax highlighting
- Sources `project_nav.zsh` for project jumping and navigation shortcuts
- Sets commonly used shell history and completion behavior
- Defines developer aliases and environment hooks
- Keeps the setup ready for a personalized workstation experience

> This file expects Powerlevel10k to be available in the configured Zsh theme location.

---

## 3️⃣ 🎨 `.p10k.zsh` — Powerlevel10k Theme Configuration

This file controls the visual style of the prompt, including colors, icons, and status indicators.

### ✅ What it does

- Uses a colorful Powerlevel10k rainbow-style prompt
- Shows the current directory and git status in the left prompt
- Displays exit codes, command duration, jobs, and environment indicators in the right prompt
- Adds custom directory icons for work, personal, infra, config, and SSH paths
- Includes a custom git formatter for ahead/behind status, stash state, and staged/unstaged changes
- Keeps the prompt readable and informative while working across repos and environments

---

## 4️⃣ 🗂️ `install_project_nav.sh` — Project Navigation Installer

This installer writes the project navigation helper to your Zsh config directory and sets up quick project switching.

### ✅ What it does

- Writes `~/.config/zsh/project_nav.zsh`
- Backs up any existing broken or outdated configuration before replacing it
- Creates a project mapping file for quick navigation between repos
- Enables project commands such as `proj`, `proj-sync-all`, `proj-scan`, and `proj-doctor`

### Example commands

```bash
proj acme emea tgw     # Jump to a project by name
proj                   # List all registered projects
proj -                 # Jump back to the previous project
proj-sync-all          # Pull latest changes in every registered repo
proj-scan <folder>     # Auto-discover repos under a folder
proj-doctor            # Check for missing or broken project mappings
```

---

## 5️⃣ 🔑 `git-profile-manager-v2.sh` — Git Profile Manager

This helper lets you manage multiple Git identities and SSH keys across projects. It is especially useful for teams that need different names and emails per repository.

### ✅ What it does

- Manages per-project Git identities using `includeIf` config entries
- Keeps global Git settings separate from project-specific overrides
- Generates and assigns SSH keys for GitLab use
- Warns when a key is reused across multiple profiles
- Creates full snapshot backups before making changes
- Verifies SSH authentication after applying a profile

### Run it

```bash
./git-profile-manager-v2.sh
```

---

## 🚦 Quick Start

```bash
# 1) Preview the installer
sudo ./initial-setup.sh --dry-run

# 2) Install the environment
sudo ./initial-setup.sh

# 3) Load your new shell configuration
exec zsh

# 4) Configure the helper tools
./install_project_nav.sh
./git-profile-manager-v2.sh
```

---

## 💡 Notes and Tips

- Re-running the setup script is safe and idempotent
- Powerlevel10k needs the correct font packages for proper icon rendering
- After setup, your current shell may still be bash until you run `exec zsh`
- You can tweak the theme by editing `.p10k.zsh` and re-running `p10k configure`

Built for developers who want a beautiful, powerful shell without the manual grunt work. Happy hacking! 💻🚀
