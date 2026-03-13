#!/bin/bash
# ─── Claude Account Manager (Unix) ─────────────────────────────────────────

ACCOUNTS_DIR="$HOME/claude-accounts"
BACKUP_DIR="$HOME/claude-backups"
SHARED_DIR="$HOME/claude-shared"
SHARED_SETTINGS="$SHARED_DIR/settings.json"
SHARED_CLAUDE="$SHARED_DIR/CLAUDE.md"
SHARED_PLUGINS_DIR="$SHARED_DIR/plugins"
SHARED_MARKETPLACES_DIR="$SHARED_PLUGINS_DIR/marketplaces"
PAIR_SERVER="https://pair.ghackk.com"

# ─── DISPLAY ────────────────────────────────────────────────────────────────

show_header() {
    clear
    echo -e "\033[36m======================================\033[0m"
    echo -e "\033[36m       Claude Account Manager         \033[0m"
    echo -e "\033[36m======================================\033[0m"
    echo ""
}

# ─── ACCOUNT HELPERS ────────────────────────────────────────────────────────

get_accounts() {
    local files=()
    for f in "$ACCOUNTS_DIR"/claude-*.sh; do
        [ -f "$f" ] || continue
        local base=$(basename "$f" .sh)
        [ "$base" = "claude-menu" ] && continue
        files+=("$base")
    done
    echo "${files[@]}"
}

