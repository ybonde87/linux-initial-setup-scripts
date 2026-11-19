# 🚀 Project Navigator for zsh

A lightweight zsh function suite for navigating Git repositories with short, case-insensitive commands such as `proj acme emea tgw`. It supports context-aware navigation, Git sync, back-jump history, bulk sync, repository discovery, and clone-and-register with shortcuts derived from repository URLs.

The installer supports Linux and WSL environments with zsh.

---

## 📦 What's Included

| Feature | Command | What it does |
|---|---|---|
| 🔀 Jump + sync | `proj acme emea tgw` | `cd` into the repo, switch to `main`/`master` if needed, `git pull`, show what changed |
| 🧭 Context-aware shortcut | `proj emea tgw` | Drop the client name if you're already inside its folder tree |
| 🏷️ Case-insensitive keys | `proj ACME EMEA tgw` | Same as lowercase — matching normalizes to lowercase internally |
| 📋 List all projects | `proj` | Show every registered project and its path |
| ⏪ Back-jump | `proj -` | Jump back to the previously visited project (like `cd -`) |
| 🌐 Bulk sync | `proj-sync-all` | Pull the latest on **every** registered repo in one pass |
| 🔍 Auto-discovery | `proj-scan <folder>` | Walk a folder tree, find every `.git` repo, auto-register it |
| 🩺 Health check | `proj-doctor` | Audit all mappings — flags missing folders or non-git folders |
| ➕ Add a project | `proj-add <keys> <path>` | Register a new mapping manually |
| 📥 Clone into current folder | `proj-clone <url> [keys]` | Clone a repository under the current folder and register it |
| 📂 Clone into a specific folder | `proj-clone-into <folder> <url> [keys]` | Clone a repository under a chosen folder and register it |
| 🔑 Preview URL shortcut | `proj-url-key <url>` | Show the shortcut that would be derived from a Git URL |
| ➖ Remove a project | `proj-remove <keys>` | Delete a mapping (auto-backs up config first) |
| ✏️ Edit config | `proj-edit` | Open the raw config file for manual bulk edits (auto-backs up first) |
| ♻️ Restore config | `proj-restore` | Restore the config from its last automatic backup |
| 🔄 Reload config | `proj-reload` | Reload config after manual file changes |
| 🎯 Show context | `proj-context` | Shows which client context (if any) is detected for your current directory |
| 🗂️ Tab completion | `proj co<TAB>` | Completes level by level: client → region → repo |

---

## 🛠️ Installation

### 1. Run the installer

```bash
cd Git-Project-Navigation
bash install_project_nav_v2.sh
```

The installer writes `~/.config/zsh/project_nav_v2.zsh`, backs up an existing copy with a timestamped `.bak.<timestamp>` suffix, and adds a source line to `~/.zshrc` if it is not already present. If zsh is installed, it checks the generated script's syntax. It also warns if it finds an older `project_nav` script sourced from `.zshrc`; comment out that older source line to avoid loading both versions.

### 2. Reload your shell

```bash
exec zsh
```

You now have all the commands listed above available.

---

## 📝 Registering Projects

### Option A — Manual, one at a time

```bash
proj-add Acme EMEA TGW ~/projects/work/Acme/EMEA/TGW-repo
proj-add Acme APAC VPC ~/projects/work/Acme/APAC/VPC-repo
proj-add Corp EMEA TGW ~/projects/work/Corp/EMEA/TGW-repo
proj-add Corp APAC ISE ~/projects/work/Corp/APAC/ISE-repo
```

