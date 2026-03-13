#!/bin/bash
# ─── Claude Multi-Account — One-line Installer (Linux/macOS) ─────────────────
# curl -fsSL https://raw.githubusercontent.com/ghackk/claude-multi-account/master/install.sh | bash

set -e

REPO="https://github.com/ghackk/claude-multi-account.git"
INSTALL_DIR="$HOME/claude-multi-account"
BIN_DIR="$HOME/.local/bin"
SYMLINK="$BIN_DIR/multi-claude"

echo ""
echo -e "\033[36m======================================\033[0m"
echo -e "\033[36m  Claude Multi-Account — Installer    \033[0m"
echo -e "\033[36m======================================\033[0m"
echo ""

# ─── Download ────────────────────────────────────────────────────────────────

if [ -d "$INSTALL_DIR/.git" ]; then
    echo -e "\033[33mExisting installation found. Updating...\033[0m"
    git -C "$INSTALL_DIR" pull --quiet
    echo -e "\033[32mUpdated!\033[0m"
elif command -v git &>/dev/null; then
    echo "Cloning repository..."
    git clone --quiet "$REPO" "$INSTALL_DIR"
    echo -e "\033[32mDownloaded!\033[0m"
else
    echo "git not found — downloading as archive..."
    mkdir -p "$INSTALL_DIR"
    curl -fsSL "https://github.com/ghackk/claude-multi-account/archive/refs/heads/master.tar.gz" \
        | tar -xz --strip-components=1 -C "$INSTALL_DIR"
    echo -e "\033[32mDownloaded!\033[0m"
fi

chmod +x "$INSTALL_DIR/unix/claude-menu.sh"

# ─── Create symlink ─────────────────────────────────────────────────────────

mkdir -p "$BIN_DIR"

if [ -L "$SYMLINK" ]; then
    rm "$SYMLINK"
elif [ -e "$SYMLINK" ]; then
    echo -e "\033[33mWarning: $SYMLINK already exists and is not a symlink. Backing up to ${SYMLINK}.bak\033[0m"
    mv "$SYMLINK" "${SYMLINK}.bak"
fi

ln -s "$INSTALL_DIR/unix/claude-menu.sh" "$SYMLINK"
echo -e "\033[32mSymlink created: $SYMLINK\033[0m"

# ─── Ensure ~/.local/bin is in PATH ─────────────────────────────────────────

add_path_to_rc() {
    local rc_file="$1"
    local line="$2"

    # Create the rc file if it doesn't exist
    [ -f "$rc_file" ] || touch "$rc_file"

    if grep -qF '.local/bin' "$rc_file" 2>/dev/null; then
        echo -e "\033[90mPATH already configured in $(basename "$rc_file")\033[0m"
    else
        echo "" >> "$rc_file"
        echo "# Claude Multi-Account Manager" >> "$rc_file"
        echo "$line" >> "$rc_file"
        echo -e "\033[32mPATH added to $(basename "$rc_file")\033[0m"
    fi
}

# Also clean up old alias lines from previous installs
cleanup_old_alias() {
    local rc_file="$1"
    [ -f "$rc_file" ] || return 0
    if grep -q "alias claude-menu=" "$rc_file" 2>/dev/null; then
        # Remove the old alias line and its comment
        sed -i.bak '/# Claude Multi-Account Manager/{N;/alias claude-menu=/d;}' "$rc_file" 2>/dev/null || true
        sed -i.bak '/alias claude-menu=/d' "$rc_file" 2>/dev/null || true
        rm -f "${rc_file}.bak"
        echo -e "\033[90mRemoved old alias from $(basename "$rc_file")\033[0m"
    fi
}

PATH_IN_SHELL=false
if echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR" 2>/dev/null; then
    PATH_IN_SHELL=true
fi

EXPORT_LINE='export PATH="$HOME/.local/bin:$PATH"'
FISH_PATH_LINE='fish_add_path -g $HOME/.local/bin'

# Bash
for rc in "$HOME/.bashrc" "$HOME/.bash_profile"; do
    cleanup_old_alias "$rc"
done
if ! $PATH_IN_SHELL; then
    if [ -f "$HOME/.bashrc" ]; then
        add_path_to_rc "$HOME/.bashrc" "$EXPORT_LINE"
    elif [ -f "$HOME/.bash_profile" ]; then
        add_path_to_rc "$HOME/.bash_profile" "$EXPORT_LINE"
    else
        add_path_to_rc "$HOME/.bashrc" "$EXPORT_LINE"
    fi
fi

# Zsh
cleanup_old_alias "$HOME/.zshrc"
if ! $PATH_IN_SHELL; then
    if [ -f "$HOME/.zshrc" ] || command -v zsh &>/dev/null; then
        add_path_to_rc "$HOME/.zshrc" "$EXPORT_LINE"
    fi
fi

# Fish
FISH_CONFIG="$HOME/.config/fish/config.fish"
if command -v fish &>/dev/null || [ -f "$FISH_CONFIG" ]; then
    mkdir -p "$(dirname "$FISH_CONFIG")"
    [ -f "$FISH_CONFIG" ] || touch "$FISH_CONFIG"

    if grep -qF '.local/bin' "$FISH_CONFIG" 2>/dev/null; then
        echo -e "\033[90mPATH already configured in config.fish\033[0m"
    else
        echo "" >> "$FISH_CONFIG"
        echo "# Claude Multi-Account Manager" >> "$FISH_CONFIG"
        echo "$FISH_PATH_LINE" >> "$FISH_CONFIG"
        echo -e "\033[32mPATH added to config.fish\033[0m"
    fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "\033[32m✓ Installed successfully!\033[0m"
echo ""
echo -e "  Run \033[36mmulti-claude\033[0m to start (open a new terminal first)"
echo -e "  Update anytime: \033[90mcd $INSTALL_DIR && git pull\033[0m"
echo ""
