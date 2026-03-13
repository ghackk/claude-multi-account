#!/bin/bash
# ─── Claude Account Manager (Unix) ─────────────────────────────────────────

ACCOUNTS_DIR="$HOME/claude-accounts"
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
    # Returns account names (basenames without extension)
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
        local loggedIn
        if [ -d "$configDir" ]; then
            loggedIn="[logged in]"
            local lastUsed=$(date -r "$configDir" "+%d %b %Y %I:%M %p" 2>/dev/null || echo "unknown")
            echo "  $i. $name  $loggedIn  (last used: $lastUsed)"
        else
            echo "  $i. $name  [not logged in]  (never used)"
        fi
        ((i++))
    done
}

# ─── EXPORT/IMPORT HELPERS ─────────────────────────────────────────────────

build_export_token() {
    local name="$1"
    local configDir="$HOME/.$name"
    local credFile="$configDir/.credentials.json"

    [ -d "$configDir" ] || return 1
    [ -f "$credFile" ] || return 1

    local tempDir=$(mktemp -d)

    # Copy auth-essential files
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

    # Copy launcher script
    [ -f "$ACCOUNTS_DIR/$name.sh" ] && cp "$ACCOUNTS_DIR/$name.sh" "$tempDir/launcher.sh"

    # Save profile name
    echo -n "$name" > "$tempDir/profile-name.txt"

    # Create zip then gzip (matches PS format for cross-platform compatibility)
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

    # Detect format
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

    # Extract base64
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
        # GZip-compressed zip — decompress gzip first, then unzip
        local zipPath=$(mktemp)
        gunzip -c "$rawPath" > "$zipPath" 2>/dev/null || {
            echo -e "  \033[31mFailed to decompress token.\033[0m"
            rm -rf "$tempDir" "$rawPath" "$zipPath"
            return 1
        }
        cd "$tempDir" && unzip -qo "$zipPath" 2>/dev/null
        rm -f "$zipPath"
    else
        # Plain tar.gz
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

    # Copy to clipboard
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

    # Decode: reverse string then base64 decode
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

# ─── MENU ───────────────────────────────────────────────────────────────────

show_menu() {
    show_header
    echo -e "  \033[36mCurrent Accounts:\033[0m"
    echo ""
    show_accounts
    echo ""
    echo -e "\033[36m======================================\033[0m"
    echo -e "  \033[32m8. Remote Session Backup\033[0m"
    echo -e "  \033[32m9. Remote Session Restore\033[0m"
    echo -e "  \033[32mE. Send Account (Pair Code)\033[0m"
    echo -e "  \033[32mI. Receive Account (Pair Code)\033[0m"
    echo -e "  \033[90mH. Help\033[0m"
    echo -e "  \033[31m0. Exit\033[0m"
    echo -e "\033[36m======================================\033[0m"
    echo ""
}

show_help() {
    show_header
    echo -e "\033[36mHELP — Claude Account Manager\033[0m"
    echo ""
    echo -e "  \033[37m8. Remote Session Backup\033[0m"
    echo -e "  \033[90m   Upload all your accounts and sessions to a secure server.\033[0m"
    echo -e "  \033[90m   You get a short code like A7X4B-K9M4PX — save it somewhere safe.\033[0m"
    echo -e "  \033[90m   Everything is encrypted. The code is your key to restore later.\033[0m"
    echo ""
    echo -e "  \033[37m9. Remote Session Restore\033[0m"
    echo -e "  \033[90m   Enter your backup code to restore all accounts and sessions.\033[0m"
    echo -e "  \033[90m   Use this on a new machine or after a fresh install to get\033[0m"
    echo -e "  \033[90m   everything back exactly as it was.\033[0m"
    echo ""
    echo -e "  \033[37mE. Send Account (Pair Code)\033[0m"
    echo -e "  \033[90m   Send a single account to another machine. You get a short code\033[0m"
    echo -e "  \033[90m   — tell the other person the code and they enter it using 'I'.\033[0m"
    echo -e "  \033[90m   The code expires in 10 minutes and works only once.\033[0m"
    echo ""
    echo -e "  \033[37mI. Receive Account (Pair Code)\033[0m"
    echo -e "  \033[90m   Receive an account from someone else. Enter the pairing code\033[0m"
    echo -e "  \033[90m   they gave you and the account appears on your machine, ready to use.\033[0m"
    echo ""
    read -p "  Press Enter..." _
}

while true; do
    show_menu
    read -p "  Pick an option: " choice
    case "$choice" in
        8)    cloud_backup ;;
        9)    cloud_restore ;;
        [eE]) pair_export ;;
        [iI]) pair_import ;;
        [hH]) show_help ;;
        0)    clear; echo -e "\033[31mBye!\033[0m"; break ;;
        *)    echo -e "  \033[31mInvalid option.\033[0m"; sleep 1 ;;
    esac
done
