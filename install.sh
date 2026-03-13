#!/bin/bash
# ─── Claude Multi-Account — One-line Installer (Linux/macOS) ─────────────────
# curl -fsSL https://raw.githubusercontent.com/ghackk/claude-multi-account/master/install.sh | bash

set -e

REPO="https://github.com/ghackk/claude-multi-account.git"
INSTALL_DIR="$HOME/claude-multi-account"

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

# ─── Shell integration ───────────────────────────────────────────────────────

ALIAS_LINE="alias claude-menu='$INSTALL_DIR/unix/claude-menu.sh'"
ADDED=false

for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    [ -f "$rc" ] || continue
    if grep -q "claude-menu" "$rc" 2>/dev/null; then
        echo -e "\033[90mAlias already in $(basename $rc)\033[0m"
        ADDED=true
        break
    fi
done

if ! $ADDED; then
    # Pick the right rc file
    SHELL_RC=""
    if [ -n "$ZSH_VERSION" ] || [ "$SHELL" = "$(which zsh 2>/dev/null)" ]; then
        SHELL_RC="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        SHELL_RC="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        SHELL_RC="$HOME/.bash_profile"
    fi

    if [ -n "$SHELL_RC" ]; then
        echo "" >> "$SHELL_RC"
        echo "# Claude Multi-Account Manager" >> "$SHELL_RC"
        echo "$ALIAS_LINE" >> "$SHELL_RC"
        echo -e "\033[32mAlias added to $(basename $SHELL_RC)\033[0m"
    else
        echo -e "\033[33mCould not detect shell rc file. Add manually:\033[0m"
        echo "  $ALIAS_LINE"
    fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "\033[32m✓ Installed successfully!\033[0m"
echo ""
echo -e "  Run \033[36mclaude-menu\033[0m to start (open a new terminal first)"
echo -e "  Update anytime: \033[90mcd $INSTALL_DIR && git pull\033[0m"
echo ""
