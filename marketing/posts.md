# Marketing Posts — claude-multi-account

---

## Twitter/X Thread

### Tweet 1 (main)
```
I built an open-source tool to manage multiple Claude CLI accounts.

Switch between work, personal, client accounts instantly. Shared MCP servers, plugins, cloud backup — all from one command.

Works on Windows, Linux, macOS, Termux.

github.com/ghackk/claude-multi-account
npmjs.com/package/@ghackk/multi-claude
```

### Tweet 2
```
What it does:

-> Isolated profiles — no config conflicts
-> Shared MCP servers & settings across all accounts
-> Global CLAUDE.md — write instructions once, apply everywhere
-> Plugins & marketplace management
-> Direct launch: just type "claude-work" from any terminal
```

### Tweet 3
```
Cloud features:

-> Backup all profiles to cloud in one click
-> Restore on any machine with a single code
-> Export/import profiles as copy-paste tokens
-> Cross-platform — backup from Mac, restore on Linux

Your profiles follow you everywhere.
```

### Tweet 4
```
Install in one line:

npm install -g @ghackk/multi-claude
pip install multi-claude
brew install ghackk/tap/multi-claude
scoop install multi-claude

Or just:
curl -fsSL https://raw.githubusercontent.com/ghackk/claude-multi-account/master/install.sh | bash

Star if useful -> github.com/ghackk/claude-multi-account
npm: npmjs.com/package/@ghackk/multi-claude
pip: pypi.org/project/multi-claude
```

---

## Reddit — r/ClaudeAI

**Title:** `I built an open-source multi-account manager for Claude CLI — switch between accounts instantly, shared settings, cloud backup`

**Body:**
```
Hey everyone,

I got tired of logging in/out of Claude CLI every time I needed to switch
between my work and personal accounts. Claude stores everything in a single
~/.claude/ directory, so you're locked to one account at a time.

So I built **claude-multi-account** — a CLI tool that gives you unlimited
isolated profiles with shared settings.

### What it does

- **Isolated profiles** — each account gets its own config directory
- **Shared MCP servers & settings** — define once, auto-applied to all accounts
- **Global CLAUDE.md** — instructions and skills that work across every account
- **Plugins & marketplace** — manage plugins globally or per-account
- **Direct launch** — run `claude-work` or `claude-personal` directly from terminal
- **Local backup/restore** — timestamped archives with one click
- **Cloud backup/restore** — sync all profiles to cloud, restore on any machine
- **Export/import** — transfer profiles between machines as a single token
- **Auto dependency detection** — installs missing deps on first run

### Install (pick any)

    npm install -g @ghackk/multi-claude
    pip install multi-claude
    brew install ghackk/tap/multi-claude
    scoop install multi-claude

Or one-liner:

    curl -fsSL https://raw.githubusercontent.com/ghackk/claude-multi-account/master/install.sh | bash

Works on **Windows, Linux, macOS, and Termux**.

GitHub: https://github.com/ghackk/claude-multi-account

Built this for myself but figured others might find it useful.
Happy to answer any questions!
```

---

## Reddit — r/commandline

**Title:** `Show r/commandline: multi-claude — manage multiple Claude CLI profiles with shared configs, cloud sync, and direct launch`

**Body:**
```
Claude CLI stores all config in ~/.claude/ — one account at a time.
Switching means logging out, logging in, losing your setup.

I built a shell tool that fixes this:

- Each account gets its own config dir (~/.claude-work, ~/.claude-personal, etc.)
- Shared MCP servers, env vars, plugins deep-merged on every launch
- Profiles auto-registered on PATH — just type `claude-work` directly
- Cloud backup/restore across machines
- Zero dependencies beyond bash + Claude CLI (jq optional for JSON merging)

Written in bash (Linux/macOS/Termux) and PowerShell (Windows).

Install: `npm i -g @ghackk/multi-claude` or `pip install multi-claude`
or `brew install ghackk/tap/multi-claude`

https://github.com/ghackk/claude-multi-account

MIT licensed, feedback welcome.
```

---

## Hacker News

**Title:** `Show HN: Multi-account manager for Claude CLI`

