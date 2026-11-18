# 🔐 Git Profile Manager

A terminal-based manager for multiple Git identities and SSH keys on **WSL / Linux**.
Keep your **work**, **personal**, and other GitLab accounts separate — with the correct SSH key, Git identity, and project directory selected automatically.

---

## ✨ What It Does

- 🪪 Creates and manages named Git profiles, such as `work`, `personal`, or `client-acme`
- 🔑 Assigns a separate SSH key to every profile
- 📁 Routes the correct Git identity by project directory using Git `includeIf`
- 🧾 Keeps a local profile database alongside the script
- 💾 Creates full configuration snapshots before changes
- ⏪ Restores a prior configuration snapshot
- 🌍 Manages selected global Git settings
- 🛡️ Includes safeguards for private-key viewing, deletion, and passphrase changes
- 📜 Records separate run, success, and error logs

No Python, Node.js, database server, or third-party package is required. The script uses Bash, Git, OpenSSH, and standard Linux tools.

---

## 🧭 Main Menu

```text
 Manage Git profiles (add/edit/remove/review)
 Manage global Git configuration
 Manage SSH Keys
 Create a full configuration backup
 List backup snapshots
 Restore a backup snapshot
 Exit
```

At any prompt:

- `:b` or `:back` returns to the previous screen
- `:x` or `:exit` asks whether you want to leave the application

The main menu has no back option because there is no previous screen to return to.

---

## 📦 Requirements

- 🐧 Linux or WSL
- 🐚 Bash
- 🔧 Git
- 🔐 OpenSSH, including `ssh` and `ssh-keygen`
- 🧰 Standard utilities: `find`, `sort`, `realpath`, `stat`, and `flock`

The script creates its own state directory beside itself:

```text
./.gitprofile_manager/
```

It does **not** need to be installed system-wide.

---

## 🚀 Getting Started

1. Save or locate the script as `git-profile-manager-v3.sh`
2. Make it executable:

```bash
chmod +x git-profile-manager-v3.sh
```

3. Check its syntax:

```bash
bash -n git-profile-manager-v3.sh
```

4. Start it:

```bash
./git-profile-manager-v3.sh
```

On the first run, the script creates:

```text
.gitprofile_manager/
├── db/        🗃️ Profile database
├── backups/   💾 Configuration snapshots
├── outputs/   📤 Reserved output directory
├── logs/      📜 Run and success logs
└── errors/    ❌ Error logs
```

If no profile database is found, it tells you that it is starting fresh. It still checks your existing SSH keys and directories, so you can safely use existing keys.

---

## 🪪 Git Profiles

### ➕ Add a Profile

From the main menu, choose:

```text
 Manage Git profiles
[a] Add profile
```

The script asks for:

| Field | Default | Notes |
|---|---|---|
| 🏷️ Profile name | None | Must be unique; letters, numbers, `.`, `_`, and `-` only |
| 📁 Project directory | `~/projects/<profile-name>` | Created during apply if it does not exist |
| 🔑 SSH key | `~/.ssh/<profile-name>/id_ed25519_<profile-name>` | Choose an existing key or create a new one |
| 🌐 GitLab host | `gitlab.com` | Use your own hostname for self-hosted GitLab |
| 🧑 Git name | Profile name | Used for commits in that profile’s directory |
| 📧 Git email | None | Used for commits in that profile’s directory |

Nothing is written to Git configuration until you explicitly confirm the final review.

### 🔍 SSH Key Selection

When adding or editing a profile, you can:

- 🔍 Scan `~/.ssh/` for existing key pairs
- 📂 Change the scan folder
- 🆕 Generate a new Ed25519 key
- 📄 Enter the path of an existing private key
- ♻️ Keep the profile’s currently assigned key

The script scans up to two directory levels, so it can find keys stored directly in `~/.ssh/` or inside profile-specific folders such as:

```text
~/.ssh/work/id_ed25519_work
```

If a key is already assigned to another profile, the script displays a shared-key warning. You may continue, but separate keys are recommended for separate Git identities.

### ✅ Review Before Apply

Before a profile is applied, the script displays:

- 🌍 Current global Git configuration
- 🪪 The proposed profile details
- 🔑 Whether the SSH key already exists or will be generated
- 📁 Whether the project directory already exists or will be created

