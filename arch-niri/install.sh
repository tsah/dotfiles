#!/bin/bash
# Install script for Niri configuration
# Sets up symlinks for Niri config and scripts
#
# Usage: ./install.sh
#
# This script:
# 1. Creates ~/.config/niri/ directory
# 2. Symlinks config.kdl and all scripts to ~/.config/niri/
# 3. Symlinks nwt and wt-pr to ~/bin/ for PATH access

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIRI_CONFIG_DIR="$HOME/.config/niri"
BIN_DIR="$HOME/bin"

echo "Installing Niri configuration from: $SCRIPT_DIR"
echo ""

# Create directories
echo "Creating directories..."
mkdir -p "$NIRI_CONFIG_DIR"
mkdir -p "$BIN_DIR"

# Function to create symlink (removes existing if present)
symlink() {
    local src="$1"
    local dest="$2"
    
    if [ -L "$dest" ]; then
        rm "$dest"
    elif [ -e "$dest" ]; then
        echo "  Warning: $dest exists and is not a symlink, backing up to ${dest}.bak"
        mv "$dest" "${dest}.bak"
    fi
    
    ln -sf "$src" "$dest"
    echo "  $dest -> $src"
}

# Symlink config file
echo ""
echo "Symlinking config..."
symlink "$SCRIPT_DIR/config.kdl" "$NIRI_CONFIG_DIR/config.kdl"

# Symlink all scripts to ~/.config/niri/
echo ""
echo "Symlinking scripts to $NIRI_CONFIG_DIR..."

# Scripts that stay in ~/.config/niri/
NIRI_SCRIPTS=(
    "focus-or-spawn-ghostty.sh"
    "focus-or-spawn-chromium-work.sh"
    "focus-or-spawn-chromium.sh"
    "browser-personal.sh"
    "launch-slack.sh"
    "launch-network.sh"
    "get-keyboard-layout.sh"
    "niri-start-worktree-workspaces.sh"
    "niri-workspace-switcher.sh"
    "niri-wt-spawn.sh"
    "nwt-destroy-by-name.sh"
)

for script in "${NIRI_SCRIPTS[@]}"; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        chmod +x "$SCRIPT_DIR/$script"
        symlink "$SCRIPT_DIR/$script" "$NIRI_CONFIG_DIR/$script"
    fi
done

# Symlink CLI tools to ~/bin/ for PATH access
echo ""
echo "Symlinking CLI tools to $BIN_DIR..."

CLI_TOOLS=(
    "nwt"
    "wt-pr"
)

for tool in "${CLI_TOOLS[@]}"; do
    if [ -f "$SCRIPT_DIR/$tool" ]; then
        chmod +x "$SCRIPT_DIR/$tool"
        symlink "$SCRIPT_DIR/$tool" "$BIN_DIR/$tool"
    fi
done

# Make all scripts executable (in case they weren't)
echo ""
echo "Ensuring scripts are executable..."
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR/nwt" "$SCRIPT_DIR/wt-pr" 2>/dev/null || true

echo ""
echo "Installation complete!"
echo ""
echo "Installed components:"
echo "  - Niri config: $NIRI_CONFIG_DIR/config.kdl"
echo "  - Niri scripts: $NIRI_CONFIG_DIR/*.sh"
echo "  - CLI tools: $BIN_DIR/nwt, $BIN_DIR/wt-pr"
echo ""
echo "New commands available:"
echo "  nwt spawn <branch>  - Create worktree + tmux session + Niri workspace"
echo "  nwt destroy         - Clean up worktree, session, and workspace"
echo "  wt-pr               - Open PR/compare page for current branch"
echo "  Mod+G               - Workspace switcher (in Niri)"
echo ""
echo "Note: Make sure ~/bin is in your PATH"
echo "      Add to ~/.zshrc: export PATH=\"\$HOME/bin:\$PATH\""