**Body:**
```
Claude CLI stores config in a single ~/.claude/ directory, locking you
to one account. Switching means logging out, logging in, reconfiguring.

I built a tool that creates isolated profiles with shared settings:

- Isolated config directories per account
- Shared MCP servers, env vars, plugins, CLAUDE.md — deep-merged on launch
- Profiles registered on PATH (claude-work, claude-personal as direct commands)
- Cloud backup/restore — sync profiles across machines with a single code
- Export/import via base64 tokens
- Works on Linux, macOS, Windows, Termux

No daemon, no background process. Pure bash + PowerShell scripts.

Available via npm, pip, Homebrew, Scoop, AUR, or curl one-liner.

https://github.com/ghackk/claude-multi-account
```

---

## LinkedIn

```
Just open-sourced a tool I've been building: claude-multi-account

If you use Claude CLI (Claude Code) for work, you've probably hit this wall —
one account at a time. Switch accounts? Log out, log in, lose your settings.

This tool gives you:

- Unlimited isolated profiles
- Shared MCP servers & settings across all accounts
- Global instructions (CLAUDE.md) applied everywhere
- Direct terminal launch — type "claude-work" and go
- Cloud backup & restore across machines
- Works on Windows, Linux, macOS, Termux

Available on npm, pip, Homebrew, and Scoop.

GitHub: https://github.com/ghackk/claude-multi-account

If you're managing multiple Claude accounts for different clients or projects,
give it a try. Feedback and contributions welcome.

#ClaudeCode #Anthropic #DevTools #OpenSource #CLI
```

---

## Discord (short version for showcase channels)

```
multi-claude — manage multiple Claude CLI profiles

Tired of logging in/out? This gives you isolated accounts with shared
MCP servers, plugins, and settings. Profiles work as direct commands
(claude-work, claude-personal). Cloud backup/restore across machines.

npm i -g @ghackk/multi-claude
https://github.com/ghackk/claude-multi-account

Works on Windows/Linux/macOS/Termux. MIT licensed.
```

---

## Dev.to / Hashnode Article

**Title:** `How I Manage 4 Claude CLI Accounts Without Losing My Mind`

**Subtitle:** `An open-source tool for isolated profiles, shared settings, and cloud sync`

**Body:**

```
## The Problem

If you use Claude CLI (Claude Code), you know the pain — everything lives in
`~/.claude/`. One account. One set of settings. Want to switch between work
and personal? Log out, log in, reconfigure your MCP servers, re-apply your
CLAUDE.md instructions.

I have 4 different Claude accounts for different projects. Doing this dance
multiple times a day was killing my productivity.

## The Solution

I built **claude-multi-account** — a CLI tool that creates isolated profiles
with shared settings. Each account gets its own config directory, but MCP
servers, environment variables, plugins, and CLAUDE.md instructions are
defined once and deep-merged into every profile on launch.

## Features

### Multi-Account Management
Create, launch, rename, and delete independent profiles. Each one is fully
isolated — different credentials, different conversation history, zero conflicts.

### Shared Everything
Define your MCP servers, env vars, and plugins in `~/claude-shared/settings.json`.
Write your global instructions in `~/claude-shared/CLAUDE.md`. They're automatically
applied to every account on launch.

### Direct Launch
Every profile is registered on your PATH. No menu needed — just type:

    claude-work
    claude-personal
    claude-client-xyz

### Cloud Backup & Restore
Sync all your profiles to the cloud. Get a code. Enter it on another machine.
Done — all accounts, settings, and launchers restored instantly.

### Export/Import Tokens
Transfer a single profile between machines as a copy-paste token. Credentials,
settings, launcher — all bundled in ~5 KB of base64.

### Auto Dependencies
First run detects your package manager (apt, brew, pacman, dnf, pkg) and
offers to install missing dependencies automatically.

## Install

Pick your favorite:

    npm install -g @ghackk/multi-claude
    pip install multi-claude
    brew install ghackk/tap/multi-claude
    scoop install multi-claude

Or the one-liner:

    curl -fsSL https://raw.githubusercontent.com/ghackk/claude-multi-account/master/install.sh | bash

## How It Works

Each account gets a directory: `~/.claude-work`, `~/.claude-personal`, etc.
On every launch, shared settings from `~/claude-shared/` are deep-merged:

| Scenario                              | Result              |
|---------------------------------------|---------------------|
| Key exists only in account            | Kept                |
| Key exists only in shared             | Added               |
| Key exists in both (simple value)     | Shared wins         |
| Key exists in both (nested object)    | Recursively merged  |

For CLAUDE.md, shared content is inserted between auto-managed markers.
Account-specific instructions below the markers are preserved.

## Cross-Platform

Works on Windows (PowerShell), Linux, macOS, and Termux (Android).
Written in bash and PowerShell — no compiled binaries, no runtime dependencies.

GitHub: https://github.com/ghackk/claude-multi-account

MIT licensed. Contributions welcome!
```