Nothing is changed until you answer **yes**.

### 📦 What Happens on Apply

1. 💾 Creates a pre-change snapshot
2. 🔑 Generates the SSH key if needed
3. 📁 Creates the project directory if needed
4. 📝 Writes `~/.gitconfig-<profile-name>`
5. 🔗 Adds the matching Git `includeIf` rule
6. 💾 Saves the profile record
7. 🖨️ Displays the public key for you to add to GitLab
8. 🧹 Offers to keep or delete the old key after a key replacement
9. 📡 Optionally tests SSH connectivity

---

## 🔀 How Profile Routing Works

For each profile, the script writes a separate Git configuration file:

```text
~/.gitconfig-work
~/.gitconfig-personal
```

Example for a work profile:

```ini
[user]
    name = Yogesh (Work)
    email = yogesh@company.example

[core]
    sshCommand = ssh -o IdentitiesOnly=yes -i '/home/you/.ssh/work/id_ed25519_work'
```

It then adds a conditional include to your global Git configuration:

```ini
[includeIf "gitdir:/home/you/projects/work/"]
    path = /home/you/.gitconfig-work
```

Inside `/home/you/projects/work/`, Git automatically uses:

- 🧑 The work Git name
- 📧 The work Git email
- 🔑 The work SSH private key

`IdentitiesOnly=yes` prevents SSH from trying other keys or agent identities first.

---

## ✏️ Editing Profiles

From the profile menu, choose:

```text
[e] Edit profile
```

You can change:

- 📁 Project directory
- 🌐 GitLab host
- 🧑 Git name
- 📧 Git email
- 🔑 SSH key

The profile name itself is intentionally fixed after creation. This prevents accidental renaming from leaving orphaned configuration files or database records.

If the project directory changes, the old `includeIf` rule is removed and the new one is added.

---

## 🔁 Replacing a Profile Key

From the SSH Keys menu:

```text
 Replace a profile key
```

The script first shows the profile’s current details. You can then choose:

```text
 Replace key only — keep other parameters
 Modify parameters, then replace key
```

- **Option 1** keeps the directory, GitLab host, Git name, and Git email unchanged
- **Option 2** lets you edit any of those values before replacing the key

After selecting or generating the new key, the script shows a final review screen before applying it.

### 🧹 Old-Key Handling

After a successful replacement, the script asks what to do with the old key:

```text
 Keep on disk — no longer assigned to this profile (default)
 Permanently delete private and public files
```

- **Keep:** The old key remains on disk but is no longer assigned to the profile
- **Delete:** Requires a `y` confirmation and then typing `DELETE`

The script blocks deletion if another saved profile still uses the old key.

⚠️ Deleting a key locally does **not** remove it from GitLab. Remove it manually from **GitLab → Preferences → SSH Keys** after confirming the replacement works.

---

## 🔐 SSH Keys Menu

```text
 View one profile: metadata and public key
 View all public keys
 Reveal a private key
 Replace a profile key
 Add/change/remove key passphrase
 Test SSH connectivity
```

### 👁️ View Key Metadata

Option 1 shows:

- 🪪 Profile details
- 🔑 Private-key path and permissions
- 🔓 Public key
- 🧬 Public-key fingerprint

It does **not** guess whether a private key is encrypted from its file permissions.

### 📋 View All Public Keys

Option 2 displays every saved profile’s public key, ready to copy into the matching GitLab account.

### 🛑 Reveal a Private Key

Option 3 is deliberately protected:

- 🚨 Displays a private-key exposure warning
- 🎥 Warns about screen recording, streaming, terminal logging, and screen sharing
- 🔡 Requires you to type `SHOW PRIVATE KEY`
- 🧹 Clears the terminal after you press Enter
- 📜 Logs that the key was viewed, but never records its contents

⚠️ Clearing the terminal cannot erase a screen recording, terminal scrollback copy, or a remote session capture. Only reveal private keys when no recording or screen sharing is active.

### 🔑 Change a Passphrase

Option 5 uses `ssh-keygen -p` directly. It can:

- ➕ Add a passphrase to an unencrypted key
- 🔁 Change an existing passphrase
- ➖ Remove an existing passphrase

The script never passes a passphrase as a command-line argument. OpenSSH prompts for it directly.

