$ACCOUNTS_DIR             = "$HOME\claude-accounts"
$BACKUP_DIR               = "$HOME\claude-backups"
$SHARED_DIR               = "$HOME\claude-shared"
$SHARED_SETTINGS          = "$SHARED_DIR\settings.json"
$SHARED_CLAUDE            = "$SHARED_DIR\CLAUDE.md"
$SHARED_PLUGINS_DIR       = "$SHARED_DIR\plugins"
$SHARED_MARKETPLACES_DIR  = "$SHARED_PLUGINS_DIR\marketplaces"
$PAIR_SERVER              = "https://pair.ghackk.com"

# ─── ENSURE CLAUDE CLI INSTALLED ────────────────────────────────────────────

function Ensure-ClaudeInstalled {
    if (Get-Command claude -ErrorAction SilentlyContinue) { return }

    Write-Host ""
    Write-Host "  Claude CLI is not installed." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Detected system:" -ForegroundColor Cyan
    Write-Host "    OS:   Windows $([System.Environment]::OSVersion.Version)" -ForegroundColor White
    Write-Host "    Arch: $env:PROCESSOR_ARCHITECTURE" -ForegroundColor White

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "    Pkg:  WinGet" -ForegroundColor White
    }
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host "    Pkg:  Scoop" -ForegroundColor White
    }
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        Write-Host "    Pkg:  npm" -ForegroundColor White
    }

    Write-Host ""
    $choice = Read-Host "  Install Claude CLI now? (y/n)"
    if ($choice -ne "y") {
        Write-Host "  Claude CLI is required. Exiting." -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "  Installing Claude CLI..." -ForegroundColor Gray

    # Try native installer first
    try {
        Write-Host "  Trying native installer..." -ForegroundColor Gray
        Invoke-Expression (Invoke-RestMethod -Uri "https://claude.ai/install.ps1" -ErrorAction Stop)
        # Refresh PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
        if (Get-Command claude -ErrorAction SilentlyContinue) {
            Write-Host "  Claude CLI installed successfully!" -ForegroundColor Green
            return
        }
    } catch {
        Write-Host "  Native installer failed: $_" -ForegroundColor Gray
    }

    # Try WinGet
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "  Trying WinGet..." -ForegroundColor Gray
        try {
            winget install Anthropic.ClaudeCode --accept-source-agreements --accept-package-agreements 2>$null
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
            if (Get-Command claude -ErrorAction SilentlyContinue) {
                Write-Host "  Claude CLI installed via WinGet!" -ForegroundColor Green
                return
            }
        } catch {}
    }

    # Try npm
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        Write-Host "  Trying npm..." -ForegroundColor Gray
        try {
            npm install -g @anthropic-ai/claude-code 2>$null
            if (Get-Command claude -ErrorAction SilentlyContinue) {
                Write-Host "  Claude CLI installed via npm!" -ForegroundColor Green
                return
            }
        } catch {}
    }

    Write-Host ""
    Write-Host "  Automatic install failed." -ForegroundColor Red
    Write-Host "  Manual install options:" -ForegroundColor White
    Write-Host "    irm https://claude.ai/install.ps1 | iex" -ForegroundColor Gray
    Write-Host "    winget install Anthropic.ClaudeCode" -ForegroundColor Gray
    Write-Host "    npm install -g @anthropic-ai/claude-code" -ForegroundColor Gray
    Write-Host ""
    pause
}

Ensure-ClaudeInstalled

# ─── ENSURE DIRECTORIES EXIST ───────────────────────────────────────────────

if (!(Test-Path $ACCOUNTS_DIR)) { New-Item -ItemType Directory -Path $ACCOUNTS_DIR | Out-Null }
if (!(Test-Path $BACKUP_DIR))   { New-Item -ItemType Directory -Path $BACKUP_DIR   | Out-Null }

# ─── DISPLAY ─────────────────────────────────────────────────────────────────

function Show-Header {
    Clear-Host
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host "       Claude Account Manager         " -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host ""
}

# ─── ACCOUNT HELPERS ─────────────────────────────────────────────────────────

function Get-Accounts {
    return Get-ChildItem "$ACCOUNTS_DIR\claude-*.bat" -Exclude "claude-menu.bat" -ErrorAction SilentlyContinue
}

function Show-Accounts {
    $accounts = Get-Accounts
    if ($accounts.Count -eq 0) {
        Write-Host "  No accounts found." -ForegroundColor Yellow
        return $accounts
    }
    $i = 1
    foreach ($f in $accounts) {
        $name = $f.BaseName
        $configDir = "$HOME\.$name"
        $loggedIn = if (Test-Path $configDir) { "[logged in]" } else { "[not logged in]" }
        $lastUsed = if (Test-Path $configDir) {
            $d = (Get-Item $configDir).LastWriteTime
            "last used: $($d.ToString('dd MMM yyyy hh:mm tt'))"
        } else { "never used" }
        Write-Host "  $i. $name  $loggedIn  ($lastUsed)" -ForegroundColor White
        $i++
    }
    return $accounts
}

function Pick-Accounts($prompt, $single = $false) {
    $accounts = Get-Accounts
    if ($accounts.Count -eq 0) { return $null }
    Write-Host ""
    if ($single) {
        Write-Host "  (enter number)" -ForegroundColor Gray
    } else {
        Write-Host "  (enter number or comma separated e.g. 1,2,3)" -ForegroundColor Gray
    }
    $userInput = Read-Host $prompt
    $selected = @()
    $parts = $userInput -split "," | ForEach-Object { $_.Trim() }
    foreach ($part in $parts) {
        $index = [int]$part - 1
        if ($index -lt 0 -or $index -ge $accounts.Count) {
            Write-Host "  Skipping invalid choice: $part" -ForegroundColor Yellow
        } else {
            $selected += $accounts[$index]
        }
    }
    if ($selected.Count -eq 0) { return $null }
    return $selected
}

# ─── DEEP MERGE (shared wins on conflict) ────────────────────────────────────

function Merge-JsonObjects($base, $override) {
    if ($null -eq $base)     { return $override }
    if ($null -eq $override) { return $base }

    $result = $base.PSObject.Copy()
    foreach ($prop in $override.PSObject.Properties) {
        $key = $prop.Name
        $overrideVal = $prop.Value
        if ($result.PSObject.Properties[$key]) {
            $baseVal = $result.$key
            if ($baseVal -is [PSCustomObject] -and $overrideVal -is [PSCustomObject]) {
                $result.$key = Merge-JsonObjects $baseVal $overrideVal
            } else {
                $result.$key = $overrideVal
            }
        } else {
            $result | Add-Member -MemberType NoteProperty -Name $key -Value $overrideVal
        }
    }
    return $result
}

# ─── SHARED DIR SETUP ────────────────────────────────────────────────────────

function Ensure-SharedDir {
    if (!(Test-Path $SHARED_DIR)) {
        New-Item -ItemType Directory -Path $SHARED_DIR | Out-Null
    }
    # Create default shared settings.json if missing
    if (!(Test-Path $SHARED_SETTINGS)) {
        [PSCustomObject]@{
            mcpServers              = [PSCustomObject]@{}
            env                     = [PSCustomObject]@{}
            preferences             = [PSCustomObject]@{}
            enabledPlugins          = [PSCustomObject]@{}
            extraKnownMarketplaces  = [PSCustomObject]@{}
        } | ConvertTo-Json -Depth 10 | ForEach-Object { Write-JsonNoBOM $SHARED_SETTINGS $_ }
    } else {
        # Migrate existing shared settings to include new fields if missing
        $s = Get-Content $SHARED_SETTINGS -Raw | ConvertFrom-Json
        $changed = $false
        foreach ($field in @('enabledPlugins','extraKnownMarketplaces')) {
            if (-not $s.PSObject.Properties[$field]) {
                $s | Add-Member -MemberType NoteProperty -Name $field -Value ([PSCustomObject]@{})
                $changed = $true
            }
        }
        if ($changed) { Write-JsonNoBOM $SHARED_SETTINGS ($s | ConvertTo-Json -Depth 10) }
    }
    # Create shared plugins/marketplaces dirs
    if (!(Test-Path $SHARED_PLUGINS_DIR))      { New-Item -ItemType Directory -Path $SHARED_PLUGINS_DIR      | Out-Null }
    if (!(Test-Path $SHARED_MARKETPLACES_DIR)) { New-Item -ItemType Directory -Path $SHARED_MARKETPLACES_DIR | Out-Null }
    # Create empty CLAUDE.md if missing
    if (!(Test-Path $SHARED_CLAUDE)) {
        @"
# Shared Claude Instructions (Skills)
# This file is automatically applied to ALL accounts.
# Add your custom behaviors, personas, or skill instructions below.

"@ | Set-Content $SHARED_CLAUDE -Encoding UTF8
    }
}

