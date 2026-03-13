<div align="center">

<h1>claude-multi-account</h1>

<p><strong>Run multiple Claude CLI accounts with shared settings, plugins, marketplace sync, and backup/restore.</strong></p>

<p>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey" alt="Platform">
  <img src="https://img.shields.io/badge/Shell-PowerShell%20%7C%20Bash-green" alt="Shell">
  <a href="https://github.com/ghackk/claude-multi-account/stargazers"><img src="https://img.shields.io/github/stars/ghackk/claude-multi-account?style=social" alt="GitHub Stars"></a>
</p>

</div>

---

## Why?

Claude CLI stores all config in a single `~/.claude/` directory — so you're locked to **one account at a time**. Switching means logging out, logging in, and losing your settings.

**claude-multi-account** fixes this:

- **Isolated profiles** — each account gets its own config directory, no conflicts
- **Shared settings** — define MCP servers, env vars, plugins, and CLAUDE.md once — auto-applied everywhere
- **Plugin & marketplace management** — enable plugins globally or per-account, browse marketplace indexes
- **One command** — launch any account instantly from an interactive menu

---

## Features

<table>
<tr>
<td width="50%">

**Multi-Account Management**<br>
Create, launch, rename, and delete independent Claude CLI profiles

</td>
<td width="50%">

**Shared MCP & Settings**<br>
Define MCP servers, env vars, and preferences once — sync to all accounts

</td>
</tr>
<tr>
<td>

**Plugins & Marketplace**<br>
Enable/disable plugins globally or per-account, browse and manage marketplace indexes

</td>
<td>

**Global CLAUDE.md**<br>
Write instructions and skills that apply across every account

</td>
</tr>
<tr>
<td>

**Backup & Restore**<br>
Timestamped archives of all accounts and configs with one click

</td>
<td>

**Export / Import Profiles**<br>
Copy a profile between machines as a single base64 token — credentials, settings, and launcher included

</td>
</tr>
<tr>
<td>

**Zero Dependencies**<br>
Just your shell and Claude CLI — nothing else to install

</td>
<td>

**Run from Repo**<br>
Add the repo to your PATH — `git pull` instantly updates the menu, no manual copying

</td>
</tr>
</table>

---

## Quick Start

### Windows

```powershell
# Clone the repo
git clone https://github.com/ghackk/claude-multi-account.git

# Option A: Add the repo directly to your PATH (recommended — git pull updates instantly)
[Environment]::SetEnvironmentVariable("PATH", "$HOME\claude-multi-account;" + [Environment]::GetEnvironmentVariable("PATH", "User"), "User")

# Option B: Copy scripts to a separate directory
New-Item -ItemType Directory -Path "$HOME\claude-accounts" -Force
Copy-Item claude-multi-account\claude-menu.ps1 "$HOME\claude-accounts\"
Copy-Item claude-multi-account\claude-menu.bat "$HOME\claude-accounts\"

# Run it (open a new terminal first if you changed PATH)
claude-menu
```

### Linux / macOS

```bash
# Clone the repo
git clone https://github.com/ghackk/claude-multi-account.git

# Option A: Add the repo to your PATH (recommended)
echo 'export PATH="$HOME/claude-multi-account:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Option B: Copy scripts to a separate directory
mkdir -p ~/claude-accounts
cp claude-multi-account/unix/claude-menu.sh ~/claude-accounts/
chmod +x ~/claude-accounts/claude-menu.sh

# Run it
claude-menu
```

---

## Menu Overview

### Main Menu

```
======================================
       Claude Account Manager
======================================
  Current Accounts:

  1. claude-work     [logged in]   (last used: 02 Mar 2026 10:30 AM)
  2. claude-personal [logged in]   (last used: 01 Mar 2026 08:15 PM)

======================================
  1. List Accounts
  2. Create New Account
  3. Launch Account
  4. Rename Account
  5. Delete Account
  6. Backup Sessions
  7. Restore Sessions
  8. Shared Settings (MCP/Skills)
  9. Plugins & Marketplace
  E. Export Profile (Token)
  I. Import Profile (Token)
  0. Exit
======================================
```

### Shared Settings (Option 8)

Manage universal settings applied to all accounts on launch:

| Option | Action |
|--------|--------|
| 1 | Edit MCP + Settings (opens in editor) |
| 2 | Edit Skills/Instructions (CLAUDE.md) |
| 3 | View current shared settings |
| 4 | Sync shared settings to ALL accounts |
| 5 | Show MCP server list |
| 6 | Reset shared settings |

### Plugins & Marketplace (Option 9)

Browse marketplace indexes and manage plugins across accounts:

| Option | Action |
|--------|--------|
| 1 | Enable plugin for ALL accounts |
| 2 | Enable plugin for one account |
| 3 | Disable plugin (shared) |
| 4 | Disable plugin (one account) |
| 5 | Browse marketplace plugins |
| 6 | Marketplace Management (add/remove/sync) |

### Export / Import Profile (Options E & I)

Transfer a profile between machines using a copy-pasteable base64 token:

| Option | Action |
|--------|--------|
| E | Export a profile — generates a compact token (~5 KB) containing credentials, settings, and launcher |
| I | Import a profile — paste the token to restore the account on any machine |

The token bundles only essentials (credentials, settings, CLAUDE.md, launcher) — not cache or conversation history.

---

## How It Works

```
┌─────────────┐      ┌──────────────────┐      ┌─────────────────┐
│  You pick    │ ───> │  Shared settings │ ───> │  Claude CLI     │
│  an account  │      │  + plugins are   │      │  launches with  │
│  from menu   │      │  merged in       │      │  isolated config│
└─────────────┘      └──────────────────┘      └─────────────────┘
```

Each account gets its own config directory (`~/.claude-<name>`). On every launch, shared settings from `~/claude-shared/` are deep-merged into the account — MCP servers, env vars, preferences, plugins, marketplace indexes, and CLAUDE.md instructions all stay in sync.

### Merge Strategy

Settings are **deep-merged** with shared settings winning on conflict:

| Scenario | Result |
|----------|--------|
| Key exists only in account | Kept |
| Key exists only in shared | Added |
| Key exists in both (simple value) | Shared wins |
| Key exists in both (nested object) | Recursively merged |

For `CLAUDE.md`, shared content is inserted between auto-managed markers at the top. Account-specific instructions below the markers are preserved.

---

## Folder Structure

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
├── claude-shared/             # Shared config (applied to all accounts)
│   ├── settings.json          # MCP servers, env vars, preferences, enabledPlugins, extraKnownMarketplaces
│   ├── CLAUDE.md              # Global instructions & skills
│   └── plugins/               # Shared plugin & marketplace data
│       └── marketplaces/      # Cached marketplace indexes
│
├── claude-backups/            # Timestamped backup archives
│
├── .claude-work/              # Account: work (auto-created)
├── .claude-personal/          # Account: personal (auto-created)
└── .claude-<name>/            # Account: <name>
```

---

## Documentation

- **[Installation Guide](docs/installation.md)** — setup for all platforms
- **[Usage Guide](docs/usage.md)** — full walkthrough of every feature

---

## Requirements

- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) installed and available in PATH
- **Windows**: PowerShell 5.1+
- **Linux/macOS**: Bash 4+, `jq` for JSON merging

---

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

---

## Credits

Built by **[Gyanesh Kumar](https://github.com/ghackk)**

---

## License

[MIT](LICENSE)