⚠️ Removing a passphrase makes the private key easier to use if someone obtains the file. Only do this if you understand the tradeoff.

### 📡 Test Connectivity

Option 6 asks for a GitLab SSH target, such as:

```text
git@gitlab.com
```

It also accepts repository URLs, including:

```text
git@gitlab.com:group/project.git
[https://gitlab.com/group/project](https://gitlab.com/group/project)
ssh://git@gitlab.com:2222/group/project.git
```

The script extracts the host, optional username, and optional port, then tests SSH authentication using the selected profile’s key.

---

## 🌍 Global Git Configuration

From the main menu:

```text
 Manage global Git configuration
```

You can:

- 👁️ View the current global Git configuration
- ✏️ Set a global setting, such as `user.name` or `init.defaultBranch`
- ➖ Unset a global setting

The script deliberately blocks direct edits to:

```text
include.*
includeIf.*
```

Those settings are managed by the profile workflow so that profile routing remains consistent.

Every global change requires confirmation and creates a snapshot first.

---

## 💾 Backup Snapshots

From the main menu:

```text
 Create a full configuration backup
 List backup snapshots
 Restore a backup snapshot
```

A snapshot contains:

```text
backups/<timestamp>_<reason>/
├── gitconfig            🌍 Global Git configuration
├── configs/             📝 Profile-specific Git configuration files
├── db/                  🗃️ Profile database
└── manifest.txt         🧾 Snapshot metadata
```

Snapshots are created automatically before:

- ➕ Applying a profile
- ✏️ Editing a profile
- 🔁 Replacing a profile key
- 🗑️ Removing a profile
- 🌍 Changing a global setting
- ⏪ Restoring a snapshot

### ⏪ Restore Behavior

Restoring a snapshot restores both:

- 🌍 Global Git configuration
- 🗃️ Profile database and managed profile configuration files

This prevents the database and Git configuration from becoming inconsistent.

⚠️ SSH key files are never restored, copied, or deleted by the restore process. Ensure that the SSH keys referenced by a restored profile still exist.

---

## 📜 Logs

```text
logs/
├── run_<timestamp>.log       📜 Detailed run transcript
├── success_<timestamp>.log   ✅ Successful operations
└── errors/
    └── error_<timestamp>.log ❌ Errors
```

The logs record actions and outcomes, but deliberately avoid storing:

- 🔐 Private-key contents
- 🔑 SSH passphrases
- 🌍 Full global Git configuration output

---

## 🛡️ Safety Principles

- 🚫 Nothing is applied until you explicitly confirm it
- 💾 A snapshot is created before configuration changes
- 🔒 Private keys are never automatically deleted
- 🗑️ Key deletion requires typed confirmation: `DELETE`
- 🚧 Key deletion is blocked if another profile still uses the key
- 🔐 Private-key contents are never written to application logs
- 🧹 Private-key viewing clears the terminal afterward
- 🧭 `:b` and `:x` are available throughout the menus

---

## ⚠️ Important Notes

### 🏢 SAML-Protected GitLab

A valid SSH key does not always guarantee access to a GitLab account. If your organization enables GitLab’s Git-over-SSH restrictions or similar SAML-based policy, you may also need an active SAML session.

If SSH authentication fails despite a correctly configured key, check with your GitLab administrator.

### 🖥️ WSL

The script uses your Linux home directory, such as:

```text
/home/<your-linux-user>
```

It does not use the Windows user profile under `/mnt/c/Users/...`.

### 🧪 First Use

Test the workflow with a temporary profile and a new SSH key before using it to replace an important work key.

---

## 🧰 Typical Workflow

1. 🚀 Start the script
2. 🪪 Choose **Manage Git profiles**
3. ➕ Add a `work` profile
4. 🔑 Select or create a work SSH key
5. 🌐 Keep `gitlab.com` or enter your company GitLab hostname
6. 📧 Enter your work Git email
7. ✅ Review and apply
8. 📋 Copy the displayed public key into GitLab
9. 📡 Test SSH connectivity
10. 📁 Clone or move repositories into `~/projects/work/`

Now commits and SSH operations inside that directory automatically use the correct identity.

---

## 📄 License

Use, modify, and adapt this script for your own workflows. 🎉

---

*Built for keeping `work` 💼 and `personal` 🏡 Git identities safely separated.*