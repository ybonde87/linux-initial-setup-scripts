# ⚙️ Linux Initial Setup

An automated installer for a Zsh + Powerlevel10k development environment on Debian/Ubuntu and RHEL/Fedora family Linux distributions.

It installs the essential command-line tools, configures Zsh, installs compatible font packages, and prepares the machine for the repository's project navigation and Git profile tools.

---

## 📦 What's Inside

| File | Purpose |
| --- | --- |
| `initial-setup.sh` | Detects the OS and package manager, installs dependencies, copies configuration, sets Zsh as the default shell, and verifies the result |
| `.zshrc` | Zsh startup configuration using Zinit, Powerlevel10k, completion, plugins, aliases, and SSH-agent reuse |
| `.p10k.zsh` | Generated Rainbow-style Powerlevel10k prompt configuration |

---

## 🛠️ Requirements

- Linux or WSL with Bash
- Debian/Ubuntu or RHEL/Fedora/CentOS/Rocky/AlmaLinux family
- `sudo` access for package installation and login-shell changes
- Internet access for package installs and Zinit plugin/theme downloads

The script detects `apt`, `dnf`, `microdnf`, or `yum`. Unsupported distributions stop if package installation is required.

---

## 🚀 Getting Started

Make the installer executable if needed:

```bash
chmod +x initial-setup.sh
```

Preview every action before changing the system:

```bash
./initial-setup.sh --dry-run
```

Run the normal setup:

```bash
./initial-setup.sh
```

The script invokes `sudo` internally as needed. It resolves the target user's home directory from `SUDO_USER` when run with `sudo`.

After it finishes:

```bash
exec zsh
```

Open a new terminal if `chsh` was used so the login-shell change is applied to new sessions.

---

## 🎛️ Command Options

| Option | What it does |
| --- | --- |
| `-h`, `--help` | Displays help |
| `--dry-run` | Prints or describes actions without modifying files or packages |
| `--config-dir DIR` | Uses a custom directory containing `.zshrc` and `.p10k.zsh` |
| `--no-default-shell` | Keeps the existing login shell instead of setting Zsh |
| `--skip-packages` | Skips package and font installation; only copies configuration |

Examples:

```bash
./initial-setup.sh --dry-run
./initial-setup.sh --config-dir "$HOME/my-zsh-config"
./initial-setup.sh --skip-packages --no-default-shell
```

---

## ✅ What the Installer Changes

### Debian/Ubuntu

- Updates `apt` package lists when required
- Installs `zsh`, `git`, and `gh`
- Adds the official GitHub CLI package repository if `gh` is not in the configured repositories
- Installs `fonts-powerline` and `fonts-noto-color-emoji`

### RHEL/Fedora family

- Installs `zsh`, `git`, `gh`, and `powerline-fonts`
- Uses `dnf`, `microdnf`, or `yum` according to availability

Package installation can be skipped with `--skip-packages`.

---

## 🧬 Zsh Configuration

The included `.zshrc`:

- Loads Powerlevel10k instant-prompt cache
- Installs Zinit when Git is available
- Loads Powerlevel10k, completions, autosuggestions, syntax highlighting, and useful Oh My Zsh snippets
- Sources `~/.config/zsh/project_nav.zsh` when the Project Navigation tool is installed
- Configures history, case-insensitive completion, and menu selection
- Sources optional private settings from `~/.zsh_secrets`
- Sources `~/.local/bin/env`
- Reuses an SSH agent across login shells
- Loads private SSH keys automatically for that agent

Keep `~/.zsh_secrets` private and set its permissions if it contains credentials:

```bash
chmod 600 ~/.zsh_secrets
```

---

## 🎨 Powerlevel10k Theme

The `.p10k.zsh` file configures a compact Rainbow-style Powerlevel10k prompt. It includes:

- Directory and Git status indicators
- Command exit status
- Command duration
- Background job count
- Environment indicators for tools such as Python, Node.js, and Go
- Custom folder icons and prompt separators

To reconfigure it interactively:

```bash
p10k configure
```

---

## 💾 Backups

Before replacing an existing Zsh config, the installer creates a timestamped backup:

```text
~/.zshrc.bak.YYYYMMDD_HHMMSS
~/.p10k.zsh.bak.YYYYMMDD_HHMMSS
```

Restore a previous file manually if needed:

```bash
cp ~/.zshrc.bak.YYYYMMDD_HHMMSS ~/.zshrc
cp ~/.p10k.zsh.bak.YYYYMMDD_HHMMSS ~/.p10k.zsh
```

---

## 🧰 Related Tools

### Project Navigation

Install from the sibling folder:

```bash
cd ../Git-Project-Navigation
./install_project_nav.sh
```

Details: [`../Git-Project-Navigation/README.md`](../Git-Project-Navigation/README.md)

### Git Profile Manager

Run from the sibling folder:

```bash
cd ../Git-Profile-Manager
./git-profile-manager-v3.sh
```

Details: [`../Git-Profile-Manager/Readme.md`](../Git-Profile-Manager/Readme.md)

---

## 🔍 Verification

The installer checks for `zsh`, `git`, `gh`, `.zshrc`, and `.p10k.zsh`. It also reports whether Powerlevel10k's theme directory is already present.

Powerlevel10k is normally downloaded automatically by Zinit from `.zshrc` on the first Zsh startup. Internet access is required for that first load.

---

## 🐛 Troubleshooting

**Zsh is still not the default shell**

```bash
chsh -s "$(command -v zsh)"
```

Log out and back in, or restart WSL with `wsl --shutdown`.

**Configuration file was not found**

The default source directory is the directory containing `initial-setup.sh`. Use `--config-dir` if `.zshrc` or `.p10k.zsh` is stored elsewhere.

**Powerlevel10k icons look incorrect**

Install a Nerd Font or Powerline-compatible font, enable it in the terminal, and refresh the font cache:

```bash
sudo fc-cache -f
```

**Zinit or plugins are missing**

Start Zsh again with internet access so Zinit can clone Powerlevel10k and download the configured plugins.