---

## YouTube — Video Description

```
Multi-Claude: Manage Multiple Claude CLI Accounts | Open Source Tool

Tired of logging in and out of Claude CLI every time you switch accounts? Meet multi-claude — an open-source tool that lets you run unlimited Claude CLI profiles with shared settings, cloud backup, and one-command launch.

FEATURES:
00:00 — Intro: The problem with Claude CLI
00:30 — Installing multi-claude
01:00 — Creating your first account
01:30 — Switching between accounts
02:00 — Shared MCP servers & CLAUDE.md
02:30 — Direct launch from terminal
03:00 — Cloud backup & restore
03:30 — Export/import profile tokens
04:00 — Plugins & marketplace
04:30 — Cross-platform support

INSTALL:
npm install -g @ghackk/multi-claude
pip install multi-claude
brew install ghackk/tap/multi-claude
scoop install multi-claude

LINKS:
GitHub: https://github.com/ghackk/claude-multi-account
npm: https://www.npmjs.com/package/@ghackk/multi-claude
PyPI: https://pypi.org/project/multi-claude/

#ClaudeCode #ClaudeCLI #Anthropic #DevTools #OpenSource #MultiAccount #CLI #Programming #AI #AICoding
```

---

## YouTube — Video Title Options

```
1. I Built a Multi-Account Manager for Claude CLI (Open Source)
2. Manage Multiple Claude CLI Accounts — No More Logging In/Out
3. claude-multi-account: Switch Claude CLI Profiles Instantly
4. Stop Logging In and Out of Claude CLI — Use This Instead
5. How to Run Multiple Claude Code Accounts on One Machine
```

---

## YouTube — Pinned Comment

```
Links:
GitHub: https://github.com/ghackk/claude-multi-account
npm: https://www.npmjs.com/package/@ghackk/multi-claude
PyPI: https://pypi.org/project/multi-claude/

Install in one line:
npm install -g @ghackk/multi-claude

Star the repo if you find it useful! Let me know what features you'd like to see next.
```

---

## YouTube Shorts / Instagram Reels / TikTok

### Short 1 — The Hook
```
POV: You have 4 Claude CLI accounts and you're tired of logging in/out

*shows logging out, logging in, losing settings*

There's a better way.

npm install -g @ghackk/multi-claude

*shows menu with all accounts*
*types claude-work directly*

Multi-claude. Open source. Link in bio.

#ClaudeCode #DevTools #Programming #AI #OpenSource
```

### Short 2 — Cloud Backup
```
Back up ALL your Claude CLI accounts to the cloud in 10 seconds

*shows cloud backup flow*
*shows backup code*

Now restore on any machine:

*shows restore on different terminal*

All accounts, settings, plugins — restored.

github.com/ghackk/claude-multi-account

#ClaudeCode #CloudBackup #DevTools
```

### Short 3 — Direct Launch
```
You don't need a menu to switch Claude accounts.

Just type the name:

$ claude-work
$ claude-personal
$ claude-client

Each one is isolated. Shared MCP servers. Global CLAUDE.md.

npm install -g @ghackk/multi-claude

#ClaudeCode #CLI #DevTools
```

---

## Reddit — r/programming

**Title:** `Show r/programming: Built a multi-account manager for Claude CLI in bash/PowerShell — isolated profiles, shared configs, cloud sync`