show_accounts() {
    local accounts=($(get_accounts))
    if [ ${#accounts[@]} -eq 0 ]; then
        echo -e "  \033[33mNo accounts found.\033[0m"
        return
    fi
    local i=1
    for name in "${accounts[@]}"; do
        local configDir="$HOME/.$name"
        if [ -d "$configDir" ]; then
            local lastUsed=$(date -r "$configDir" "+%d %b %Y %I:%M %p" 2>/dev/null || echo "unknown")
            echo "  $i. $name  [logged in]  (last used: $lastUsed)"
        else
            echo "  $i. $name  [not logged in]  (never used)"
        fi
        ((i++))
    done
}

pick_account() {
    local prompt="$1"
    local accounts=($(get_accounts))
    if [ ${#accounts[@]} -eq 0 ]; then
        echo ""
        return
    fi
    echo ""
    echo -e "  \033[90m(enter number)\033[0m"
    read -p "  $prompt: " choice
    local index=$((choice - 1))
    if [ "$index" -lt 0 ] 2>/dev/null || [ "$index" -ge "${#accounts[@]}" ] 2>/dev/null; then
        echo ""
        return
    fi
    echo "${accounts[$index]}"
}

# ─── JSON HELPERS (requires jq) ────────────────────────────────────────────

check_jq() {
    if ! command -v jq &>/dev/null; then
        echo -e "  \033[31mjq is required for this feature. Install it:\033[0m"
        echo -e "  \033[90m  Ubuntu/Debian: sudo apt install jq\033[0m"
        echo -e "  \033[90m  macOS: brew install jq\033[0m"
        read -p "  Press Enter..." _
        return 1
    fi
    return 0
}

# Deep merge: override wins on conflict
json_merge() {
    local base="$1"
    local override="$2"
    echo "$base" "$override" | jq -s '.[0] * .[1]'
}

# ─── SHARED DIR SETUP ──────────────────────────────────────────────────────

ensure_shared_dir() {
    mkdir -p "$SHARED_DIR" "$SHARED_PLUGINS_DIR" "$SHARED_MARKETPLACES_DIR"

    if [ ! -f "$SHARED_SETTINGS" ]; then
        cat > "$SHARED_SETTINGS" << 'ENDJSON'
{
  "mcpServers": {},
  "env": {},
  "preferences": {},
  "enabledPlugins": {},
  "extraKnownMarketplaces": {}
}
ENDJSON
    else
        # Migrate: add missing fields
        local tmp=$(mktemp)
        jq '. + {enabledPlugins: (.enabledPlugins // {}), extraKnownMarketplaces: (.extraKnownMarketplaces // {})}' "$SHARED_SETTINGS" > "$tmp" 2>/dev/null && mv "$tmp" "$SHARED_SETTINGS"
        rm -f "$tmp"
    fi

    if [ ! -f "$SHARED_CLAUDE" ]; then
        cat > "$SHARED_CLAUDE" << 'ENDMD'
# Shared Claude Instructions (Skills)
# This file is automatically applied to ALL accounts.
# Add your custom behaviors, personas, or skill instructions below.

ENDMD
    fi
}

# ─── SYNC SHARED INTO ONE ACCOUNT ──────────────────────────────────────────

merge_shared_into_account() {
    local accountName="$1"
    ensure_shared_dir
    local configDir="$HOME/.$accountName"
    mkdir -p "$configDir"

    # --- Merge settings.json ---
    local settingsPath="$configDir/settings.json"
    local shared=$(cat "$SHARED_SETTINGS")

    if [ -f "$settingsPath" ]; then
        local accountSettings=$(cat "$settingsPath")
        json_merge "$accountSettings" "$shared" > "$settingsPath.tmp"
        mv "$settingsPath.tmp" "$settingsPath"
    else
        echo "$shared" > "$settingsPath"
    fi

    # --- Sync marketplace indexes ---
    local accountPluginsDir="$configDir/plugins"
    local accountMarketplacesDir="$accountPluginsDir/marketplaces"
    mkdir -p "$accountMarketplacesDir"

    if [ -d "$SHARED_MARKETPLACES_DIR" ]; then
        for mktDir in "$SHARED_MARKETPLACES_DIR"/*/; do
            [ -d "$mktDir" ] || continue
            local mktName=$(basename "$mktDir")
            local destDir="$accountMarketplacesDir/$mktName"
            mkdir -p "$destDir"
            cp -r "$mktDir"* "$destDir/" 2>/dev/null
        done
    fi

    # --- Sync known_marketplaces.json ---
    local knownMktPath="$accountPluginsDir/known_marketplaces.json"
    local sharedMkts=$(jq -r '.extraKnownMarketplaces // {}' "$SHARED_SETTINGS" 2>/dev/null)
    if [ "$sharedMkts" != "{}" ] && [ -n "$sharedMkts" ]; then
        local knownMkts="{}"
        [ -f "$knownMktPath" ] && knownMkts=$(cat "$knownMktPath")
        # Merge shared marketplace entries into known
        local merged=$(echo "$knownMkts" "$sharedMkts" | jq -s '.[0] * .[1]')
        echo "$merged" > "$knownMktPath"
    fi

    # --- Copy CLAUDE.md ---
    local sharedClaudeContent=""
    [ -f "$SHARED_CLAUDE" ] && sharedClaudeContent=$(cat "$SHARED_CLAUDE")

    if [ -n "$sharedClaudeContent" ]; then
        local accountClaudePath="$configDir/CLAUDE.md"
        local marker="# ===== SHARED INSTRUCTIONS (auto-managed) ====="
        local endMarker="# ===== END SHARED INSTRUCTIONS ====="

        if [ -f "$accountClaudePath" ]; then
            local existing=$(cat "$accountClaudePath")
            # Remove old shared block if present
            existing=$(echo "$existing" | sed "/$marker/,/$endMarker/d")
            printf "%s\n%s\n%s\n\n%s" "$marker" "$sharedClaudeContent" "$endMarker" "$existing" > "$accountClaudePath"
        else
            printf "%s\n%s\n%s\n" "$marker" "$sharedClaudeContent" "$endMarker" > "$accountClaudePath"
        fi
    fi
}

sync_all_accounts() {
    local accounts=($(get_accounts))
    if [ ${#accounts[@]} -eq 0 ]; then
        echo -e "  \033[33mNo accounts to sync.\033[0m"
        return
    fi
    for acc in "${accounts[@]}"; do
        merge_shared_into_account "$acc"
        echo -e "  \033[32mSynced -> $acc\033[0m"
    done
}

# ─── MANAGE SHARED SETTINGS MENU ───────────────────────────────────────────

manage_shared_settings() {
    check_jq || return
    while true; do
        show_header
        ensure_shared_dir
        echo -e "\033[35mSHARED SETTINGS\033[0m"
        echo ""
        echo -e "  \033[90mThese apply to ALL accounts automatically on launch.\033[0m"
        echo -e "  \033[90mShared folder: $SHARED_DIR\033[0m"
        echo ""

        local mcpCount=$(jq '.mcpServers | length' "$SHARED_SETTINGS" 2>/dev/null || echo 0)
        local envCount=$(jq '.env | length' "$SHARED_SETTINGS" 2>/dev/null || echo 0)
        local skillLines=0
        [ -f "$SHARED_CLAUDE" ] && skillLines=$(wc -l < "$SHARED_CLAUDE")

        echo -e "  \033[36mSummary:\033[0m"
        echo "    MCP Servers  : $mcpCount configured"
        echo "    Env Vars     : $envCount configured"
        echo "    CLAUDE.md    : $skillLines lines (skills/instructions)"
        echo ""
        echo -e "\033[36m======================================\033[0m"
        echo "  1. Edit MCP + Settings"
        echo "  2. Edit Skills/Instructions (CLAUDE.md)"
        echo "  3. View current shared settings"
        echo "  4. Sync shared -> ALL accounts NOW"
        echo "  5. Show MCP server list"
        echo "  6. Reset shared settings (clear)"
        echo "  0. Back"
        echo -e "\033[36m======================================\033[0m"
        echo ""

        read -p "  Pick an option: " choice
        case "$choice" in
            1)
                local editor="${EDITOR:-${VISUAL:-nano}}"
                echo -e "  \033[36mOpening settings.json in $editor...\033[0m"
                echo -e "  \033[33mTIP: Add MCP servers, env vars, preferences here.\033[0m"
                echo -e "  \033[33mAfter saving, use option 4 to push to all accounts.\033[0m"
                "$editor" "$SHARED_SETTINGS"
                read -p "  Press Enter..." _
                ;;
            2)
                local editor="${EDITOR:-${VISUAL:-nano}}"
                echo -e "  \033[36mOpening CLAUDE.md in $editor...\033[0m"
                echo -e "  \033[33mTIP: Write your skills, personas, or global instructions here.\033[0m"
                "$editor" "$SHARED_CLAUDE"
                read -p "  Press Enter..." _
                ;;
            3)
                show_header
                echo -e "\033[35mSHARED SETTINGS.JSON\033[0m"
                echo ""
                cat "$SHARED_SETTINGS"
                echo ""
                echo -e "\033[35mSHARED CLAUDE.MD (Skills)\033[0m"
                echo ""
                cat "$SHARED_CLAUDE"
                echo ""
                read -p "  Press Enter..." _
                ;;
            4)
                echo ""
                echo -e "  \033[36mSyncing to all accounts...\033[0m"
                sync_all_accounts
                echo ""
                echo -e "  \033[32mAll accounts updated!\033[0m"
                read -p "  Press Enter..." _
                ;;
            5)
                show_header
                echo -e "\033[35mMCP SERVERS\033[0m"
                echo ""
                local servers=$(jq -r '.mcpServers | keys[]' "$SHARED_SETTINGS" 2>/dev/null)
                if [ -z "$servers" ]; then
                    echo -e "  \033[33mNo MCP servers configured yet.\033[0m"
                    echo ""
                    echo -e "  \033[90mTo add one, use option 1 and add to the mcpServers block.\033[0m"
                else
                    echo "$servers" | while read -r name; do
                        local cmd=$(jq -r ".mcpServers[\"$name\"].command // empty" "$SHARED_SETTINGS" 2>/dev/null)
                        echo -e "  \033[32m- $name\033[0m"
                        [ -n "$cmd" ] && echo -e "    \033[90mcommand: $cmd\033[0m"
                    done
                fi
                echo ""
                read -p "  Press Enter..." _
                ;;
            6)
                echo ""
                read -p "  Type YES to reset ALL shared settings and CLAUDE.md: " confirm
                if [ "$confirm" = "YES" ]; then
                    cat > "$SHARED_SETTINGS" << 'ENDJSON'
{
  "mcpServers": {},
  "env": {},
  "preferences": {},
  "enabledPlugins": {},
  "extraKnownMarketplaces": {}
}
ENDJSON
                    echo "# Shared Claude Instructions" > "$SHARED_CLAUDE"
                    echo -e "  \033[31mShared settings reset.\033[0m"
                else
                    echo -e "  \033[90mCancelled.\033[0m"
                fi
                read -p "  Press Enter..." _
                ;;
            0) return ;;
            *) echo -e "  \033[31mInvalid option.\033[0m"; sleep 1 ;;
        esac
    done
}

# ─── CORE ACCOUNT FUNCTIONS ────────────────────────────────────────────────

create_account() {
    show_header
    echo -e "\033[32mCREATE NEW ACCOUNT\033[0m"
    echo ""
    read -p "  Enter account name (e.g. alpha): " name
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | xargs)

    if [ -z "$name" ]; then
        echo -e "  \033[31mName cannot be empty!\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    local shFile="$ACCOUNTS_DIR/claude-$name.sh"
    if [ -f "$shFile" ]; then
        echo -e "  \033[33mAccount 'claude-$name' already exists!\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    mkdir -p "$ACCOUNTS_DIR"
    cat > "$shFile" << ENDSH
#!/bin/bash
export CLAUDE_CONFIG_DIR="\$HOME/.claude-$name"
claude "\$@"
ENDSH
    chmod +x "$shFile"

    # Auto-apply shared settings
    if command -v jq &>/dev/null; then
        merge_shared_into_account "claude-$name"
        echo -e "  \033[90mShared settings applied automatically.\033[0m"
    fi

    echo ""
    echo -e "  \033[32mCreated claude-$name successfully!\033[0m"
    echo ""
    read -p "  Login now? (y/n): " login
    if [ "$login" = "y" ]; then
        echo -e "  \033[36mOpening claude-$name...\033[0m"
        bash "$shFile"
    fi
}

launch_account() {
    show_header
    echo -e "\033[32mLAUNCH ACCOUNT\033[0m"
    echo ""
    show_accounts
    local accounts=($(get_accounts))
    if [ ${#accounts[@]} -eq 0 ]; then
        read -p "  Press Enter..." _
        return
    fi
    local selected=$(pick_account "Pick account to launch")
    if [ -z "$selected" ]; then
        echo -e "  \033[31mInvalid choice.\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    # Auto-sync shared settings before launch
    if command -v jq &>/dev/null; then
        echo -e "  \033[90mApplying shared settings to $selected...\033[0m"
        merge_shared_into_account "$selected"
    fi
    echo -e "  \033[36mLaunching $selected...\033[0m"
    bash "$ACCOUNTS_DIR/$selected.sh"
}

rename_account() {
    show_header
    echo -e "\033[32mRENAME ACCOUNT\033[0m"
    echo ""
    show_accounts
    local accounts=($(get_accounts))
    if [ ${#accounts[@]} -eq 0 ]; then
        read -p "  Press Enter..." _
        return
    fi
    local selected=$(pick_account "Pick account to rename")
    if [ -z "$selected" ]; then
        echo -e "  \033[31mInvalid choice.\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    read -p "  Enter new name for $selected: " newSuffix
    newSuffix=$(echo "$newSuffix" | tr '[:upper:]' '[:lower:]' | xargs)
    local newName="claude-$newSuffix"
    local newSh="$ACCOUNTS_DIR/$newName.sh"

    if [ -f "$newSh" ]; then
        echo -e "  \033[33mAccount '$newName' already exists!\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    # Rename launcher
    mv "$ACCOUNTS_DIR/$selected.sh" "$newSh"
    sed -i "s/$selected/$newName/g" "$newSh" 2>/dev/null || sed -i '' "s/$selected/$newName/g" "$newSh"

    # Rename config dir
    local oldConfig="$HOME/.$selected"
    local newConfig="$HOME/.$newName"
    if [ -d "$oldConfig" ]; then
        mv "$oldConfig" "$newConfig"
    fi

    echo -e "  \033[32mRenamed $selected to $newName\033[0m"
    read -p "  Press Enter..." _
}

delete_account() {
    show_header
    echo -e "\033[31mDELETE ACCOUNT\033[0m"
    echo ""
    show_accounts
    local accounts=($(get_accounts))
    if [ ${#accounts[@]} -eq 0 ]; then
        read -p "  Press Enter..." _
        return
    fi
    local selected=$(pick_account "Pick account to delete")
    if [ -z "$selected" ]; then
        echo -e "  \033[31mInvalid choice.\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    echo ""
    echo -e "  \033[33mAccount selected for deletion: $selected\033[0m"
    read -p "  Type YES to confirm: " confirm

    if [ "$confirm" != "YES" ]; then
        echo -e "  \033[90mCancelled.\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    rm -f "$ACCOUNTS_DIR/$selected.sh"
    local configDir="$HOME/.$selected"
    if [ -d "$configDir" ]; then
        rm -rf "$configDir"
    fi
    echo -e "  \033[31mDeleted $selected\033[0m"
    read -p "  Press Enter..." _
}

# ─── LOCAL BACKUP/RESTORE ──────────────────────────────────────────────────

backup_sessions() {
    show_header
    echo -e "\033[35mBACKUP SESSIONS\033[0m"
    echo ""

    mkdir -p "$BACKUP_DIR"
    local timestamp=$(date "+%Y-%m-%d_%H-%M")
    local zipPath="$BACKUP_DIR/claude-backup-$timestamp.tar.gz"

    local toBackup=("$ACCOUNTS_DIR" "$SHARED_DIR")
    local accounts=($(get_accounts))
    for acc in "${accounts[@]}"; do
        local config="$HOME/.$acc"
        [ -d "$config" ] && toBackup+=("$config")
    done

    tar -czf "$zipPath" "${toBackup[@]}" 2>/dev/null

    echo -e "  \033[32mBackup saved to:\033[0m"
    echo "  $zipPath"
    read -p "  Press Enter..." _
}

restore_sessions() {
    show_header
    echo -e "\033[35mRESTORE SESSIONS\033[0m"
    echo ""

    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "  \033[33mNo backups found.\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    local backups=()
    for f in "$BACKUP_DIR"/claude-backup-*.tar.gz; do
        [ -f "$f" ] && backups+=("$f")
    done

    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "  \033[33mNo backup files found.\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    local i=1
    for b in "${backups[@]}"; do
        echo "  $i. $(basename "$b")"
        ((i++))
    done

    echo ""
    read -p "  Pick backup number to restore: " choice
    local index=$((choice - 1))

    if [ "$index" -lt 0 ] 2>/dev/null || [ "$index" -ge "${#backups[@]}" ] 2>/dev/null; then
        echo -e "  \033[31mInvalid choice.\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    local selected="${backups[$index]}"
    echo ""
    echo -e "  \033[33mThis will overwrite existing accounts and sessions!\033[0m"
    read -p "  Continue? (y/n): " confirm

    if [ "$confirm" != "y" ]; then
        echo -e "  \033[90mCancelled.\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    tar -xzf "$selected" -C / 2>/dev/null
    echo ""
    echo -e "  \033[32mRestored from $(basename "$selected")\033[0m"
    read -p "  Press Enter..." _
}

# ─── EXPORT/IMPORT HELPERS ─────────────────────────────────────────────────

build_export_token() {
    local name="$1"
    local configDir="$HOME/.$name"
    local credFile="$configDir/.credentials.json"

    [ -d "$configDir" ] || return 1
    [ -f "$credFile" ] || return 1

    local tempDir=$(mktemp -d)

    local configDest="$tempDir/config"
    mkdir -p "$configDest"

    for f in .credentials.json .claude.json settings.json CLAUDE.md mcp-needs-auth-cache.json; do
        [ -f "$configDir/$f" ] && cp "$configDir/$f" "$configDest/$f"
    done

    [ -d "$configDir/session-env" ] && cp -r "$configDir/session-env" "$configDest/session-env"

    if [ -d "$configDir/plugins" ]; then
        mkdir -p "$configDest/plugins"
        for f in installed_plugins.json known_marketplaces.json blocklist.json; do
            [ -f "$configDir/plugins/$f" ] && cp "$configDir/plugins/$f" "$configDest/plugins/$f"
        done
    fi

    [ -f "$ACCOUNTS_DIR/$name.sh" ] && cp "$ACCOUNTS_DIR/$name.sh" "$tempDir/launcher.sh"
    echo -n "$name" > "$tempDir/profile-name.txt"

    local zipPath=$(mktemp)
    (cd "$tempDir" && zip -qr "$zipPath" . 2>/dev/null) || {
        python3 -c "
import zipfile, os
with zipfile.ZipFile('$zipPath', 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk('$tempDir'):
        for f in files:
            fp = os.path.join(root, f)
            zf.write(fp, os.path.relpath(fp, '$tempDir'))
"
    }

    local gzPath=$(mktemp)
    gzip -c "$zipPath" > "$gzPath"
    rm -f "$zipPath"

    local b64=$(base64 -w0 "$gzPath" 2>/dev/null || base64 "$gzPath" 2>/dev/null)
    local token="CLAUDE_TOKEN_GZ:${b64}:END_TOKEN"

    rm -rf "$tempDir" "$gzPath"
    echo "$token"
}

apply_import_token() {
    local token="$1"

    local isGz=false
    local isPlain=false
    if [[ "$token" == CLAUDE_TOKEN_GZ:* ]]; then
        isGz=true
    elif [[ "$token" == CLAUDE_TOKEN:* ]]; then
        isPlain=true
    fi

    if ! $isGz && ! $isPlain; then
        echo -e "  \033[31mInvalid token format.\033[0m"
        return 1
    fi
    if [[ "$token" != *":END_TOKEN" ]]; then
        echo -e "  \033[31mInvalid token format.\033[0m"
        return 1
    fi

    local prefix
    if $isGz; then prefix="CLAUDE_TOKEN_GZ:"; else prefix="CLAUDE_TOKEN:"; fi
    local b64="${token#$prefix}"
    b64="${b64%:END_TOKEN}"

    local tempDir=$(mktemp -d)
    local rawPath=$(mktemp)

    echo "$b64" | base64 -d > "$rawPath" 2>/dev/null || {
        echo -e "  \033[31mFailed to decode token.\033[0m"
        rm -rf "$tempDir" "$rawPath"
        return 1
    }

    if $isGz; then
        local zipPath=$(mktemp)
        gunzip -c "$rawPath" > "$zipPath" 2>/dev/null || {
            echo -e "  \033[31mFailed to decompress token.\033[0m"
            rm -rf "$tempDir" "$rawPath" "$zipPath"
            return 1
        }
        cd "$tempDir" && unzip -qo "$zipPath" 2>/dev/null
        rm -f "$zipPath"
    else
        tar -xzf "$rawPath" -C "$tempDir" 2>/dev/null || {
            echo -e "  \033[31mFailed to extract token.\033[0m"
            rm -rf "$tempDir" "$rawPath"
            return 1
        }
    fi
    rm -f "$rawPath"

    local nameFile="$tempDir/profile-name.txt"
    if [ ! -f "$nameFile" ]; then
        echo -e "  \033[31mInvalid token: missing profile name.\033[0m"
        rm -rf "$tempDir"
        return 1
    fi
    local name=$(cat "$nameFile" | tr -d '\r\n')

    if ! echo "$name" | grep -qE '^[a-zA-Z0-9_-]+$'; then
        echo -e "  \033[31mInvalid profile name in token.\033[0m"
        rm -rf "$tempDir"
        return 1
    fi

    echo ""
    echo -e "  \033[36mDetected profile: $name\033[0m"

    local configDir="$HOME/.$name"
    if [ -d "$configDir" ]; then
        echo -e "  \033[33mProfile already exists locally!\033[0m"
        read -p "  Overwrite? (y/n): " confirm
        if [ "$confirm" != "y" ]; then
            echo -e "  \033[90mCancelled.\033[0m"
            rm -rf "$tempDir"
            return 1
        fi
    fi

    local importConfig="$tempDir/config"
    if [ ! -d "$importConfig" ]; then
        echo -e "  \033[31mNo config found in token.\033[0m"
        rm -rf "$tempDir"
        return 1
    fi

    mkdir -p "$configDir"
    cp -r "$importConfig"/. "$configDir/"
    echo -e "  \033[32mProfile restored (credentials, settings, session)\033[0m"

    if [ -f "$tempDir/launcher.sh" ]; then
        cp "$tempDir/launcher.sh" "$ACCOUNTS_DIR/$name.sh"
        chmod +x "$ACCOUNTS_DIR/$name.sh"
        echo -e "  \033[32mLauncher created\033[0m"
    fi

    echo ""
    echo -e "  \033[32mProfile '$name' imported successfully!\033[0m"
    echo -e "  \033[90mPlugins will auto-install on first launch.\033[0m"
    echo -e "  \033[36mRun $name to start.\033[0m"

    rm -rf "$tempDir"
    return 0
}

# ─── EXPORT/IMPORT (clipboard) ─────────────────────────────────────────────

export_profile() {
    show_header
    echo -e "\033[35mEXPORT PROFILE (Token)\033[0m"
    echo ""

    show_accounts
    local accounts=($(get_accounts))
    if [ ${#accounts[@]} -eq 0 ]; then
        read -p "  Press Enter..." _
        return
    fi

    echo ""
    read -p "  Pick account number to export: " choice
    local index=$((choice - 1))

    if [ "$index" -lt 0 ] || [ "$index" -ge "${#accounts[@]}" ]; then
        echo -e "  \033[31mInvalid choice.\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    local name="${accounts[$index]}"
    echo -e "  \033[90mBuilding token...\033[0m"
    local token=$(build_export_token "$name")

    if [ -z "$token" ]; then
        echo -e "  \033[31mFailed to build export token.\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    echo ""
    echo -e "  \033[36mProfile: $name\033[0m"
    echo -e "  \033[90mToken length: ${#token} characters\033[0m"

    if command -v xclip &>/dev/null; then
        echo -n "$token" | xclip -selection clipboard
        echo -e "  \033[32mToken copied to clipboard!\033[0m"
    elif command -v pbcopy &>/dev/null; then
        echo -n "$token" | pbcopy
        echo -e "  \033[32mToken copied to clipboard!\033[0m"
    else
        echo -e "  \033[33mClipboard not available. Token:\033[0m"
        echo "$token"
    fi

    read -p "  Press Enter..." _
}

import_profile() {
    show_header
    echo -e "\033[35mIMPORT PROFILE (Token)\033[0m"
    echo ""
    echo -e "  \033[36mPaste your profile token below:\033[0m"
    echo ""
    read -p "  Token: " token

    apply_import_token "$token"
    read -p "  Press Enter..." _
}

# ─── PAIR EXPORT/IMPORT (fetch from server, run in memory) ─────────────────

pair_export() {
    show_header
    echo -e "\033[35mPAIR EXPORT — Generate a pairing code\033[0m"
    echo ""
    echo -e "  \033[90mFetching pairing script from server...\033[0m"

    local raw
    raw=$(curl -sf "$PAIR_SERVER/client/pair-export.sh")
    if [ $? -ne 0 ] || [ -z "$raw" ]; then
        echo -e "  \033[31mFailed to fetch pairing script.\033[0m"
        echo -e "  \033[90mIs the pairing server online? Check $PAIR_SERVER/api/health\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    local reversed=$(echo -n "$raw" | rev)
    local decoded=$(echo "$reversed" | base64 -d 2>/dev/null)

    if [ -z "$decoded" ]; then
        echo -e "  \033[31mFailed to decode pairing script.\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    eval "$decoded"
}

pair_import() {
    show_header
    echo -e "\033[35mPAIR IMPORT — Enter a pairing code\033[0m"
    echo ""
    echo -e "  \033[90mFetching pairing script from server...\033[0m"

    local raw
    raw=$(curl -sf "$PAIR_SERVER/client/pair-import.sh")
    if [ $? -ne 0 ] || [ -z "$raw" ]; then
        echo -e "  \033[31mFailed to fetch pairing script.\033[0m"
        echo -e "  \033[90mIs the pairing server online? Check $PAIR_SERVER/api/health\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    local reversed=$(echo -n "$raw" | rev)
    local decoded=$(echo "$reversed" | base64 -d 2>/dev/null)

    if [ -z "$decoded" ]; then
        echo -e "  \033[31mFailed to decode pairing script.\033[0m"
        read -p "  Press Enter..." _
        return
    fi

    eval "$decoded"
}

fetch_and_run() {
    local script_name="$1"
    local raw
    raw=$(curl -sf "$PAIR_SERVER/client/$script_name")
    if [ $? -ne 0 ] || [ -z "$raw" ]; then
        echo -e "  \033[31mFailed to fetch script.\033[0m"
        echo -e "  \033[90mIs the pairing server online? Check $PAIR_SERVER/api/health\033[0m"
        read -p "  Press Enter..." _
        return
    fi
    local reversed=$(echo -n "$raw" | rev)
    local decoded=$(echo "$reversed" | base64 -d 2>/dev/null)
    if [ -z "$decoded" ]; then
        echo -e "  \033[31mFailed to decode script.\033[0m"
        read -p "  Press Enter..." _
        return
    fi
    eval "$decoded"
}

cloud_backup() {
    show_header
    echo -e "\033[35mCLOUD BACKUP\033[0m"
    echo ""
    echo -e "  \033[90mFetching backup script from server...\033[0m"
    fetch_and_run "pair-backup.sh"
}

cloud_restore() {
    show_header
    echo -e "\033[35mCLOUD RESTORE\033[0m"
    echo ""
    echo -e "  \033[90mFetching restore script from server...\033[0m"
    fetch_and_run "pair-restore.sh"
}

# ─── PLUGIN & MARKETPLACE MANAGEMENT ──────────────────────────────────────

get_all_marketplace_names() {
    # Returns marketplace names from shared + all accounts
    local names=()
    local shared_mkts=$(jq -r '.extraKnownMarketplaces | keys[]' "$SHARED_SETTINGS" 2>/dev/null)
    if [ -n "$shared_mkts" ]; then
        while read -r name; do
            names+=("$name")
        done <<< "$shared_mkts"
    fi

    local accounts=($(get_accounts))
    for acc in "${accounts[@]}"; do
        local kp="$HOME/.$acc/plugins/known_marketplaces.json"
        if [ -f "$kp" ]; then
            local acc_mkts=$(jq -r 'keys[]' "$kp" 2>/dev/null)
            while read -r name; do
                [ -z "$name" ] && continue
                local found=false
                for existing in "${names[@]}"; do
                    [ "$existing" = "$name" ] && found=true && break
                done
                $found || names+=("$name")
            done <<< "$acc_mkts"
        fi
    done
    echo "${names[@]}"
}

get_marketplace_plugins() {
    local mktName="$1"
    local dirs=("$SHARED_MARKETPLACES_DIR/$mktName")
    local accounts=($(get_accounts))
    for acc in "${accounts[@]}"; do
        dirs+=("$HOME/.$acc/plugins/marketplaces/$mktName")
    done

    for d in "${dirs[@]}"; do
        if [ -d "$d/plugins" ]; then
            echo "PLUGINS:"
            ls "$d/plugins" 2>/dev/null
            if [ -d "$d/external_plugins" ]; then
                echo "EXTERNAL:"
                ls "$d/external_plugins" 2>/dev/null
            fi
            return 0
        fi
    done
    return 1
}

manage_marketplaces() {
    check_jq || return
    while true; do
        show_header
        echo -e "\033[35mMARKETPLACE MANAGEMENT\033[0m"
        echo ""
        local mkts=($(get_all_marketplace_names))
        if [ ${#mkts[@]} -eq 0 ]; then
            echo -e "  \033[33mNo marketplaces found.\033[0m"
        else
            echo -e "  \033[36mKnown Marketplaces:\033[0m"
            for mkt in "${mkts[@]}"; do
                echo "  - $mkt"
            done
        fi
        echo ""
        echo -e "\033[36m======================================\033[0m"
        echo "  1. Add marketplace globally"
        echo "  2. Remove global marketplace"
        echo "  3. Sync marketplace indexes now"
        echo "  4. Pull indexes from accounts"
        echo "  0. Back"
        echo -e "\033[36m======================================\033[0m"
        echo ""

        read -p "  Pick an option: " choice
        case "$choice" in
            1)
                show_header
                echo -e "\033[32mADD GLOBAL MARKETPLACE\033[0m"
                echo ""
                echo -e "  \033[90mThis marketplace will be available to ALL accounts.\033[0m"
                echo ""
                read -p "  Marketplace name (e.g. my-plugins): " mktName
                mktName=$(echo "$mktName" | xargs)
                [ -z "$mktName" ] && { echo -e "  \033[90mCancelled.\033[0m"; read -p "  Press Enter..." _; continue; }
                echo -e "  \033[90mSource type: [1] GitHub repo  [2] URL\033[0m"
                read -p "  Pick: " srcChoice
                if [ "$srcChoice" = "1" ]; then
                    read -p "  GitHub repo (owner/repo): " repo
                    [ -z "$repo" ] && { echo -e "  \033[90mCancelled.\033[0m"; read -p "  Press Enter..." _; continue; }
                    jq --arg name "$mktName" --arg repo "$repo" \
                        '.extraKnownMarketplaces[$name] = {source: {source: "github", repo: $repo}}' \
                        "$SHARED_SETTINGS" > "$SHARED_SETTINGS.tmp" && mv "$SHARED_SETTINGS.tmp" "$SHARED_SETTINGS"
                elif [ "$srcChoice" = "2" ]; then
                    read -p "  URL: " url
                    [ -z "$url" ] && { echo -e "  \033[90mCancelled.\033[0m"; read -p "  Press Enter..." _; continue; }
                    jq --arg name "$mktName" --arg url "$url" \
                        '.extraKnownMarketplaces[$name] = {source: {source: "url", url: $url}}' \
                        "$SHARED_SETTINGS" > "$SHARED_SETTINGS.tmp" && mv "$SHARED_SETTINGS.tmp" "$SHARED_SETTINGS"
                else
                    echo -e "  \033[31mInvalid.\033[0m"
                    read -p "  Press Enter..." _
                    continue
                fi
                echo ""
                echo -e "  \033[32mAdded '$mktName' globally. Run sync to push to all accounts.\033[0m"
                read -p "  Press Enter..." _
                ;;
            2)
                show_header
                echo -e "\033[31mREMOVE GLOBAL MARKETPLACE\033[0m"
                echo ""
                local mkts=($(jq -r '.extraKnownMarketplaces | keys[]' "$SHARED_SETTINGS" 2>/dev/null))
                if [ ${#mkts[@]} -eq 0 ]; then
                    echo -e "  \033[33mNo global marketplaces configured.\033[0m"
                    read -p "  Press Enter..." _
                    continue
                fi
                local i=1
                for mkt in "${mkts[@]}"; do
                    echo "  $i. $mkt"
                    ((i++))
                done
                echo ""
                read -p "  Pick number to remove: " pick
                local idx=$((pick - 1))
                if [ "$idx" -ge 0 ] 2>/dev/null && [ "$idx" -lt "${#mkts[@]}" ] 2>/dev/null; then
                    local toRemove="${mkts[$idx]}"
                    jq --arg name "$toRemove" 'del(.extraKnownMarketplaces[$name])' \
                        "$SHARED_SETTINGS" > "$SHARED_SETTINGS.tmp" && mv "$SHARED_SETTINGS.tmp" "$SHARED_SETTINGS"
                    echo -e "  \033[32mRemoved '$toRemove' from global marketplaces.\033[0m"
                else
                    echo -e "  \033[31mInvalid.\033[0m"
                fi
                read -p "  Press Enter..." _
                ;;
            3)
                echo ""
                echo -e "  \033[36mSyncing marketplace indexes to all accounts...\033[0m"
                sync_all_accounts
                echo -e "  \033[32mDone.\033[0m"
                read -p "  Press Enter..." _
                ;;
            4)
                show_header
                echo -e "\033[36mPULL MARKETPLACE INDEXES FROM ACCOUNTS\033[0m"
                echo ""
                echo -e "  \033[90mCopies downloaded marketplace indexes into the shared dir.\033[0m"
                echo ""
                local mkts=($(get_all_marketplace_names))
                local pulled=0
                for mkt in "${mkts[@]}"; do
                    local destDir="$SHARED_MARKETPLACES_DIR/$mkt"
                    mkdir -p "$destDir"
                    local found=false
                    local accounts=($(get_accounts))
                    for acc in "${accounts[@]}"; do
                        local src="$HOME/.$acc/plugins/marketplaces/$mkt"
                        if [ -d "$src" ]; then
                            cp -r "$src"/* "$destDir/" 2>/dev/null
                            echo -e "  \033[32mPulled: $mkt (from $acc)\033[0m"
                            found=true
                            ((pulled++))
                            break
                        fi
                    done
                    $found || echo -e "  \033[33mNot found locally: $mkt\033[0m"
                done
                [ "$pulled" -eq 0 ] && echo -e "  \033[33mNothing pulled.\033[0m"
                read -p "  Press Enter..." _
                ;;
            0) return ;;
            *) echo -e "  \033[31mInvalid option.\033[0m"; sleep 1 ;;
        esac
    done
}

manage_plugins() {
    check_jq || return
    while true; do
        show_header
        echo -e "\033[35mPLUGINS & MARKETPLACE\033[0m"
        echo ""

        # Show summary
        local sharedCount=$(jq '.enabledPlugins | length' "$SHARED_SETTINGS" 2>/dev/null || echo 0)
        echo -e "  \033[36mEnabled Plugins:\033[0m"
        echo "    Universal (all accounts) : $sharedCount"
        echo ""

        if [ "$sharedCount" -gt 0 ]; then
            jq -r '.enabledPlugins | keys[]' "$SHARED_SETTINGS" 2>/dev/null | while read -r key; do
                echo -e "    \033[32m$key  [ALL]\033[0m"
            done
            echo ""
        fi

        echo -e "\033[36m======================================\033[0m"
        echo -e "  \033[32m1. Enable plugin for ALL accounts\033[0m"
        echo "  2. Enable plugin for one account"
        echo "  3. Disable plugin (shared)"
        echo "  4. Disable plugin (one account)"
        echo -e "  \033[36m5. Browse marketplace plugins\033[0m"
        echo -e "  \033[33m6. Marketplace Management\033[0m"
        echo "  0. Back"
        echo -e "\033[36m======================================\033[0m"
        echo ""

        read -p "  Pick an option: " choice
        case "$choice" in
            1)
                show_header
                echo -e "\033[32mENABLE PLUGIN FOR ALL ACCOUNTS\033[0m"
                echo ""
                echo -e "  \033[90mFormat: plugin-name@marketplace-name\033[0m"
                echo -e "  \033[90mExample: frontend-design@claude-plugins-official\033[0m"
                echo ""
                read -p "  Plugin key (name@marketplace): " pluginKey
                pluginKey=$(echo "$pluginKey" | xargs)
                [ -z "$pluginKey" ] && { echo -e "  \033[90mCancelled.\033[0m"; read -p "  Press Enter..." _; continue; }
                jq --arg key "$pluginKey" '.enabledPlugins[$key] = true' \
                    "$SHARED_SETTINGS" > "$SHARED_SETTINGS.tmp" && mv "$SHARED_SETTINGS.tmp" "$SHARED_SETTINGS"
                echo ""
                echo -e "  \033[32m'$pluginKey' enabled for ALL accounts.\033[0m"
                echo -e "  \033[36mSyncing to all accounts now...\033[0m"
                sync_all_accounts
                echo -e "  \033[32mDone. Launch any account to activate.\033[0m"
                read -p "  Press Enter..." _
                ;;
            2)
                show_header
                echo -e "\033[32mENABLE PLUGIN FOR ONE ACCOUNT\033[0m"
                echo ""
                show_accounts
                local accounts=($(get_accounts))
                [ ${#accounts[@]} -eq 0 ] && { read -p "  Press Enter..." _; continue; }
                local selected=$(pick_account "Pick account")
                [ -z "$selected" ] && { read -p "  Press Enter..." _; continue; }
                echo ""
                read -p "  Plugin key (name@marketplace): " pluginKey
                pluginKey=$(echo "$pluginKey" | xargs)
                [ -z "$pluginKey" ] && { echo -e "  \033[90mCancelled.\033[0m"; read -p "  Press Enter..." _; continue; }
                local settingsPath="$HOME/.$selected/settings.json"
                mkdir -p "$HOME/.$selected"
                if [ -f "$settingsPath" ]; then
                    jq --arg key "$pluginKey" '.enabledPlugins[$key] = true' "$settingsPath" > "$settingsPath.tmp" && mv "$settingsPath.tmp" "$settingsPath"
                else
                    echo "{\"enabledPlugins\":{\"$pluginKey\":true}}" > "$settingsPath"
                fi
                echo -e "  \033[32m'$pluginKey' enabled for $selected.\033[0m"
                read -p "  Press Enter..." _
                ;;
            3)
                show_header
                echo -e "\033[31mDISABLE PLUGIN (SHARED)\033[0m"
                echo ""
                local keys=($(jq -r '.enabledPlugins | keys[]' "$SHARED_SETTINGS" 2>/dev/null))
                if [ ${#keys[@]} -eq 0 ]; then
                    echo -e "  \033[33mNo shared plugins configured.\033[0m"
                    read -p "  Press Enter..." _
                    continue
                fi
                local i=1
                for key in "${keys[@]}"; do
                    echo "  $i. $key"
                    ((i++))
                done
                echo ""
                read -p "  Pick number to disable: " pick
                local idx=$((pick - 1))
                if [ "$idx" -ge 0 ] 2>/dev/null && [ "$idx" -lt "${#keys[@]}" ] 2>/dev/null; then
                    local toRemove="${keys[$idx]}"
                    jq --arg key "$toRemove" 'del(.enabledPlugins[$key])' \
                        "$SHARED_SETTINGS" > "$SHARED_SETTINGS.tmp" && mv "$SHARED_SETTINGS.tmp" "$SHARED_SETTINGS"
                    echo -e "  \033[32m'$toRemove' removed from shared.\033[0m"
                    read -p "  Sync to all accounts now? (y/n): " doSync
                    if [ "$doSync" = "y" ]; then
                        sync_all_accounts
                        echo -e "  \033[32mSynced.\033[0m"
                    fi
                else
                    echo -e "  \033[31mInvalid.\033[0m"
                fi
                read -p "  Press Enter..." _
                ;;
            4)
                show_header
                echo -e "\033[31mDISABLE PLUGIN (ONE ACCOUNT)\033[0m"
                echo ""
                show_accounts
                local accounts=($(get_accounts))
                [ ${#accounts[@]} -eq 0 ] && { read -p "  Press Enter..." _; continue; }
                local selected=$(pick_account "Pick account")
                [ -z "$selected" ] && { read -p "  Press Enter..." _; continue; }
                local settingsPath="$HOME/.$selected/settings.json"
                if [ ! -f "$settingsPath" ]; then
                    echo -e "  \033[33mNo settings for $selected.\033[0m"
                    read -p "  Press Enter..." _
                    continue
                fi
                local keys=($(jq -r '.enabledPlugins | keys[]' "$settingsPath" 2>/dev/null))
                if [ ${#keys[@]} -eq 0 ]; then
                    echo -e "  \033[33mNo plugins configured for $selected.\033[0m"
                    read -p "  Press Enter..." _
                    continue
                fi
                local i=1
                for key in "${keys[@]}"; do
                    echo "  $i. $key"
                    ((i++))
                done
                echo ""
                read -p "  Pick number: " pick
                local idx=$((pick - 1))
                if [ "$idx" -ge 0 ] 2>/dev/null && [ "$idx" -lt "${#keys[@]}" ] 2>/dev/null; then
                    local toRemove="${keys[$idx]}"
                    jq --arg key "$toRemove" 'del(.enabledPlugins[$key])' \
                        "$settingsPath" > "$settingsPath.tmp" && mv "$settingsPath.tmp" "$settingsPath"
                    echo -e "  \033[32m'$toRemove' disabled for $selected.\033[0m"
                else
                    echo -e "  \033[31mInvalid.\033[0m"
                fi
                read -p "  Press Enter..." _
                ;;
            5)
                show_header
                echo -e "\033[36mBROWSE MARKETPLACE PLUGINS\033[0m"
                echo ""
                local mkts=($(get_all_marketplace_names))
                if [ ${#mkts[@]} -eq 0 ]; then
                    echo -e "  \033[33mNo marketplaces found. Add one via Marketplace Management.\033[0m"
                    read -p "  Press Enter..." _
                    continue
                fi
                local i=1
                for mkt in "${mkts[@]}"; do
                    echo "  $i. $mkt"
                    ((i++))
                done
                echo ""
                read -p "  Pick marketplace: " pick
                local idx=$((pick - 1))
                if [ "$idx" -ge 0 ] 2>/dev/null && [ "$idx" -lt "${#mkts[@]}" ] 2>/dev/null; then
                    local selectedMkt="${mkts[$idx]}"
                    show_header
                    echo -e "\033[36mPLUGINS IN $selectedMkt\033[0m"
                    echo ""
                    local result=$(get_marketplace_plugins "$selectedMkt")
                    if [ -z "$result" ]; then
                        echo -e "  \033[33mIndex not downloaded. Launch an account with this marketplace\033[0m"
                        echo -e "  \033[33mconfigured, then pull indexes via Marketplace Management.\033[0m"
                    else
                        echo "$result" | while read -r line; do
                            if [ "$line" = "PLUGINS:" ]; then
                                echo -e "  \033[32mOfficial plugins:\033[0m"
                            elif [ "$line" = "EXTERNAL:" ]; then
                                echo -e "  \033[33mExternal/3rd-party:\033[0m"
                            elif [ -n "$line" ]; then
                                echo "    - $line"
                            fi
                        done
                    fi
                else
                    echo -e "  \033[31mInvalid.\033[0m"
                fi
                echo ""
                read -p "  Press Enter..." _
                ;;
            6) manage_marketplaces ;;
            0) return ;;
            *) echo -e "  \033[31mInvalid option.\033[0m"; sleep 1 ;;
        esac
    done
}

# ─── MENU ───────────────────────────────────────────────────────────────────

show_menu() {
    show_header
    echo -e "  \033[36mCurrent Accounts:\033[0m"
    echo ""
    show_accounts
    echo ""
    echo -e "\033[36m======================================\033[0m"
    echo "  1. List Accounts"
    echo "  2. Create New Account"
    echo "  3. Launch Account"
    echo "  4. Rename Account"
    echo -e "  \033[31m5. Delete Account\033[0m"
    echo "  6. Backup Sessions"
    echo "  7. Restore Sessions"
    echo -e "  \033[33m8. Shared Settings (MCP/Skills)\033[0m"
    echo -e "  \033[35m9. Plugins & Marketplace\033[0m"
    echo -e "  \033[32mE. Export Profile (Pair Code)\033[0m"
    echo -e "  \033[32mI. Import Profile (Pair Code)\033[0m"
    echo "  0. Exit"
    echo -e "\033[36m======================================\033[0m"
    echo ""
}

show_help() {
    show_header
    echo -e "\033[36mHELP — Claude Account Manager\033[0m"
    echo ""
    echo -e "  \033[37m1-5. Account Management\033[0m"
    echo -e "  \033[90m   Create, launch, rename, and delete Claude CLI accounts.\033[0m"
    echo -e "  \033[90m   Each account gets its own isolated config directory.\033[0m"
    echo ""
    echo -e "  \033[37m6-7. Backup & Restore\033[0m"
    echo -e "  \033[90m   Create timestamped local backups of all accounts and settings.\033[0m"
    echo ""
    echo -e "  \033[37m8. Shared Settings\033[0m"
    echo -e "  \033[90m   Define MCP servers, env vars, and CLAUDE.md instructions\033[0m"
    echo -e "  \033[90m   that automatically apply to ALL accounts on launch.\033[0m"
    echo ""
    echo -e "  \033[37m9. Plugins & Marketplace\033[0m"
    echo -e "  \033[90m   Enable/disable plugins globally or per-account.\033[0m"
    echo -e "  \033[90m   Browse and manage marketplace indexes.\033[0m"
    echo ""
    echo -e "  \033[37mE. Export Profile (Pair Code)\033[0m"
    echo -e "  \033[90m   Send a single account to another machine. You get a short code\033[0m"
    echo -e "  \033[90m   like A7X4B-K9M4PX — the other person enters it using 'I'.\033[0m"
    echo -e "  \033[90m   The code expires in 10 minutes and works only once.\033[0m"
    echo ""
    echo -e "  \033[37mI. Import Profile (Pair Code)\033[0m"
    echo -e "  \033[90m   Receive an account from someone else. Enter the pairing code\033[0m"
    echo -e "  \033[90m   they gave you and the account appears on your machine.\033[0m"
    echo ""
    read -p "  Press Enter..." _
}

while true; do
    show_menu
    read -p "  Pick an option: " choice
    case "$choice" in
        1)    show_header; echo -e "\033[36mAll Accounts:\033[0m"; echo ""; show_accounts; echo ""; read -p "  Press Enter..." _ ;;
        2)    create_account ;;
        3)    launch_account ;;
        4)    rename_account ;;
        5)    delete_account ;;
        6)    backup_sessions ;;
        7)    restore_sessions ;;
        8)    manage_shared_settings ;;
        9)    manage_plugins ;;
        [eE]) pair_export ;;
        [iI]) pair_import ;;
        [hH]) show_help ;;
        0)    clear; echo -e "\033[36mBye!\033[0m"; break ;;
        *)    echo -e "  \033[31mInvalid option.\033[0m"; sleep 1 ;;
    esac
done