# ─── SYNC SHARED INTO ONE ACCOUNT ───────────────────────────────────────────

function Merge-SharedIntoAccount($accountName) {
    Ensure-SharedDir
    $configDir = "$HOME\.$accountName"
    if (!(Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir | Out-Null
    }

    # --- Merge settings.json (MCP, env, preferences) ---
    $settingsPath = "$configDir\settings.json"
    $shared = Get-Content $SHARED_SETTINGS -Raw | ConvertFrom-Json

    if (Test-Path $settingsPath) {
        $accountSettings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    } else {
        $accountSettings = [PSCustomObject]@{}
    }

    $merged = Merge-JsonObjects $accountSettings $shared
    Write-JsonNoBOM $settingsPath ($merged | ConvertTo-Json -Depth 10)

    # --- Sync marketplace indexes from shared dir ---
    $accountPluginsDir      = "$configDir\plugins"
    $accountMarketplacesDir = "$accountPluginsDir\marketplaces"
    if (!(Test-Path $accountPluginsDir))      { New-Item -ItemType Directory -Path $accountPluginsDir      | Out-Null }
    if (!(Test-Path $accountMarketplacesDir)) { New-Item -ItemType Directory -Path $accountMarketplacesDir | Out-Null }

    # Copy each shared marketplace index into account
    if (Test-Path $SHARED_MARKETPLACES_DIR) {
        Get-ChildItem $SHARED_MARKETPLACES_DIR -Directory | ForEach-Object {
            $mktName    = $_.Name
            $destMktDir = "$accountMarketplacesDir\$mktName"
            if (!(Test-Path $destMktDir)) { New-Item -ItemType Directory -Path $destMktDir | Out-Null }
            Copy-Item "$($_.FullName)\*" $destMktDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Seed / update account known_marketplaces.json from shared extraKnownMarketplaces
    $knownMktPath = "$accountPluginsDir\known_marketplaces.json"
    $sharedMkts   = if ($merged.PSObject.Properties['extraKnownMarketplaces']) { $merged.extraKnownMarketplaces } else { $null }
    if ($sharedMkts) {
        $knownMkts = if (Test-Path $knownMktPath) {
            Get-Content $knownMktPath -Raw | ConvertFrom-Json
        } else { [PSCustomObject]@{} }

        foreach ($prop in $sharedMkts.PSObject.Properties) {
            $mktName = $prop.Name
            $installLoc = "$accountMarketplacesDir\$mktName"
            if (-not $knownMkts.PSObject.Properties[$mktName]) {
                $entry = [PSCustomObject]@{
                    source          = $prop.Value.source
                    installLocation = $installLoc
                    lastUpdated     = (Get-Date -Format "o")
                }
                $knownMkts | Add-Member -MemberType NoteProperty -Name $mktName -Value $entry
            }
        }
        Write-JsonNoBOM $knownMktPath ($knownMkts | ConvertTo-Json -Depth 10)
    }

    # --- Copy CLAUDE.md (skills/instructions) ---
    $sharedClaudeContent = Get-Content $SHARED_CLAUDE -Raw -ErrorAction SilentlyContinue
    $accountClaudePath   = "$configDir\CLAUDE.md"

    if (![string]::IsNullOrWhiteSpace($sharedClaudeContent)) {
        if (Test-Path $accountClaudePath) {
            # Read existing, strip old shared block if present, then prepend fresh
            $existing = Get-Content $accountClaudePath -Raw
            $marker   = "# ===== SHARED INSTRUCTIONS (auto-managed) ====="
            $endMarker = "# ===== END SHARED INSTRUCTIONS ====="
            if ($existing -match [regex]::Escape($marker)) {
                # Remove old shared block
                $existing = $existing -replace "(?s)$([regex]::Escape($marker)).*?$([regex]::Escape($endMarker))\r?\n?", ""
            }
            $newContent = "$marker`n$sharedClaudeContent`n$endMarker`n`n$existing"
            $newContent | Set-Content $accountClaudePath -Encoding UTF8
        } else {
            # No existing file, just write shared content
            $marker    = "# ===== SHARED INSTRUCTIONS (auto-managed) ====="
            $endMarker = "# ===== END SHARED INSTRUCTIONS ====="
            "$marker`n$sharedClaudeContent`n$endMarker`n" | Set-Content $accountClaudePath -Encoding UTF8
        }
    }
}

# ─── SYNC ALL ACCOUNTS ───────────────────────────────────────────────────────

function Sync-AllAccounts {
    $accounts = Get-Accounts
    if ($accounts.Count -eq 0) {
        Write-Host "  No accounts to sync." -ForegroundColor Yellow
        return
    }
    foreach ($acc in $accounts) {
        Merge-SharedIntoAccount $acc.BaseName
        Write-Host "  Synced -> $($acc.BaseName)" -ForegroundColor Green
    }
}

# ─── MANAGE SHARED SETTINGS MENU ─────────────────────────────────────────────

function Manage-SharedSettings {
    while ($true) {
        Show-Header
        Ensure-SharedDir
        Write-Host "SHARED SETTINGS" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "  These apply to ALL accounts automatically on launch." -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Shared folder: $SHARED_DIR" -ForegroundColor Gray
        Write-Host ""

        # Quick summary
        $shared  = Get-Content $SHARED_SETTINGS -Raw | ConvertFrom-Json
        $mcpCount = ($shared.mcpServers.PSObject.Properties | Measure-Object).Count
        $envCount = ($shared.env.PSObject.Properties | Measure-Object).Count
        $claudeMd = Get-Content $SHARED_CLAUDE -Raw -ErrorAction SilentlyContinue
        $skillLines = if ($claudeMd) { ($claudeMd -split "`n").Count } else { 0 }

        Write-Host "  Summary:" -ForegroundColor Cyan
        Write-Host "    MCP Servers  : $mcpCount configured" -ForegroundColor White
        Write-Host "    Env Vars     : $envCount configured" -ForegroundColor White
        Write-Host "    CLAUDE.md    : $skillLines lines (skills/instructions)" -ForegroundColor White
        Write-Host ""
        Write-Host "======================================" -ForegroundColor Cyan
        Write-Host "  1. Edit MCP + Settings (Notepad)   " -ForegroundColor White
        Write-Host "  2. Edit Skills/Instructions (Notepad)" -ForegroundColor White
        Write-Host "  3. View current shared settings    " -ForegroundColor White
        Write-Host "  4. Sync shared -> ALL accounts NOW " -ForegroundColor White
        Write-Host "  5. Show MCP server list            " -ForegroundColor White
        Write-Host "  6. Reset shared settings (clear)   " -ForegroundColor White
        Write-Host "  0. Back                            " -ForegroundColor White
        Write-Host "======================================" -ForegroundColor Cyan
        Write-Host ""

        $choice = Read-Host "  Pick an option"
        switch ($choice) {
            "1" {
                Write-Host "  Opening settings.json in Notepad..." -ForegroundColor Cyan
                Write-Host "  TIP: Add MCP servers, env vars, preferences here." -ForegroundColor Yellow
                Write-Host "  After saving, use option 4 to push to all accounts." -ForegroundColor Yellow
                Start-Process notepad $SHARED_SETTINGS -Wait
                pause
            }
            "2" {
                Write-Host "  Opening CLAUDE.md in Notepad..." -ForegroundColor Cyan
                Write-Host "  TIP: Write your skills, personas, or global instructions here." -ForegroundColor Yellow
                Write-Host "  After saving, use option 4 to push to all accounts." -ForegroundColor Yellow
                Start-Process notepad $SHARED_CLAUDE -Wait
                pause
            }
            "3" {
                Show-Header
                Write-Host "SHARED SETTINGS.JSON" -ForegroundColor Magenta
                Write-Host ""
                Get-Content $SHARED_SETTINGS | Write-Host
                Write-Host ""
                Write-Host "SHARED CLAUDE.MD (Skills)" -ForegroundColor Magenta
                Write-Host ""
                Get-Content $SHARED_CLAUDE | Write-Host
                Write-Host ""
                pause
            }
            "4" {
                Write-Host ""
                Write-Host "  Syncing to all accounts..." -ForegroundColor Cyan
                Sync-AllAccounts
                Write-Host ""
                Write-Host "  All accounts updated!" -ForegroundColor Green
                pause
            }
            "5" {
                Show-Header
                Write-Host "MCP SERVERS" -ForegroundColor Magenta
                Write-Host ""
                $s = Get-Content $SHARED_SETTINGS -Raw | ConvertFrom-Json
                $props = $s.mcpServers.PSObject.Properties
                if (($props | Measure-Object).Count -eq 0) {
                    Write-Host "  No MCP servers configured yet." -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "  To add one, use option 1 and add to the mcpServers block like:" -ForegroundColor Gray
                    Write-Host '  "mcpServers": { "myserver": { "command": "npx", "args": ["-y", "my-mcp-package"] } }' -ForegroundColor Gray
                } else {
                    foreach ($p in $props) {
                        Write-Host "  - $($p.Name)" -ForegroundColor Green
                        if ($p.Value.command) {
                            Write-Host "    command: $($p.Value.command)" -ForegroundColor Gray
                        }
                    }
                }
                Write-Host ""
                pause
            }
            "6" {
                Write-Host ""
                $confirm = Read-Host "  Type YES to reset ALL shared settings and CLAUDE.md"
                if ($confirm.Trim() -eq "YES") {
                    $resetObj = [PSCustomObject]@{
                        mcpServers             = [PSCustomObject]@{}
                        env                    = [PSCustomObject]@{}
                        preferences            = [PSCustomObject]@{}
                        enabledPlugins         = [PSCustomObject]@{}
                        extraKnownMarketplaces = [PSCustomObject]@{}
                    }
                    Write-JsonNoBOM $SHARED_SETTINGS ($resetObj | ConvertTo-Json -Depth 10)
                    "# Shared Claude Instructions`n" | Set-Content $SHARED_CLAUDE -Encoding UTF8
                    Write-Host "  Shared settings reset." -ForegroundColor Red
                } else {
                    Write-Host "  Cancelled." -ForegroundColor Gray
                }
                pause
            }
            "0" { return }
            default { Write-Host "  Invalid option." -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

# ─── CORE ACCOUNT FUNCTIONS ───────────────────────────────────────────────────

function Create-Account {
    Show-Header
    Write-Host "CREATE NEW ACCOUNT" -ForegroundColor Green
    Write-Host ""
    $name = Read-Host "  Enter account name (e.g. alpha)"
    $name = $name.Trim().ToLower()

    if ([string]::IsNullOrEmpty($name)) {
        Write-Host "  Name cannot be empty!" -ForegroundColor Red
        pause; return
    }

    if ($name -notmatch '^[a-zA-Z0-9_-]+$') {
        Write-Host "  Name can only contain letters, numbers, hyphens, and underscores." -ForegroundColor Red
        pause; return
    }

    $batFile = "$ACCOUNTS_DIR\claude-$name.bat"
    if (Test-Path $batFile) {
        Write-Host "  Account 'claude-$name' already exists!" -ForegroundColor Yellow
        pause; return
    }

    $content = "@echo off`r`nset CLAUDE_CONFIG_DIR=%USERPROFILE%\.claude-$name`r`nclaude %*"
    [System.IO.File]::WriteAllText($batFile, $content, [System.Text.Encoding]::ASCII)

    # Auto-apply shared settings to brand new account
    Merge-SharedIntoAccount "claude-$name"
    Write-Host "  Shared settings applied automatically." -ForegroundColor Gray

    Write-Host ""
    Write-Host "  Created claude-$name successfully!" -ForegroundColor Green
    Write-Host ""
    $login = Read-Host "  Login now? (y/n)"
    if ($login -eq "y") {
        Write-Host "  Opening claude-$name..." -ForegroundColor Cyan
        & $batFile
    }
}

function Launch-Account {
    Show-Header
    Write-Host "LAUNCH ACCOUNT" -ForegroundColor Green
    Write-Host ""
    Show-Accounts | Out-Null
    $accs = Pick-Accounts "  Pick account(s) to launch" $true
    if ($null -eq $accs) { pause; return }
    foreach ($acc in $accs) {
        # Auto-sync shared settings before every launch
        Write-Host "  Applying shared settings to $($acc.BaseName)..." -ForegroundColor Gray
        Merge-SharedIntoAccount $acc.BaseName
        Write-Host "  Launching $($acc.BaseName)..." -ForegroundColor Cyan
        & $acc.FullName
    }
}

function Rename-Account {
    Show-Header
    Write-Host "RENAME ACCOUNT" -ForegroundColor Green
    Write-Host ""
    Show-Accounts | Out-Null
    $accs = Pick-Accounts "  Pick account(s) to rename"
    if ($null -eq $accs) { pause; return }

    foreach ($acc in $accs) {
        $oldName = $acc.BaseName
        $newSuffix = Read-Host "  Enter new name for $oldName"
        $newSuffix = $newSuffix.Trim().ToLower()
        $newName = "claude-$newSuffix"
        $newBat = "$ACCOUNTS_DIR\$newName.bat"

        if (Test-Path $newBat) {
            Write-Host "  Account '$newName' already exists! Skipping." -ForegroundColor Yellow
            continue
        }

        Rename-Item $acc.FullName $newBat
        (Get-Content $newBat) -replace $oldName, $newName | Set-Content $newBat -Encoding ascii

        $oldConfig = "$HOME\.$oldName"
        $newConfig = "$HOME\.$newName"
        if (Test-Path $oldConfig) { Rename-Item $oldConfig $newConfig }

        Write-Host "  Renamed $oldName to $newName" -ForegroundColor Green
    }
    pause
}

function Delete-Account {
    Show-Header
    Write-Host "DELETE ACCOUNT" -ForegroundColor Red
    Write-Host ""
    Show-Accounts | Out-Null
    $accs = Pick-Accounts "  Pick account(s) to delete"
    if ($null -eq $accs) { pause; return }

    Write-Host ""
    Write-Host "  Accounts selected for deletion:" -ForegroundColor Yellow
    foreach ($acc in $accs) { Write-Host "    - $($acc.BaseName)" -ForegroundColor White }
    Write-Host ""
    $confirm = Read-Host "  Type YES to confirm deleting all selected"

    if ($confirm.Trim() -ne "YES") {
        Write-Host "  Cancelled." -ForegroundColor Gray
        pause; return
    }

    foreach ($acc in $accs) {
        $name = $acc.BaseName
        Remove-Item $acc.FullName -Force
        $configDir = "$HOME\.$name"
        if (Test-Path $configDir) { Remove-Item $configDir -Recurse -Force }
        Write-Host "  Deleted $name" -ForegroundColor Red
    }
    pause
}

function Backup-Sessions {
    Show-Header
    Write-Host "BACKUP SESSIONS" -ForegroundColor Magenta
    Write-Host ""

    if (!(Test-Path $BACKUP_DIR)) { New-Item -ItemType Directory -Path $BACKUP_DIR | Out-Null }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $zipPath = "$BACKUP_DIR\claude-backup-$timestamp.zip"

    # Include accounts dir, shared dir, and all account config dirs
    $toZip = @($ACCOUNTS_DIR, $SHARED_DIR)
    Get-Accounts | ForEach-Object {
        $config = "$HOME\.$($_.BaseName)"
        if (Test-Path $config) { $toZip += $config }
    }

    Compress-Archive -Path $toZip -DestinationPath $zipPath -Force

    Write-Host "  Backup saved to:" -ForegroundColor Green
    Write-Host "  $zipPath" -ForegroundColor White
    pause
}

function Restore-Sessions {
    Show-Header
    Write-Host "RESTORE SESSIONS" -ForegroundColor Magenta
    Write-Host ""

    if (!(Test-Path $BACKUP_DIR)) {
        Write-Host "  No backups found." -ForegroundColor Yellow
        pause; return
    }

    $backups = Get-ChildItem "$BACKUP_DIR\claude-backup-*.zip"
    if ($backups.Count -eq 0) {
        Write-Host "  No backup files found." -ForegroundColor Yellow
        pause; return
    }

    $i = 1
    foreach ($b in $backups) {
        Write-Host "  $i. $($b.Name)" -ForegroundColor White
        $i++
    }

    Write-Host ""
    $choice = Read-Host "  Pick backup number to restore"
    $index = [int]$choice - 1

    if ($index -lt 0 -or $index -ge $backups.Count) {
        Write-Host "  Invalid choice." -ForegroundColor Red
        pause; return
    }

    $selected = $backups[$index]
    Write-Host ""
    Write-Host "  This will overwrite existing accounts and sessions!" -ForegroundColor Yellow
    $confirm = Read-Host "  Continue? (y/n)"

    if ($confirm -ne "y") { Write-Host "  Cancelled." -ForegroundColor Gray; pause; return }

    Expand-Archive -Path $selected.FullName -DestinationPath $HOME -Force
    Write-Host ""
    Write-Host "  Restored from $($selected.Name)" -ForegroundColor Green
    pause
}

# ─── EXPORT / IMPORT PROFILE (TOKEN) ────────────────────────────────────────

# ─── EXPORT/IMPORT HELPERS (used by E/I clipboard and P/R pairing) ──────────

function Build-ExportToken($name) {
    $accounts = Get-Accounts
    $selected = $accounts | Where-Object { $_.BaseName -eq $name }
    if (-not $selected) { return $null }

    $configDir = "$HOME\.$name"
    if (!(Test-Path $configDir)) { return $null }

    $credFile = "$configDir\.credentials.json"
    if (!(Test-Path $credFile)) { return $null }

    $tempDir = "$env:TEMP\claude-export-$name"
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    # Copy auth-essential files only
    $configDest = "$tempDir\config"
    New-Item -ItemType Directory -Path $configDest | Out-Null

    $essentialFiles = @(".credentials.json", ".claude.json", "settings.json", "CLAUDE.md", "mcp-needs-auth-cache.json")
    foreach ($f in $essentialFiles) {
        $src = "$configDir\$f"
        if (Test-Path $src) { Copy-Item $src "$configDest\$f" -Force }
    }

    if (Test-Path "$configDir\session-env") {
        Copy-Item "$configDir\session-env" "$configDest\session-env" -Recurse -Force
    }

    if (Test-Path "$configDir\plugins") {
        New-Item -ItemType Directory -Path "$configDest\plugins" | Out-Null
        $pluginFiles = @("installed_plugins.json", "known_marketplaces.json", "blocklist.json")
        foreach ($f in $pluginFiles) {
            $src = "$configDir\plugins\$f"
            if (Test-Path $src) { Copy-Item $src "$configDest\plugins\$f" -Force }
        }
    }

    Copy-Item $selected.FullName "$tempDir\launcher.bat"
    # Also create Unix launcher for cross-platform compatibility
    $shContent = "#!/bin/bash`nexport CLAUDE_CONFIG_DIR=`"`$HOME/.$name`"`nclaude `"`$@`""
    [System.IO.File]::WriteAllText("$tempDir\launcher.sh", $shContent, (New-Object System.Text.UTF8Encoding $false))
    [System.IO.File]::WriteAllText("$tempDir\profile-name.txt", $name, (New-Object System.Text.UTF8Encoding $false))

    $zipPath = "$env:TEMP\claude-export-$name.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    try {
        Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -CompressionLevel Optimal -Force -ErrorAction Stop
        $zipBytes = [System.IO.File]::ReadAllBytes($zipPath)

        $ms = New-Object System.IO.MemoryStream
        $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionLevel]::Optimal)
        $gz.Write($zipBytes, 0, $zipBytes.Length)
        $gz.Close()
        $gzBytes = $ms.ToArray()
        $ms.Close()

        $b64 = [Convert]::ToBase64String($gzBytes)
        $token = "CLAUDE_TOKEN_GZ:" + $b64 + ":END_TOKEN"
    } catch {
        $token = $null
    } finally {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    }

    return $token
}

function Apply-ImportToken($token) {
    $isGz = $token.StartsWith("CLAUDE_TOKEN_GZ:")
    $isPlain = $token.StartsWith("CLAUDE_TOKEN:")

    if ((-not $isGz -and -not $isPlain) -or -not $token.EndsWith(":END_TOKEN")) {
        Write-Host "  Invalid token format." -ForegroundColor Red
        return $false
    }

    $prefix = if ($isGz) { "CLAUDE_TOKEN_GZ:" } else { "CLAUDE_TOKEN:" }
    $b64 = $token.Substring($prefix.Length)
    $b64 = $b64.Substring(0, $b64.Length - ":END_TOKEN".Length)

    try {
        $rawBytes = [Convert]::FromBase64String($b64)
    } catch {
        Write-Host "  Failed to decode token." -ForegroundColor Red
        return $false
    }

    if ($isGz) {
        try {
            $msIn = New-Object System.IO.MemoryStream(, $rawBytes)
            $gz = New-Object System.IO.Compression.GZipStream($msIn, [System.IO.Compression.CompressionMode]::Decompress)
            $msOut = New-Object System.IO.MemoryStream
            $gz.CopyTo($msOut)
            $gz.Close(); $msIn.Close()
            $zipBytes = $msOut.ToArray()
            $msOut.Close()
        } catch {
            Write-Host "  Failed to decompress token." -ForegroundColor Red
            return $false
        }
    } else {
        $zipBytes = $rawBytes
    }

    $zipPath = "$env:TEMP\claude-import.zip"
    [System.IO.File]::WriteAllBytes($zipPath, $zipBytes)

    $extractDir = "$env:TEMP\claude-import"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    $nameFile = "$extractDir\profile-name.txt"
    if (!(Test-Path $nameFile)) {
        Write-Host "  Invalid token: missing profile name." -ForegroundColor Red
        Remove-Item $extractDir -Recurse -Force
        Remove-Item $zipPath -Force
        return $false
    }
    $nameRaw = [System.IO.File]::ReadAllBytes($nameFile)
    if ($nameRaw.Length -ge 3 -and $nameRaw[0] -eq 0xEF -and $nameRaw[1] -eq 0xBB -and $nameRaw[2] -eq 0xBF) {
        $nameRaw = $nameRaw[3..($nameRaw.Length-1)]
    }
    $name = [System.Text.Encoding]::UTF8.GetString($nameRaw).Trim()

    Write-Host ""
    Write-Host "  Detected profile: $name" -ForegroundColor Cyan

    $configDir = "$HOME\.$name"
    if (Test-Path $configDir) {
        Write-Host "  Profile already exists locally!" -ForegroundColor Yellow
        $confirm = Read-Host "  Overwrite? (y/n)"
        if ($confirm -ne "y") {
            Write-Host "  Cancelled." -ForegroundColor Gray
            Remove-Item $extractDir -Recurse -Force
            Remove-Item $zipPath -Force
            return $false
        }
    }

    $importConfig = "$extractDir\config"
    if (!(Test-Path $importConfig)) {
        Write-Host "  No config found in token." -ForegroundColor Red
        Remove-Item $extractDir -Recurse -Force
        Remove-Item $zipPath -Force
        return $false
    }

    if (!(Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir | Out-Null }

    Get-ChildItem $importConfig -Force | ForEach-Object {
        Copy-Item $_.FullName "$configDir\$($_.Name)" -Recurse -Force
    }
    Write-Host "  Profile restored (credentials, settings, session)" -ForegroundColor Green

    $launcherSrc = "$extractDir\launcher.bat"
    if (!(Test-Path $launcherSrc)) {
        # Cross-platform: generate .bat from profile name if only .sh exists
        $batContent = "@echo off`r`nset CLAUDE_CONFIG_DIR=%USERPROFILE%\.$name`r`nclaude %*"
        $launcherSrc = "$extractDir\launcher.bat"
        [System.IO.File]::WriteAllText($launcherSrc, $batContent)
    }
    $launcherDest = "$ACCOUNTS_DIR\$name.bat"
    if (!(Test-Path $ACCOUNTS_DIR)) { New-Item -ItemType Directory -Path $ACCOUNTS_DIR | Out-Null }
    Copy-Item $launcherSrc $launcherDest -Force
    Write-Host "  Launcher created" -ForegroundColor Green

    Write-Host ""
    Write-Host "  Profile '$name' imported successfully!" -ForegroundColor Green
    Write-Host "  Plugins will auto-install on first launch." -ForegroundColor Gray
    Write-Host "  Run $name to start." -ForegroundColor Cyan

    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    return $true
}

# ─── EXPORT/IMPORT (clipboard) ─────────────────────────────────────────────

function Export-Profile {
    Show-Header
    Write-Host "EXPORT PROFILE (Token)" -ForegroundColor Magenta
    Write-Host ""

    $accounts = Show-Accounts
    if ($accounts.Count -eq 0) { pause; return }

    Write-Host ""
    $choice = Read-Host "  Pick account number to export"
    $index = [int]$choice - 1

    if ($index -lt 0 -or $index -ge $accounts.Count) {
        Write-Host "  Invalid choice." -ForegroundColor Red
        pause; return
    }

    $selected = $accounts[$index]
    $name = $selected.BaseName
    $configDir = "$HOME\.$name"

    if (!(Test-Path $configDir)) {
        Write-Host "  Config dir not found: $configDir" -ForegroundColor Red
        pause; return
    }

    if (!(Test-Path "$configDir\.credentials.json")) {
        Write-Host "  No credentials found for $name - nothing to export." -ForegroundColor Yellow
        pause; return
    }

    Write-Host "  Building token..." -ForegroundColor Gray
    $token = Build-ExportToken $name

    if (-not $token) {
        Write-Host "  Error creating token." -ForegroundColor Red
        pause; return
    }

    Set-Clipboard -Value $token

    Write-Host ""
    Write-Host "  Profile: $name" -ForegroundColor Cyan
    Write-Host "  Token length: $($token.Length) characters" -ForegroundColor Gray
    Write-Host "  Token copied to clipboard!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Press 'c' to copy again, or any key to continue..." -ForegroundColor Gray
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
    if ($key -eq 'c' -or $key -eq 'C') {
        Set-Clipboard -Value $token
        Write-Host "  Copied again!" -ForegroundColor Green
        pause
    }
}

function Import-Profile {
    Show-Header
    Write-Host "IMPORT PROFILE (Token)" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Paste your profile token below:" -ForegroundColor Cyan
    Write-Host ""
    $token = Read-Host "  Token"

    $result = Apply-ImportToken $token
    if (-not $result) {
        pause; return
    }
    pause
}

# ─── PAIR EXPORT/IMPORT (fetch from server, run in memory) ─────────────────

function Pair-Export {
    Show-Header
    Write-Host "PAIR EXPORT — Generate a pairing code" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Fetching pairing script from server..." -ForegroundColor Gray

    try {
        $raw = Invoke-RestMethod -Uri "$PAIR_SERVER/client/pair-export.ps1" -ErrorAction Stop
    } catch {
        Write-Host "  Failed to fetch pairing script: $_" -ForegroundColor Red
        Write-Host "  Is the pairing server online? Check $PAIR_SERVER/api/health" -ForegroundColor Gray
        pause; return
    }
    try {
        $reversed = -join ($raw.ToCharArray() | ForEach-Object -Begin { $a = @() } -Process { $a += $_ } -End { [array]::Reverse($a); $a })
        $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($reversed))
        Invoke-Expression $decoded
    } catch {
        Write-Host "  Pairing export failed: $_" -ForegroundColor Red
        pause
    }
}

function Pair-Import {
    Show-Header
    Write-Host "PAIR IMPORT — Enter a pairing code" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Fetching pairing script from server..." -ForegroundColor Gray

    try {
        $raw = Invoke-RestMethod -Uri "$PAIR_SERVER/client/pair-import.ps1" -ErrorAction Stop
    } catch {
        Write-Host "  Failed to fetch pairing script: $_" -ForegroundColor Red
        Write-Host "  Is the pairing server online? Check $PAIR_SERVER/api/health" -ForegroundColor Gray
        pause; return
    }
    try {
        $reversed = -join ($raw.ToCharArray() | ForEach-Object -Begin { $a = @() } -Process { $a += $_ } -End { [array]::Reverse($a); $a })
        $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($reversed))
        Invoke-Expression $decoded
    } catch {
        Write-Host "  Pairing import failed: $_" -ForegroundColor Red
        pause
    }
}

function Cloud-Backup {
    Show-Header
    Write-Host "CLOUD BACKUP" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Fetching backup script from server..." -ForegroundColor Gray

    try {
        $raw = Invoke-RestMethod -Uri "$PAIR_SERVER/client/pair-backup.ps1" -ErrorAction Stop
        $reversed = -join ($raw.ToCharArray() | ForEach-Object -Begin { $a = @() } -Process { $a += $_ } -End { [array]::Reverse($a); $a })
        $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($reversed))
        Invoke-Expression $decoded
    } catch {
        Write-Host "  Failed to fetch backup script: $_" -ForegroundColor Red
        Write-Host "  Is the pairing server online? Check $PAIR_SERVER/api/health" -ForegroundColor Gray
        pause
    }
}

function Cloud-Restore {
    Show-Header
    Write-Host "CLOUD RESTORE" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Fetching restore script from server..." -ForegroundColor Gray

    try {
        $raw = Invoke-RestMethod -Uri "$PAIR_SERVER/client/pair-restore.ps1" -ErrorAction Stop
        $reversed = -join ($raw.ToCharArray() | ForEach-Object -Begin { $a = @() } -Process { $a += $_ } -End { [array]::Reverse($a); $a })
        $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($reversed))
        Invoke-Expression $decoded
    } catch {
        Write-Host "  Failed to fetch restore script: $_" -ForegroundColor Red
        Write-Host "  Is the pairing server online? Check $PAIR_SERVER/api/health" -ForegroundColor Gray
        pause
    }
}

# ─── PLUGIN & MARKETPLACE HELPERS ────────────────────────────────────────────

function Write-JsonNoBOM($path, $content) {
    $utf8NoBOM = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBOM)
}

