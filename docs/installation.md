# Installation Guide

## Prerequisites

1. **Claude CLI** must be installed and available in your PATH. Verify with:
   ```
   claude --version
   ```
   If not installed, follow the [official Claude CLI docs](https://docs.anthropic.com/en/docs/claude-code).

2. **Platform-specific requirements:**
   - **Windows**: PowerShell 5.1+ (included with Windows 10/11)
   - **Linux/macOS**: Bash 4+, `jq` (for JSON merging)

## Windows Installation

### Option A: Clone the repo

```powershell
git clone https://github.com/ghackk/claude-multi-account.git
cd claude-multi-account
```

#### Option A (recommended): Add the cloned repo directly to PATH

This is the simplest approach — `git pull` updates your scripts instantly.

1. Open **Start** > search **Environment Variables**
2. Under **User variables**, select **Path** > **Edit**
3. Add the full path to your cloned repo (e.g. `C:\Users\YourName\claude-multi-account`)
4. Click OK, then open a new terminal

Now you can just type:
```
claude-menu
```

#### Option B: Copy scripts to a separate directory

```powershell
# Create accounts directory if it doesn't exist
New-Item -ItemType Directory -Path "$HOME\claude-accounts" -Force

# Copy scripts
Copy-Item windows\claude-menu.ps1 "$HOME\claude-accounts\"
Copy-Item windows\claude-menu.bat "$HOME\claude-accounts\"
```

> **Note:** With this approach you must re-copy files after each `git pull` to pick up updates.

To add this directory to PATH instead:

1. Open **Start** > search **Environment Variables**
2. Under **User variables**, select **Path** > **Edit**
3. Add `%USERPROFILE%\claude-accounts`
4. Click OK, then open a new terminal

### Running

Double-click `claude-menu.bat` (from whichever directory you chose), or run from a terminal:

```powershell
& "$HOME\claude-multi-account\claude-menu.bat"
```

The `.bat` launcher automatically sets the execution policy for the PowerShell script, so no system-wide policy changes are needed.

## Linux / macOS Installation

### Option A: Clone the repo

```bash
git clone https://github.com/ghackk/claude-multi-account.git
cd claude-multi-account
chmod +x unix/claude-menu.sh
```

#### Option A (recommended): Add the cloned repo's `unix/` directory to PATH

This is the simplest approach — `git pull` updates your scripts instantly.

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
export PATH="$HOME/claude-multi-account/unix:$PATH"
```

Then reload your shell:
```bash
source ~/.bashrc  # or ~/.zshrc
```

#### Option B: Copy scripts to a separate directory

```bash
mkdir -p ~/claude-accounts
cp unix/claude-menu.sh ~/claude-accounts/
chmod +x ~/claude-accounts/claude-menu.sh
```

> **Note:** With this approach you must re-copy files after each `git pull` to pick up updates.

### Option B (no git): Direct download

```bash
mkdir -p ~/claude-accounts
curl -o ~/claude-accounts/claude-menu.sh \
  https://raw.githubusercontent.com/ghackk/claude-multi-account/main/unix/claude-menu.sh
chmod +x ~/claude-accounts/claude-menu.sh
```

### Install jq

The bash script requires `jq` for JSON merging:

```bash
# Ubuntu / Debian
sudo apt install jq

# macOS (Homebrew)
brew install jq

# Fedora
sudo dnf install jq

# Arch
sudo pacman -S jq
```

### Running

If you used Option A (repo in PATH), just type:
```bash
claude-menu.sh
```

If you used Option B (copied to `~/claude-accounts`):
```bash
~/claude-accounts/claude-menu.sh
```

### Optional: Add alias or PATH (for Option B)

If you copied scripts to `~/claude-accounts`, add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Option 1: alias
alias claude-menu="$HOME/claude-accounts/claude-menu.sh"

# Option 2: add to PATH
export PATH="$HOME/claude-accounts:$PATH"
```

Then reload your shell:
```bash
source ~/.bashrc  # or ~/.zshrc
```

## Verifying Installation

After installation, run the menu and verify:

1. The menu displays without errors
2. You can create a test account (option 2)
3. The shared settings directory is created at `~/claude-shared/`
4. Launching the test account opens Claude CLI (option 3)

You can then delete the test account (option 5) if you no longer need it.

## Folder Structure After Setup

```
~/
├── claude-multi-account/      # Git repo (can be added to PATH directly)
│   ├── claude-menu.ps1        # Windows menu script
│   ├── claude-menu.bat        # Windows launcher
│   ├── windows/               # Windows-specific scripts
│   └── unix/                  # Linux/macOS scripts
│
├── claude-accounts/           # Account launchers (auto-created)
│   ├── claude-work.bat/.sh    # Account launcher
│   └── claude-personal.bat/.sh
│
├── claude-shared/             # Shared settings (auto-created)
│   ├── settings.json          # MCP servers, env, preferences, enabledPlugins, extraKnownMarketplaces
│   ├── CLAUDE.md              # Shared instructions/skills
│   └── plugins/               # Shared plugin & marketplace data
│       └── marketplaces/      # Cached marketplace indexes
│
├── claude-backups/            # Backup archives (auto-created)
├── .claude-work/              # Account config dir (auto-created)
└── .claude-personal/          # Account config dir (auto-created)
```