**Body:**
```
Claude Code (Claude CLI) stores everything in ~/.claude/ — one account at a time.
If you work with multiple accounts (work, personal, clients), switching is painful.

I wrote a tool in bash + PowerShell that creates isolated config directories per
account and deep-merges shared settings on every launch:

Technical details:
- Pure bash (Unix) + PowerShell (Windows), no compiled dependencies
- JSON deep-merge for settings (jq on Unix, ConvertFrom-Json on Windows)
- Symlinks in ~/.local/bin for direct PATH registration (Unix)
- User PATH env var modification for Windows
- Base64 + gzip profile export/import tokens
- Cloud backup via HTTP API with one-time-use codes
- Auto package manager detection (apt/brew/dnf/pacman/apk/pkg)

Available on npm, pip, Homebrew, Scoop, AUR.

https://github.com/ghackk/claude-multi-account

MIT licensed. Written for myself, sharing in case others need it.
```

---

## Reddit — r/artificial

**Title:** `Open-source tool for managing multiple Claude CLI (Claude Code) accounts — shared MCP servers, cloud backup, direct launch`

**Body:**
```
If you're using Claude Code for AI-assisted development across multiple projects
or teams, you've probably hit the one-account limitation.

I built multi-claude — manages unlimited Claude CLI profiles with:

- Isolated configs (no cross-contamination between projects)
- Shared MCP servers defined once, applied everywhere
- Global CLAUDE.md instructions across all accounts
- Cloud backup/restore (move profiles between machines)
- Direct terminal launch (claude-work, claude-client, etc.)
- Plugin management across accounts

Useful if you're a consultant working with multiple clients, have separate
work/personal accounts, or manage team setups.

Install: npm i -g @ghackk/multi-claude
GitHub: https://github.com/ghackk/claude-multi-account
```

---

## Reddit — r/selfhosted

**Title:** `Self-hosted cloud backup for Claude CLI profiles — sync accounts across machines with one code`

**Body:**
```
Part of a larger tool (multi-claude) but thought the self-hosted crowd might
appreciate this: cloud backup/restore for Claude CLI profiles.

- Backup all your Claude CLI accounts to a self-hosted server
- Get a one-time-use code
- Enter it on any other machine to restore everything
- Profiles, credentials, settings, launchers — all restored
- Code expires after 10 minutes, single use

The pairing server is a simple Node.js HTTP server (~300 lines). Data is stored
temporarily on disk, encrypted in transit, and deleted after fetch.

The full tool also handles multi-account management, shared MCP servers,
plugin management, and direct profile launching.

GitHub: https://github.com/ghackk/claude-multi-account
```

---

## Reddit — r/Anthropic

**Title:** `Built a multi-account manager for Claude Code — open source, works on all platforms`

**Body:**
```
If you use Claude Code (Claude CLI) and need to switch between accounts,
you know the pain. Everything is in ~/.claude/ — one account at a time.

multi-claude fixes this:

- Create unlimited isolated profiles
- Shared MCP servers, plugins, CLAUDE.md across all accounts
- Type "claude-work" directly from terminal — no menu needed
- Cloud backup & restore across machines
- Export/import profiles as tokens
- Works on Windows, Linux, macOS, Termux

Install: npm i -g @ghackk/multi-claude

GitHub: https://github.com/ghackk/claude-multi-account
npm: https://www.npmjs.com/package/@ghackk/multi-claude

Happy to answer questions!
```

---

## Product Hunt — Tagline & Description

**Tagline:**
```
Manage multiple Claude CLI accounts with shared settings and cloud sync
```

**Description:**
```
Claude CLI (Claude Code) locks you to one account at a time. multi-claude gives you unlimited isolated profiles with shared MCP servers, plugins, and CLAUDE.md — all from one command.

Key features:
- Isolated profiles — no config conflicts between accounts
- Shared settings — define MCP servers, plugins, CLAUDE.md once
- Direct launch — type "claude-work" from any terminal
- Cloud backup & restore — sync profiles across machines
- Export/import — transfer profiles as copy-paste tokens
- Cross-platform — Windows, Linux, macOS, Termux

Available on npm, pip, Homebrew, Scoop, and AUR.
Open source, MIT licensed.
```

**First Comment (maker):**
```
Hey Product Hunt! I built multi-claude because I was tired of logging in/out
of Claude CLI multiple times a day. I work with 4 different accounts across
different projects, and the constant switching was killing my productivity.

The tool is written in pure bash + PowerShell — no compiled binaries, no
daemon, no background processes. Each account gets its own config directory,
and shared settings (MCP servers, plugins, CLAUDE.md) are deep-merged on
every launch.

My favorite feature is direct launch — after creating an account, you can
just type "claude-work" from any terminal. No menu needed.

Would love your feedback! What features would you want to see next?
```

