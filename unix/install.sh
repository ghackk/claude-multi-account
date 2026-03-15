#!/bin/bash
# ─── Claude Account Manager Installer (Unix) ───────────────────────────────

set -e

INSTALL_DIR="$HOME/claude-accounts"

echo "Installing Claude Account Manager..."
mkdir -p "$INSTALL_DIR/unix"

# Copy scripts
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/claude-menu.sh" "$INSTALL_DIR/unix/claude-menu.sh"
chmod +x "$INSTALL_DIR/unix/claude-menu.sh"

# Create alias helper
echo ""
echo "Add this to your ~/.bashrc or ~/.zshrc:"
echo ""
echo "  alias claude-menu='$INSTALL_DIR/unix/claude-menu.sh'"
echo ""
echo "Done! Run 'claude-menu' to start."