function Read-SharedSettings {
    Ensure-SharedDir
    return Get-Content $SHARED_SETTINGS -Raw | ConvertFrom-Json
}

function Write-SharedSettings($obj) {
    Write-JsonNoBOM $SHARED_SETTINGS ($obj | ConvertTo-Json -Depth 10)
}

function Read-AccountSettings($accountName) {
    $path = "$HOME\.$accountName\settings.json"
    if (Test-Path $path) { return Get-Content $path -Raw | ConvertFrom-Json }
    return [PSCustomObject]@{}
}

function Write-AccountSettings($accountName, $obj) {
    $dir = "$HOME\.$accountName"
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    Write-JsonNoBOM "$dir\settings.json" ($obj | ConvertTo-Json -Depth 10)
}

# Pull a marketplace index into the shared dir (copies from the first account that has it)
function Pull-MarketplaceToShared($mktName) {
    $destDir = "$SHARED_MARKETPLACES_DIR\$mktName"
    if (!(Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
    foreach ($acc in (Get-Accounts)) {
        $src = "$HOME\.$($acc.BaseName)\plugins\marketplaces\$mktName"
        if (Test-Path $src) {
            Copy-Item "$src\*" $destDir -Recurse -Force -ErrorAction SilentlyContinue
            return $true
        }
    }
    return $false
}

# List all plugins available in a marketplace (reads from shared dir or any account that has it)
function Get-MarketplacePlugins($mktName) {
    $dirs = @(
        "$SHARED_MARKETPLACES_DIR\$mktName",
        (Get-Accounts | ForEach-Object { "$HOME\.$($_.BaseName)\plugins\marketplaces\$mktName" })
    )
    foreach ($d in $dirs) {
        if (Test-Path "$d\plugins") {
            $plugins = Get-ChildItem "$d\plugins" -Directory | Select-Object -ExpandProperty Name
            $external = if (Test-Path "$d\external_plugins") {
                Get-ChildItem "$d\external_plugins" -Directory | Select-Object -ExpandProperty Name
            } else { @() }
            return @{ plugins = $plugins; external = $external }
        }
    }
    return $null
}

# Get all known marketplace names (shared + all accounts)
function Get-AllMarketplaceNames {
    $names = @{}
    $s = Read-SharedSettings
    if ($s.PSObject.Properties['extraKnownMarketplaces']) {
        $s.extraKnownMarketplaces.PSObject.Properties | ForEach-Object { $names[$_.Name] = "shared" }
    }
    foreach ($acc in (Get-Accounts)) {
        $kp = "$HOME\.$($acc.BaseName)\plugins\known_marketplaces.json"
        if (Test-Path $kp) {
            (Get-Content $kp -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object {
                if (-not $names[$_.Name]) { $names[$_.Name] = $acc.BaseName }
            }
        }
    }
    return $names
}

# Get enabled plugins across shared + all accounts
function Get-AllEnabledPlugins {
    $result = @{}
    $s = Read-SharedSettings
    if ($s.PSObject.Properties['enabledPlugins']) {
        $s.enabledPlugins.PSObject.Properties | ForEach-Object {
            $result[$_.Name] = @{ scope = "shared (all accounts)"; enabled = $_.Value }
        }
    }
    foreach ($acc in (Get-Accounts)) {
        $as = Read-AccountSettings $acc.BaseName
        if ($as.PSObject.Properties['enabledPlugins']) {
            $as.enabledPlugins.PSObject.Properties | ForEach-Object {
                if (-not $result[$_.Name]) {
                    $result[$_.Name] = @{ scope = $acc.BaseName; enabled = $_.Value }
                } elseif ($result[$_.Name].scope -eq "shared (all accounts)") {
                    # already shared, skip
                } else {
                    $result[$_.Name].scope += ", $($acc.BaseName)"
                }
            }
        }
    }
    return $result
}

# ─── MARKETPLACE MANAGEMENT ───────────────────────────────────────────────────

function Manage-Marketplaces {
    while ($true) {
        Show-Header
        Write-Host "MARKETPLACE MANAGEMENT" -ForegroundColor Magenta
        Write-Host ""
        $allMkts = Get-AllMarketplaceNames
        if ($allMkts.Count -eq 0) {
            Write-Host "  No marketplaces found." -ForegroundColor Yellow
        } else {
            Write-Host "  Known Marketplaces:" -ForegroundColor Cyan
            foreach ($kv in $allMkts.GetEnumerator()) {
                $tag = if ($kv.Value -eq "shared") { "[ALL ACCOUNTS]" } else { "[$($kv.Value)]" }
                Write-Host "  - $($kv.Key)  $tag" -ForegroundColor White
            }
        }
        Write-Host ""
        Write-Host "======================================" -ForegroundColor Cyan
        Write-Host "  1. Add marketplace globally        " -ForegroundColor White
        Write-Host "  2. Add marketplace to one account  " -ForegroundColor White
        Write-Host "  3. Remove global marketplace       " -ForegroundColor White
        Write-Host "  4. Sync marketplace indexes now    " -ForegroundColor White
        Write-Host "  5. Pull indexes from accounts      " -ForegroundColor White
        Write-Host "  0. Back                            " -ForegroundColor White
        Write-Host "======================================" -ForegroundColor Cyan
        Write-Host ""

        $choice = Read-Host "  Pick an option"
        switch ($choice) {
            "1" {
                Show-Header
                Write-Host "ADD GLOBAL MARKETPLACE" -ForegroundColor Green
                Write-Host ""
                Write-Host "  This marketplace will be available to ALL accounts." -ForegroundColor Gray
                Write-Host ""
                $mktName = (Read-Host "  Marketplace name (e.g. my-plugins)").Trim()
                if ([string]::IsNullOrEmpty($mktName)) { Write-Host "  Cancelled." -ForegroundColor Gray; pause; break }
                Write-Host "  Source type: [1] GitHub repo  [2] URL" -ForegroundColor Gray
                $srcChoice = Read-Host "  Pick"
                $s = Read-SharedSettings
                if (-not $s.PSObject.Properties['extraKnownMarketplaces']) {
                    $s | Add-Member -MemberType NoteProperty -Name 'extraKnownMarketplaces' -Value ([PSCustomObject]@{})
                }
                if ($srcChoice -eq "1") {
                    $repo = (Read-Host "  GitHub repo (owner/repo)").Trim()
                    if ([string]::IsNullOrEmpty($repo)) { Write-Host "  Cancelled." -ForegroundColor Gray; pause; break }
                    $entry = [PSCustomObject]@{ source = [PSCustomObject]@{ source = "github"; repo = $repo } }
                    $s.extraKnownMarketplaces | Add-Member -MemberType NoteProperty -Name $mktName -Value $entry -Force
                } elseif ($srcChoice -eq "2") {
                    $url = (Read-Host "  URL").Trim()
                    if ([string]::IsNullOrEmpty($url)) { Write-Host "  Cancelled." -ForegroundColor Gray; pause; break }
                    $entry = [PSCustomObject]@{ source = [PSCustomObject]@{ source = "url"; url = $url } }
                    $s.extraKnownMarketplaces | Add-Member -MemberType NoteProperty -Name $mktName -Value $entry -Force
                } else { Write-Host "  Invalid." -ForegroundColor Red; pause; break }
                Write-SharedSettings $s
                Write-Host ""
                Write-Host "  Added '$mktName' globally. Run sync to push to all accounts." -ForegroundColor Green
                pause
            }
            "2" {
                Show-Header
                Write-Host "ADD MARKETPLACE TO ONE ACCOUNT" -ForegroundColor Green
                Write-Host ""
                Show-Accounts | Out-Null
                $accs = Pick-Accounts "  Pick account" $true
                if ($null -eq $accs) { pause; break }
                $acc = $accs[0]
                $mktName = (Read-Host "  Marketplace name").Trim()
                Write-Host "  Source: [1] GitHub  [2] URL" -ForegroundColor Gray
                $srcChoice = Read-Host "  Pick"
                $as = Read-AccountSettings $acc.BaseName
                if (-not $as.PSObject.Properties['extraKnownMarketplaces']) {
                    $as | Add-Member -MemberType NoteProperty -Name 'extraKnownMarketplaces' -Value ([PSCustomObject]@{})
                }
                if ($srcChoice -eq "1") {
                    $repo = (Read-Host "  GitHub repo (owner/repo)").Trim()
                    $entry = [PSCustomObject]@{ source = [PSCustomObject]@{ source = "github"; repo = $repo } }
                    $as.extraKnownMarketplaces | Add-Member -MemberType NoteProperty -Name $mktName -Value $entry -Force
                } elseif ($srcChoice -eq "2") {
                    $url = (Read-Host "  URL").Trim()
                    $entry = [PSCustomObject]@{ source = [PSCustomObject]@{ source = "url"; url = $url } }
                    $as.extraKnownMarketplaces | Add-Member -MemberType NoteProperty -Name $mktName -Value $entry -Force
                } else { Write-Host "  Invalid." -ForegroundColor Red; pause; break }
                Write-AccountSettings $acc.BaseName $as
                Write-Host "  Added '$mktName' to $($acc.BaseName)." -ForegroundColor Green
                pause
            }
            "3" {
                Show-Header
                Write-Host "REMOVE GLOBAL MARKETPLACE" -ForegroundColor Red
                Write-Host ""
                $s = Read-SharedSettings
                if (-not $s.PSObject.Properties['extraKnownMarketplaces'] -or
                    ($s.extraKnownMarketplaces.PSObject.Properties | Measure-Object).Count -eq 0) {
                    Write-Host "  No global marketplaces configured." -ForegroundColor Yellow
                    pause; break
                }
                $mkts = $s.extraKnownMarketplaces.PSObject.Properties | ForEach-Object { $_.Name }
                $i = 1; $mkts | ForEach-Object { Write-Host "  $i. $_" -ForegroundColor White; $i++ }
                Write-Host ""
                $pick = [int](Read-Host "  Pick number") - 1
                if ($pick -lt 0 -or $pick -ge $mkts.Count) { Write-Host "  Invalid." -ForegroundColor Red; pause; break }
                $toRemove = $mkts[$pick]
                $s.extraKnownMarketplaces.PSObject.Properties.Remove($toRemove)
                Write-SharedSettings $s
                Write-Host "  Removed '$toRemove' from global marketplaces." -ForegroundColor Green
                pause
            }
            "4" {
                Write-Host ""
                Write-Host "  Syncing marketplace indexes to all accounts..." -ForegroundColor Cyan
                Sync-AllAccounts
                Write-Host "  Done." -ForegroundColor Green
                pause
            }
            "5" {
                Show-Header
                Write-Host "PULL MARKETPLACE INDEXES FROM ACCOUNTS" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  This copies downloaded marketplace indexes into the shared dir" -ForegroundColor Gray
                Write-Host "  so they can be distributed to other accounts without re-downloading." -ForegroundColor Gray
                Write-Host ""
                $pulled = 0
                (Get-AllMarketplaceNames).Keys | ForEach-Object {
                    $ok = Pull-MarketplaceToShared $_
                    if ($ok) { Write-Host "  Pulled: $_" -ForegroundColor Green; $pulled++ }
                    else     { Write-Host "  Not found locally: $_" -ForegroundColor Yellow }
                }
                if ($pulled -eq 0) { Write-Host "  Nothing pulled." -ForegroundColor Yellow }
                pause
            }
            "0" { return }
            default { Write-Host "  Invalid option." -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

# ─── PLUGIN MANAGEMENT ────────────────────────────────────────────────────────

function Manage-Plugins {
    while ($true) {
        Show-Header
        Write-Host "PLUGINS & MARKETPLACE" -ForegroundColor Magenta
        Write-Host ""

        # Show summary
        $allPlugins = Get-AllEnabledPlugins
        $sharedCount = ($allPlugins.Values | Where-Object { $_.scope -eq "shared (all accounts)" } | Measure-Object).Count
        $specificCount = $allPlugins.Count - $sharedCount
        Write-Host "  Enabled Plugins:" -ForegroundColor Cyan
        Write-Host "    Universal (all accounts) : $sharedCount" -ForegroundColor White
        Write-Host "    Account-specific         : $specificCount" -ForegroundColor White
        Write-Host ""
        if ($allPlugins.Count -gt 0) {
            foreach ($kv in ($allPlugins.GetEnumerator() | Sort-Object Key)) {
                $tag   = if ($kv.Value.scope -eq "shared (all accounts)") { "[ALL]" } else { "[$($kv.Value.scope)]" }
                $color = if ($kv.Value.scope -eq "shared (all accounts)") { "Green" } else { "White" }
                Write-Host "    $($kv.Key)  $tag" -ForegroundColor $color
            }
            Write-Host ""
        }

        Write-Host "======================================" -ForegroundColor Cyan
        Write-Host "  1. Enable plugin for ALL accounts  " -ForegroundColor Green
        Write-Host "  2. Enable plugin for one account   " -ForegroundColor White
        Write-Host "  3. Disable plugin (shared)         " -ForegroundColor White
        Write-Host "  4. Disable plugin (one account)    " -ForegroundColor White
        Write-Host "  5. Browse marketplace plugins      " -ForegroundColor Cyan
        Write-Host "  6. Marketplace Management          " -ForegroundColor Yellow
        Write-Host "  0. Back                            " -ForegroundColor White
        Write-Host "======================================" -ForegroundColor Cyan
        Write-Host ""

        $choice = Read-Host "  Pick an option"
        switch ($choice) {
            "1" {
                Show-Header
                Write-Host "ENABLE PLUGIN FOR ALL ACCOUNTS" -ForegroundColor Green
                Write-Host ""
                Write-Host "  Format: plugin-name@marketplace-name" -ForegroundColor Gray
                Write-Host "  Example: frontend-design@claude-plugins-official" -ForegroundColor Gray
                Write-Host ""

                # Offer to browse if marketplaces available
                $allMkts = Get-AllMarketplaceNames
                if ($allMkts.Count -gt 0) {
                    Write-Host "  Or pick from marketplace:" -ForegroundColor Cyan
                    $mktList = @($allMkts.Keys)
                    $i = 1; $mktList | ForEach-Object { Write-Host "    $i. $_" -ForegroundColor White; $i++ }
                    Write-Host "    0. Enter manually" -ForegroundColor Gray
                    Write-Host ""
                    $mktPick = Read-Host "  Marketplace (0 to enter manually)"
                    if ($mktPick -ne "0" -and $mktPick -match '^\d+$') {
                        $mktIdx  = [int]$mktPick - 1
                        if ($mktIdx -ge 0 -and $mktIdx -lt $mktList.Count) {
                            $selectedMkt = $mktList[$mktIdx]
                            $available   = Get-MarketplacePlugins $selectedMkt
                            if ($available) {
                                Show-Header
                                Write-Host "PLUGINS IN $selectedMkt" -ForegroundColor Cyan
                                Write-Host ""
                                $allAvail = @()
                                if ($available.plugins.Count -gt 0) {
                                    Write-Host "  Official:" -ForegroundColor Green
                                    $available.plugins | ForEach-Object { Write-Host "    - $_" -ForegroundColor White; $allAvail += "$_@$selectedMkt" }
                                }
                                if ($available.external.Count -gt 0) {
                                    Write-Host "  External:" -ForegroundColor Yellow
                                    $available.external | ForEach-Object { Write-Host "    - $_" -ForegroundColor White; $allAvail += "$_@$selectedMkt" }
                                }
                                Write-Host ""
                                $pName = (Read-Host "  Enter plugin name (without @marketplace)").Trim()
                                if ([string]::IsNullOrEmpty($pName)) { pause; break }
                                $pluginKey = "$pName@$selectedMkt"
                            } else {
                                Write-Host "  Marketplace index not downloaded yet. Enter manually." -ForegroundColor Yellow
                                $pluginKey = (Read-Host "  Plugin key (name@marketplace)").Trim()
                            }
                        } else { $pluginKey = (Read-Host "  Plugin key (name@marketplace)").Trim() }
                    } else { $pluginKey = (Read-Host "  Plugin key (name@marketplace)").Trim() }
                } else {
                    $pluginKey = (Read-Host "  Plugin key (name@marketplace)").Trim()
                }

                if ([string]::IsNullOrEmpty($pluginKey)) { Write-Host "  Cancelled." -ForegroundColor Gray; pause; break }
                $s = Read-SharedSettings
                if (-not $s.PSObject.Properties['enabledPlugins']) {
                    $s | Add-Member -MemberType NoteProperty -Name 'enabledPlugins' -Value ([PSCustomObject]@{})
                }
                $s.enabledPlugins | Add-Member -MemberType NoteProperty -Name $pluginKey -Value $true -Force
                Write-SharedSettings $s
                Write-Host ""
                Write-Host "  '$pluginKey' enabled for ALL accounts." -ForegroundColor Green
                Write-Host "  Syncing to all accounts now..." -ForegroundColor Cyan
                Sync-AllAccounts
                Write-Host "  Done. Launch any account to activate." -ForegroundColor Green
                pause
            }
            "2" {
                Show-Header
                Write-Host "ENABLE PLUGIN FOR ONE ACCOUNT" -ForegroundColor Green
                Write-Host ""
                Show-Accounts | Out-Null
                $accs = Pick-Accounts "  Pick account" $true
                if ($null -eq $accs) { pause; break }
                $acc = $accs[0]
                Write-Host ""
                $pluginKey = (Read-Host "  Plugin key (name@marketplace)").Trim()
                if ([string]::IsNullOrEmpty($pluginKey)) { Write-Host "  Cancelled." -ForegroundColor Gray; pause; break }
                $as = Read-AccountSettings $acc.BaseName
                if (-not $as.PSObject.Properties['enabledPlugins']) {
                    $as | Add-Member -MemberType NoteProperty -Name 'enabledPlugins' -Value ([PSCustomObject]@{})
                }
                $as.enabledPlugins | Add-Member -MemberType NoteProperty -Name $pluginKey -Value $true -Force
                Write-AccountSettings $acc.BaseName $as
                Write-Host "  '$pluginKey' enabled for $($acc.BaseName)." -ForegroundColor Green
                pause
            }
            "3" {
                Show-Header
                Write-Host "DISABLE PLUGIN (SHARED)" -ForegroundColor Red
                Write-Host ""
                $s = Read-SharedSettings
                if (-not $s.PSObject.Properties['enabledPlugins'] -or
                    ($s.enabledPlugins.PSObject.Properties | Measure-Object).Count -eq 0) {
                    Write-Host "  No shared plugins configured." -ForegroundColor Yellow
                    pause; break
                }
                $keys = @($s.enabledPlugins.PSObject.Properties | ForEach-Object { $_.Name })
                $i = 1; $keys | ForEach-Object { Write-Host "  $i. $_" -ForegroundColor White; $i++ }
                Write-Host ""
                $pick = [int](Read-Host "  Pick number to disable") - 1
                if ($pick -lt 0 -or $pick -ge $keys.Count) { Write-Host "  Invalid." -ForegroundColor Red; pause; break }
                $toRemove = $keys[$pick]
                $s.enabledPlugins.PSObject.Properties.Remove($toRemove)
                Write-SharedSettings $s
                Write-Host "  '$toRemove' removed from shared. Sync to propagate." -ForegroundColor Green
                $doSync = Read-Host "  Sync to all accounts now? (y/n)"
                if ($doSync -eq "y") { Sync-AllAccounts; Write-Host "  Synced." -ForegroundColor Green }
                pause
            }
            "4" {
                Show-Header
                Write-Host "DISABLE PLUGIN (ONE ACCOUNT)" -ForegroundColor Red
                Write-Host ""
                Show-Accounts | Out-Null
                $accs = Pick-Accounts "  Pick account" $true
                if ($null -eq $accs) { pause; break }
                $acc = $accs[0]
                $as  = Read-AccountSettings $acc.BaseName
                if (-not $as.PSObject.Properties['enabledPlugins'] -or
                    ($as.enabledPlugins.PSObject.Properties | Measure-Object).Count -eq 0) {
                    Write-Host "  No plugins configured for $($acc.BaseName)." -ForegroundColor Yellow
                    pause; break
                }
                $keys = @($as.enabledPlugins.PSObject.Properties | ForEach-Object { $_.Name })
                $i = 1; $keys | ForEach-Object { Write-Host "  $i. $_" -ForegroundColor White; $i++ }
                Write-Host ""
                $pick = [int](Read-Host "  Pick number") - 1
                if ($pick -lt 0 -or $pick -ge $keys.Count) { Write-Host "  Invalid." -ForegroundColor Red; pause; break }
                $toRemove = $keys[$pick]
                $as.enabledPlugins.PSObject.Properties.Remove($toRemove)
                Write-AccountSettings $acc.BaseName $as
                Write-Host "  '$toRemove' disabled for $($acc.BaseName)." -ForegroundColor Green
                pause
            }
            "5" {
                Show-Header
                Write-Host "BROWSE MARKETPLACE PLUGINS" -ForegroundColor Cyan
                Write-Host ""
                $allMkts = Get-AllMarketplaceNames
                if ($allMkts.Count -eq 0) {
                    Write-Host "  No marketplaces found. Add one via Marketplace Management." -ForegroundColor Yellow
                    pause; break
                }
                $mktList = @($allMkts.Keys)
                $i = 1; $mktList | ForEach-Object { Write-Host "  $i. $_" -ForegroundColor White; $i++ }
                Write-Host ""
                $pick = [int](Read-Host "  Pick marketplace") - 1
                if ($pick -lt 0 -or $pick -ge $mktList.Count) { Write-Host "  Invalid." -ForegroundColor Red; pause; break }
                $selectedMkt = $mktList[$pick]
                $available   = Get-MarketplacePlugins $selectedMkt
                Show-Header
                Write-Host "PLUGINS IN $selectedMkt" -ForegroundColor Cyan
                Write-Host ""
                if ($null -eq $available) {
                    Write-Host "  Index not downloaded. Launch an account with this marketplace configured to download it," -ForegroundColor Yellow
                    Write-Host "  then use option 5 in Marketplace Management to pull indexes to shared." -ForegroundColor Yellow
                } else {
                    if ($available.plugins.Count -gt 0) {
                        Write-Host "  Official plugins:" -ForegroundColor Green
                        $available.plugins | ForEach-Object { Write-Host "    - $_" -ForegroundColor White }
                    }
                    if ($available.external.Count -gt 0) {
                        Write-Host "  External/3rd-party:" -ForegroundColor Yellow
                        $available.external | ForEach-Object { Write-Host "    - $_" -ForegroundColor White }
                    }
                }
                Write-Host ""
                pause
            }
            "6" { Manage-Marketplaces }
            "0" { return }
            default { Write-Host "  Invalid option." -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

# ─── HELP ────────────────────────────────────────────────────────────────────

function Show-Help {
    Show-Header
    Write-Host "HELP — Claude Account Manager" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. List Accounts" -ForegroundColor White
    Write-Host "     See all your Claude accounts, which ones are logged in," -ForegroundColor Gray
    Write-Host "     and when each was last used." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. Create New Account" -ForegroundColor White
    Write-Host "     Add a new Claude account. This creates a separate profile" -ForegroundColor Gray
    Write-Host "     so you can switch between different Claude logins easily." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  3. Launch Account" -ForegroundColor White
    Write-Host "     Start Claude Code using a specific account. Pick the account" -ForegroundColor Gray
    Write-Host "     you want and it opens with that login." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  4. Rename Account" -ForegroundColor White
    Write-Host "     Change the name of an existing account profile." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  5. Delete Account" -ForegroundColor White
    Write-Host "     Permanently remove an account and all its data." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  6. Shared Settings (MCP/Skills)" -ForegroundColor Yellow
    Write-Host "     Configure MCP servers, skills, and permissions that apply" -ForegroundColor Gray
    Write-Host "     to ALL your accounts at once. Set it up once here, and every" -ForegroundColor Gray
    Write-Host "     account gets the same settings automatically on launch." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  7. Shared Plugins & Marketplace" -ForegroundColor Magenta
    Write-Host "     Install plugins GLOBALLY — one install applies to every account." -ForegroundColor Gray
    Write-Host "     No need to install the same plugin separately for each profile." -ForegroundColor Gray
    Write-Host "     Browse marketplaces to discover and install new plugins." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  8. Remote Session Backup" -ForegroundColor Green
    Write-Host "     Upload all your accounts and sessions to a secure server." -ForegroundColor Gray
    Write-Host "     You get a short code like A7X-K9M4PX — save it somewhere safe." -ForegroundColor Gray
    Write-Host "     Everything is encrypted. The code is your key to restore later." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  9. Remote Session Restore" -ForegroundColor Green
    Write-Host "     Enter your backup code to restore all accounts and sessions." -ForegroundColor Gray
    Write-Host "     Use this on a new machine or after a fresh install to get" -ForegroundColor Gray
    Write-Host "     everything back exactly as it was." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  E. Send Account (Pair Code)" -ForegroundColor Green
    Write-Host "     Send a single account to another machine. You get a short code" -ForegroundColor Gray
    Write-Host "     — tell the other person the code and they enter it using 'I'." -ForegroundColor Gray
    Write-Host "     The code expires in 10 minutes and works only once." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  I. Receive Account (Pair Code)" -ForegroundColor Green
    Write-Host "     Receive an account from someone else. Enter the pairing code" -ForegroundColor Gray
    Write-Host "     they gave you and the account appears on your machine, ready to use." -ForegroundColor Gray
    Write-Host ""
    pause
}

# ─── MAIN MENU ───────────────────────────────────────────────────────────────

function Show-Menu {
    Show-Header
    Write-Host "  Current Accounts:" -ForegroundColor Cyan
    Write-Host ""
    Show-Accounts | Out-Null
    Write-Host ""
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host "  1. List Accounts                    " -ForegroundColor White
    Write-Host "  2. Create New Account               " -ForegroundColor White
    Write-Host "  3. Launch Account                   " -ForegroundColor White
    Write-Host "  4. Rename Account                   " -ForegroundColor White
    Write-Host "  5. Delete Account                   " -ForegroundColor White
    Write-Host "  6. Shared Settings (MCP/Skills)     " -ForegroundColor Yellow
    Write-Host "  7. Shared Plugins & Marketplace     " -ForegroundColor Magenta
    Write-Host "  8. Remote Session Backup            " -ForegroundColor Green
    Write-Host "  9. Remote Session Restore           " -ForegroundColor Green
    Write-Host "  E. Send Account (Pair Code)          " -ForegroundColor Green
    Write-Host "  I. Receive Account (Pair Code)       " -ForegroundColor Green
    Write-Host "  H. Help                              " -ForegroundColor Gray
    Write-Host "  0. Exit                              " -ForegroundColor Red
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host ""
}

while ($true) {
    Show-Menu
    $choice = Read-Host "  Pick an option"
    switch ($choice) {
        "1" { Show-Header; Write-Host "All Accounts:`n" -ForegroundColor Cyan; Show-Accounts | Out-Null; Write-Host ""; pause }
        "2" { Create-Account }
        "3" { Launch-Account }
        "4" { Rename-Account }
        "5" { Delete-Account }
        "6" { Manage-SharedSettings }
        "7" { Manage-Plugins }
        "8" { Cloud-Backup }
        "9" { Cloud-Restore }
        "e" { Pair-Export }
        "E" { Pair-Export }
        "i" { Pair-Import }
        "I" { Pair-Import }
        "h" { Show-Help }
        "H" { Show-Help }
        "0" { Clear-Host; Write-Host "Bye!" -ForegroundColor Red; break }
        default { Write-Host "  Invalid option." -ForegroundColor Red; Start-Sleep 1 }
    }
    if ($choice -eq "0") { break }
}