---

## Indie Hackers

```
I built an open-source tool for managing multiple Claude CLI accounts

Problem: Claude CLI stores everything in one directory. One account at a time.
Switching = logout, login, reconfigure.

Solution: multi-claude — unlimited isolated profiles with shared settings.

What makes it different:
- Pure shell scripts (bash + PowerShell) — zero dependencies
- Shared MCP servers, plugins, CLAUDE.md across all accounts
- Direct launch from terminal (claude-work, claude-personal)
- Cloud backup/restore across machines
- Available on npm, pip, Homebrew, Scoop, AUR

Built it for myself, open-sourced it, now it's on 5 package managers.

GitHub: https://github.com/ghackk/claude-multi-account
npm: https://www.npmjs.com/package/@ghackk/multi-claude

Curious if others are hitting the same pain point. What would you add?
```

---

## Stack Overflow — Tag Wiki / Answer Template

**For questions like "How to use multiple Claude CLI accounts?":**

```
You can use [multi-claude](https://github.com/ghackk/claude-multi-account),
an open-source tool that creates isolated profiles for Claude CLI.

Install:

    npm install -g @ghackk/multi-claude

Then run `multi-claude` to create and manage accounts. Each profile gets its
own config directory, and you can define shared MCP servers and CLAUDE.md
instructions that apply to all accounts.

You can also launch profiles directly:

    claude-work      # launches work profile
    claude-personal  # launches personal profile
```

---

## Forum / Community Comments (drop in relevant threads)

### Comment 1 — When someone mentions Claude CLI account switching
```
If you're switching between Claude CLI accounts frequently, check out
multi-claude — it creates isolated profiles so you don't have to
log out/in. Just type "claude-work" or "claude-personal" directly.

npm i -g @ghackk/multi-claude
https://github.com/ghackk/claude-multi-account
```

### Comment 2 — When someone asks about MCP server management
```
I manage MCP servers across multiple Claude accounts using multi-claude.
You define them once in ~/claude-shared/settings.json and they get
deep-merged into every account on launch. Saves a ton of time.

https://github.com/ghackk/claude-multi-account
```

### Comment 3 — When someone asks about backing up Claude settings
```
multi-claude has built-in cloud backup — backs up all your profiles,
settings, and credentials. Gives you a one-time code to restore on
any other machine. Also has local backup with timestamped archives.

https://github.com/ghackk/claude-multi-account
```

### Comment 4 — When someone mentions CLAUDE.md management
```
If you want the same CLAUDE.md instructions across multiple accounts,
multi-claude handles this — you write a global CLAUDE.md that gets
auto-merged into every profile. Account-specific additions are preserved.

https://github.com/ghackk/claude-multi-account
```

### Comment 5 — General AI tools thread
```
Been using multi-claude to manage my Claude CLI accounts — lets you
run unlimited profiles with shared MCP servers, plugins, and cloud sync.
Open source, works on all platforms.

github.com/ghackk/claude-multi-account
```

---

## Bluesky

```
Built an open-source tool to manage multiple Claude CLI accounts.

Isolated profiles. Shared MCP servers. Cloud backup. Direct launch.

Works on Windows, Linux, macOS, Termux.

github.com/ghackk/claude-multi-account

#ClaudeCode #OpenSource #DevTools
```

---

## Mastodon

```
Just released multi-claude — an open-source multi-account manager
for Claude CLI (Claude Code).

If you're tired of logging in/out to switch accounts, this gives you
isolated profiles with shared settings, cloud backup, and direct
terminal launch.

Written in bash + PowerShell. No dependencies. MIT licensed.

github.com/ghackk/claude-multi-account

#ClaudeCode #OpenSource #DevTools #CLI #FOSS
```

---

## Medium Article Title Options

```
1. How I Manage Multiple Claude CLI Accounts Without Going Insane
2. The Missing Multi-Account Feature in Claude Code (And How I Built It)
3. Stop Logging Out of Claude CLI — Build Isolated Profiles Instead
4. I Open-Sourced My Claude CLI Account Manager — Here's How It Works
5. Multi-Claude: The Tool Every Claude Code Power User Needs
```
