#!/bin/bash
set -eo pipefail
SOURCE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL_ROOT="$HOME/claude-multi-account"
if [ "$SOURCE_ROOT" != "$INSTALL_ROOT" ]; then
    mkdir -p "$INSTALL_ROOT/unix" "$INSTALL_ROOT/usage"
    cp "$SOURCE_ROOT/unix/claude-menu.sh" "$SOURCE_ROOT/unix/archive.py" "$INSTALL_ROOT/unix/"
    cp "$SOURCE_ROOT"/claude-usage-report.* "$INSTALL_ROOT/"
    cp "$SOURCE_ROOT/usage/"* "$INSTALL_ROOT/usage/"
    mkdir -p "$INSTALL_ROOT/updater"
    cp "$SOURCE_ROOT/updater/"* "$INSTALL_ROOT/updater/"
    cp "$SOURCE_ROOT/package.json" "$INSTALL_ROOT/"
fi
chmod +x "$INSTALL_ROOT/unix/claude-menu.sh"
mkdir -p "$HOME/.local/bin"
ln -sf "$INSTALL_ROOT/unix/claude-menu.sh" "$HOME/.local/bin/multi-claude"
ln -sf "$INSTALL_ROOT/unix/claude-menu.sh" "$HOME/.local/bin/claude-menu"
MULTI_CLAUDE_LIBRARY_ONLY=1 source "$INSTALL_ROOT/unix/claude-menu.sh"
ensure_local_bin_on_path
echo 'Installed. Open a new terminal and run multi-claude.'