Keys are **space-separated words** (client, region, repo name, or any structure you like). Case doesn't matter when typing later — it's normalized to lowercase internally, though the **actual folder path keeps its real casing** (important since WSL's filesystem is case-sensitive).

### Option B — Auto-discovery (recommended for many repos)

```bash
proj-scan ~/projects/work
```

Walks the entire folder tree, finds every `.git` repository, and registers each one automatically — using the folder path relative to your scan point as the key (lowercased, slashes turned into spaces). Already-registered keys are skipped, so it's safe to re-run after cloning new repos.

### Option C — Bulk edit

```bash
proj-edit
```

Opens the raw config file (`~/.config/zsh/project_dirs.conf`) for adding multiple lines at once, format:

```
acme emea tgw|/home/you/projects/work/Acme/EMEA/TGW-repo
corp apac ise|/home/you/projects/work/Corp/APAC/ISE-repo
```

A backup is automatically taken before the editor opens.

### Option D — Clone and register

Clone a repository into the current directory. By default, the shortcut is derived from the URL:

```bash
cd ~/projects/work
proj-clone git@gitlab.com:group-org/platform/services/region/sample-repo.git
```

For this URL the command derives the shortcut `proj group region sample-repo`: it uses the first path segment as the client (stripping a trailing `-org`, `-group`, or `-grp`), the repository's parent path segment, and the repository name. With a one-segment URL it uses the repo name; with two segments it uses the first and last segments. The cloned folder uses the URL's repository name, without a trailing `.git`.

Preview the derived shortcut without cloning:

```bash
proj-url-key git@gitlab.com:group-org/platform/services/region/sample-repo.git
# proj group region sample-repo
```

Provide custom key words when cloning if you prefer:

```bash
proj-clone git@gitlab.com:group-org/platform/services/region/sample-repo.git acme emea tgw
```

To clone under a specific existing folder instead of the current directory:

```bash
proj-clone-into ~/projects/work/Acme/EMEA \
  git@gitlab.com:group-org/platform/services/region/sample-repo.git \
  acme emea tgw
```

Clone commands support SCP-style SSH, `ssh://`, HTTP, and HTTPS Git URLs. The destination repository folder must not already exist; the destination parent passed to `proj-clone-into` must already exist. A shortcut that is already registered is rejected to prevent duplicate mappings. If cloning fails, the mapping is not added.

---

## 🎮 Daily Usage Examples

### Morning routine — pull everything

```bash
$ proj-sync-all
Syncing 4 registered project(s)...

== acme emea tgw ==
Pulling latest 'main' in /home/you/projects/work/Acme/EMEA/TGW-repo ...
New commits pulled:
a1b2c3d Fix TGW route propagation bug
9f8e7d6 Update VPC peering docs

== acme apac vpc ==
Error: folder for 'acme apac vpc' does not exist:
  /home/you/projects/work/Acme/APAC/VPC-repo
...

Sync summary: 3 OK, 0 failed, 1 skipped (missing folder).
```

### Context-aware shortcut

```bash
$ cd ~/projects/work/Acme
$ proj emea tgw
(context: acme) resolved 'emea tgw' -> 'acme emea tgw'
Pulling latest 'main' in /home/you/projects/work/Acme/EMEA/TGW-repo ...
Already up to date.
```

### Back-jump between two repos

```bash
$ proj acme emea tgw
$ proj corp apac ise
$ proj -
Jumping back to 'acme emea tgw'...
Pulling latest 'main' in /home/you/projects/work/Acme/EMEA/TGW-repo ...
No new commits. Already up to date.
```

### Health check

```bash
$ proj-doctor
Checking 4 registered project(s)...

  [OK]       acme emea tgw             -> /home/you/projects/work/Acme/EMEA/TGW-repo
  [MISSING]  acme apac vpc             -> /home/you/projects/work/Acme/APAC/VPC-repo
  [OK]       corp emea tgw             -> /home/you/projects/work/Corp/EMEA/TGW-repo
  [NOT GIT]  corp apac ise             -> /home/you/projects/work/Corp/APAC/ISE-repo

Summary: 2 OK, 1 missing, 1 not-a-git-repo.
Fix missing ones with: proj-remove <key>  followed by  proj-add <key> <new-path>
```

---

## ⚙️ How the Git Sync Logic Works

When `proj <keys>` resolves to an exact repo:

1. 📁 Confirms the folder exists and is readable — if not, prints the exact broken path and fix commands.
2. 🔍 Checks it's a git repository (if not, just `cd`s there with a note, no sync attempted).
3. 🌿 Detects a default branch from local `main`, local `master`, remote `origin/main`, or remote `origin/master`, in that order.
4. 🔀 If found, switches to that branch if needed and runs `git pull origin <default>`. If no `main`/`master` is found, it stays on the current branch and runs `git pull` using that branch's upstream configuration.
5. 📥 Compares the commit hash before and after the pull and prints either a `git log --oneline` of new commits or "No new commits. Already up to date."

---

## 🧭 Context-Aware Navigation

If your current directory contains a known client name as a path component (e.g., inside `~/projects/work/Acme/...`), `proj` will:

1. First try your typed words as a full, standalone key.
2. If that fails, retry by prefixing the detected client, so `proj emea tgw` becomes `acme emea tgw` automatically.
3. Only apply this when you're actually inside that client's folder tree — the same shortened command from elsewhere correctly reports "no project found" instead of guessing.

---

## 🔒 Config Backups

Both `proj-edit` and `proj-remove` automatically copy `project_dirs.conf` to `project_dirs.conf.bak` immediately before making any change. If a manual edit or removal goes wrong:

```bash
proj-restore
```

This restores the config from the last backup (and saves your current, possibly-broken state to `project_dirs.conf.pre-restore` first, just in case). Note this is a single rotating backup, not full version history — for anything more durable, periodically copy the file elsewhere or track it in a private git repo.

---

## 🚨 Error Handling Reference

| Situation | Behavior |
|---|---|
| Folder deleted or moved | Clear error with the broken path and fix commands (`proj-remove` / `proj-add`) |
| No permission to access folder | Explicit permission error message |
| Folder exists but isn't a git repo | Note that it `cd`'d there only, no sync attempted |
| Detached HEAD / unreadable branch | Warning that current branch couldn't be determined |
| Uncommitted changes blocking branch switch | Tells you to commit or stash, then retry |
| `git pull` fails | Warning listing likely causes (network, auth, merge conflict) |
| Git not installed | Warning, skips sync gracefully |
| `proj-add` given a path that doesn't exist yet | Warns immediately, still saves the mapping |
| `proj-clone` target folder already exists | Stops before cloning and reports the existing folder |
| `proj-clone-into` target directory doesn't exist | Stops and asks you to create the directory first |
| `proj-clone`/`proj-clone-into` key already exists | Stops and asks you to choose another key or remove the existing mapping |
| Git clone fails | Stops, reports the URL/auth/network error, and does not register the mapping |
| `proj -` with no prior navigation | Tells you there's no previous project |
| `proj-restore` with no backup file | Tells you no backup exists yet |

Run `proj-doctor` periodically to catch broken mappings proactively, and `proj-sync-all` each morning to pull everything before starting work.

---

## 🐛 Troubleshooting

**`proj: command not found`**
`.zshrc` didn't source the script, or the shell wasn't reloaded. Re-run `exec zsh` (a full reload, not just `source ~/.zshrc`, since a broken function definition can linger in the current session).

**Tab-completion shows nothing**
Ensure `compinit` is loaded in `.zshrc` (usually automatic with Oh My Zsh/Powerlevel10k). If not:
```bash
autoload -Uz compinit && compinit
```

**`proj-scan` finds nothing**
Confirm the base folder actually contains `.git` directories at some depth, and that you have read permission on all subfolders.

**`git checkout main` fails with local changes**
Commit or stash your changes first, then re-run `proj <keys>`.

**A repo path changed**
`proj-remove <old keys>` then `proj-add <new keys> <new path>`, or edit directly with `proj-edit`.

**The installer reports that zsh is not found**
The installer still writes the generated file and configures `.zshrc`, but skips its syntax check. Install zsh before starting a zsh session.

**Both old and v2 commands appear to load**
Comment out old `project_nav` source lines in `~/.zshrc`, keep the v2 source line, and run `exec zsh`.

---

## 🗑️ Uninstalling

```bash
# remove the "source ~/.config/zsh/project_nav_v2.zsh" line from .zshrc, then:
rm ~/.config/zsh/project_nav_v2.zsh
rm ~/.config/zsh/project_dirs.conf
rm ~/.config/zsh/project_dirs.conf.bak
```

---

## 🔮 Possible Future Enhancements

Still not implemented, worth considering later:

- 🎨 Colorized output (green/red/yellow) for faster scanning of `proj-doctor` and `proj-sync-all` results.
- 🎯 `fzf`-based interactive selection when multiple matches are found, instead of a plain list.
- 💾 Persisting back-jump history across terminal sessions (currently resets each new shell).
- 🚀 A `--force` flag for `proj-scan` to overwrite existing mappings instead of always skipping.
