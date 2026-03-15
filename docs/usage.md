# Usage Guide

## Main Menu

When you launch the script, you see the main menu with a list of existing accounts and available actions:

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
  E/I. Export/Import Profile
  0. Exit
======================================
```

## Account Lifecycle

### 1. List Accounts

Shows all accounts with their login status and last-used timestamp. Accounts are identified by their launcher scripts in `~/claude-accounts/`.

### 2. Create New Account

```
  Enter account name (e.g. alpha): work
  Shared settings applied automatically.
  Created claude-work successfully!
  Login now? (y/n):
```

What happens:
- Creates a launcher script (`claude-work.bat` on Windows, `claude-work.sh` on Linux/macOS)
- The launcher sets `CLAUDE_CONFIG_DIR` to `~/.claude-work` before running `claude`
- Shared settings are automatically applied to the new account
- Optionally launches Claude CLI immediately so you can log in

### 3. Launch Account

Select an account by number. Before launching:
1. Shared settings are synced into the account's config directory
2. Claude CLI starts with that account's config

This means any MCP servers or instructions you've added to shared settings are always up to date.

### 4. Rename Account

Renames both the launcher script and the config directory. You can select multiple accounts to rename in sequence.

### 5. Delete Account

Permanently deletes the launcher script and the config directory. Requires typing `YES` to confirm. Supports batch deletion (comma-separated numbers).

**This is irreversible** — the account's authentication, conversation history, and settings are deleted.

## Backup & Restore

### 6. Backup Sessions

Creates a timestamped archive containing:
- `~/claude-accounts/` — all launcher scripts
- `~/claude-shared/` — shared settings and CLAUDE.md
- `~/.claude-<name>/` — config directories for every account

**Windows**: Creates a `.zip` file in `~/claude-backups/`
**Linux/macOS**: Creates a `.tar.gz` file in `~/claude-backups/`

### 7. Restore Sessions

Lists available backups and restores the selected one. Files are extracted to your home directory, overwriting existing account configs.

## Shared Settings

Option 8 opens the shared settings submenu:

```
SHARED SETTINGS

  These apply to ALL accounts automatically on launch.

  Shared folder: ~/claude-shared

  Summary:
    MCP Servers  : 2 configured
    Env Vars     : 1 configured
    CLAUDE.md    : 15 lines (skills/instructions)

======================================
  1. Edit MCP + Settings
  2. Edit Skills/Instructions
  3. View current shared settings
  4. Sync shared -> ALL accounts NOW
  5. Show MCP server list
  6. Reset shared settings (clear)
  0. Back
======================================
```

### How Shared Settings Work

The shared settings live in `~/claude-shared/`:

**`settings.json`** — MCP servers, environment variables, and preferences:
```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-filesystem"]
    }
  },
  "env": {
    "MY_API_KEY": "sk-..."
  },
  "preferences": {}
}
```

**`CLAUDE.md`** — Global instructions applied to every account:
```markdown
# Shared Claude Instructions (Skills)
Always respond concisely.
Use TypeScript for all code examples.
```

### Sync Behavior

- **On account launch (option 3)**: shared settings are automatically merged into the account's config
- **On account creation (option 2)**: shared settings are applied immediately
- **Manual sync (submenu option 4)**: pushes shared settings to ALL accounts at once

### Merge Strategy

Settings are **deep-merged** — shared settings win on conflict:

| Scenario | Result |
|----------|--------|
| Key exists only in account | Kept |
| Key exists only in shared | Added |
| Key exists in both (simple value) | Shared wins |
| Key exists in both (nested object) | Recursively merged |

For `CLAUDE.md`, the shared content is inserted between marker comments at the top of the file. Account-specific content below the markers is preserved.

### Editing Settings

- **Option 1**: Opens `settings.json` in your editor (Notepad on Windows, `$EDITOR` or `nano` on Linux/macOS)
- **Option 2**: Opens `CLAUDE.md` in your editor
- **Option 3**: Displays both files in the terminal
- **Option 5**: Lists configured MCP servers by name and command

After editing, use **option 4** to push changes to all accounts immediately, or they'll be applied next time you launch each account.

### Reset

Option 6 wipes shared settings back to empty defaults. Requires typing `YES` to confirm. This does **not** remove settings already synced to individual accounts.

## Plugins & Marketplace

Option 9 opens the plugins and marketplace submenu, where you can discover, install, and manage plugins across your accounts.

### Plugin Management

Plugins extend the account manager with additional functionality. Each plugin is identified by a key in the format:

```
plugin-name@marketplace-name
```

For example: `mcp-git@official`, `code-review@community`.

You can:
- **Enable or disable plugins globally** — a globally enabled plugin is available to all accounts
- **Enable or disable plugins per-account** — override the global setting for specific accounts

Disabled plugins are not loaded or synced, but their configuration is preserved so you can re-enable them later.

### Marketplace Management

A marketplace is a plugin index hosted as a GitHub repo or a URL source. You can:

- **Add a marketplace** — provide a GitHub repo (e.g. `owner/repo`) or a direct URL to a marketplace index
- **Remove a marketplace** — unregisters the marketplace and its cached index (installed plugins are not removed)
- **Sync indexes** — pull the latest plugin listings from all registered marketplaces
- **Pull indexes from accounts** — if another account has marketplace indexes already cached, pull them locally to avoid re-downloading

### Browse Marketplace Plugins

From the submenu you can browse all available plugins across your registered marketplaces, view descriptions and version info, and install directly.

## Export / Import Profiles

Options E and I let you move an account between machines with a single copy-paste token.

### Export (E)

1. Pick the account you want to export
2. The manager bundles the account's essentials into a compact base64 token (~5 KB):
   - Credentials and authentication state
   - Account-specific settings (`settings.json`)
   - Account-specific `CLAUDE.md`
   - Launcher script
3. The token is printed to the terminal for you to copy

Only essentials are bundled — cache, conversation history, and other transient data are **not** included.

### Import (I)

1. Paste the token on the target machine
2. The manager restores the account: config directory, launcher script, and settings

If an account with the same name already exists, you are prompted before overwriting.

### Token Format

Tokens follow this format:

```
CLAUDE_TOKEN:<base64-encoded payload>:END_TOKEN
```

The payload is a base64-encoded archive containing the account's credentials, settings, CLAUDE.md, and launcher. Tokens are self-contained — no network access is needed to import.

## Tips

- **Separate work and personal accounts** to keep different API keys, MCP servers, and instructions isolated
- **Use shared settings for common MCP servers** you want available everywhere
- **Back up regularly** before making big changes to accounts
- **Account names** are lowercased automatically; use simple names like `work`, `personal`, `test`
- **Use plugins for repeatable workflows** — install once, enable globally, and every account gets the same tooling
- **Add community marketplaces sparingly** — only register marketplace sources you trust
- **Export before decommissioning a machine** — export each account's token and store it securely so you can import on your next setup
- **Tokens contain credentials** — treat exported tokens like passwords; do not commit them to version control or share them in public channels
