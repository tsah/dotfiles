#!/bin/bash
# Package installation script for dotfiles
# Additional packages required beyond Omarchy base installation

set -e

echo "🚀 Installing additional packages for dotfiles..."

# Check if running on Arch Linux
if ! command -v pacman &> /dev/null; then
    echo "❌ Error: This script is designed for Arch Linux (pacman required)"
    exit 1
fi

# Check if yay is installed
if ! command -v yay &> /dev/null; then
    echo "⚠️  yay AUR helper not found. Please install yay first:"
    echo "   git clone https://aur.archlinux.org/yay.git"
    echo "   cd yay && makepkg -si"
    exit 1
fi

echo "📦 Installing core packages from official repos..."

if pacman -Q neovim-git >/dev/null 2>&1; then
    echo "🔄 Replacing neovim-git with stable neovim..."
    sudo pacman -R --noconfirm neovim-git
fi

if [ -L /usr/local/bin/nvim ] && [ "$(readlink -f /usr/local/bin/nvim)" = "/opt/nvim/bin/nvim" ]; then
    echo "🧹 Removing /usr/local/bin/nvim override from /opt/nvim..."
    sudo rm -f /usr/local/bin/nvim
fi

sudo pacman -S --needed \
    base-devel \
    zsh \
    zsh-autosuggestions \
    neovim \
    worktrunk \
    iwd \
    cliphist \
    wl-clipboard \
    xclip \
    wtype \
    lazygit \
    sqlite \
    waybar \
    mako \
    fuzzel \
    nautilus \
    chromium \
    blueberry \
    brightnessctl \
    playerctl \
    pipewire-pulse \
    libva-utils \
    vdpauinfo

echo "🔧 Enabling iwd service..."
sudo systemctl enable --now iwd

echo "📦 Installing AUR packages..."
yay -S --needed \
    ghostty \
    hyprlock \
    wiremix \
    uwsm

echo "📦 Installing Bun runtime..."
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
export PATH="$BUN_INSTALL/bin:$PATH"
if ! command -v bun &> /dev/null; then
    curl -fsSL https://bun.sh/install | bash
    export PATH="$BUN_INSTALL/bin:$PATH"
    echo "✅ Bun installed"
else
    echo "✅ Bun already installed"
fi

if command -v bun &> /dev/null; then
    echo "📦 Installing Alt-K TUI dependencies..."
    (cd "$HOME/dotfiles/alt-k-tui" && bun install)
    echo "✅ Alt-K TUI dependencies installed"
else
    echo "⚠️  Bun not found after install; Alt-K TUI will fall back to fzf"
fi

echo "📦 Installing OpenCode (SST Claude CLI)..."
if ! command -v opencode &> /dev/null; then
    curl -sSL https://opencode.ai/install | bash
    echo "✅ OpenCode installed"
else
    echo "✅ OpenCode already installed"
fi

echo ""
echo "🎯 Optional packages (install as needed):"
echo "   yay -S impala bt-device"
echo ""
echo "✅ Core package installation complete!"
echo ""
echo "📋 Installed packages:"
echo "   • zsh - Z shell"
echo "   • zsh-autosuggestions - Fish-style command suggestions for Zsh"
echo "   • iwd - Wireless daemon"
echo "   • neovim - Neovim stable release"
echo "   • cliphist - Clipboard history manager"
echo "   • wl-clipboard - Wayland clipboard tools (wl-copy/wl-paste)"
echo "   • xclip - X11 clipboard tools"
echo "   • wtype - Keyboard input simulation"
echo "   • lazygit - Git TUI"
echo "   • sqlite - SQLite CLI"
echo "   • ghostty - Terminal emulator"
echo "   • bun - JavaScript runtime for Alt-K TUI"
echo "   • opencode - SST Claude CLI"
echo "   • waybar - Status bar"
echo "   • mako - Notification daemon"
echo "   • fuzzel - App launcher"
echo "   • nautilus - File manager"
echo "   • chromium - Web browser"
echo "   • blueberry - Bluetooth manager"
echo "   • brightnessctl - Brightness control"
echo "   • playerctl - Media control"
echo "   • pipewire-pulse - Audio control"
echo "   • libva-utils - VA-API diagnostics (vainfo)"
echo "   • vdpauinfo - VDPAU diagnostics"
echo "   • hyprlock - Screen locker"
echo "   • wiremix - Audio mixer"
echo "   • uwsm - Universal Wayland Session Manager"
echo ""
echo "🔄 You may need to restart your shell or source your config files."
