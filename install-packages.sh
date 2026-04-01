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
    fish \
    zsh \
    zsh-autosuggestions \
    neovim \
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
    sesh-bin \
    ghostty \
    hyprlock \
    wiremix \
    uwsm

echo "📦 Installing OpenCode (SST Claude CLI)..."
if ! command -v opencode &> /dev/null; then
    curl -sSL https://opencode.ai/install | bash
    echo "✅ OpenCode installed"
else
    echo "✅ OpenCode already installed"
fi

echo "📦 Installing starship-jj (jj prompt for Starship)..."
if ! command -v starship-jj &> /dev/null; then
    if command -v cargo &> /dev/null; then
        cargo install starship-jj --locked
        echo "✅ starship-jj installed"
    else
        echo "⚠️  Cargo not found. Install Rust first, then run: cargo install starship-jj --locked"
    fi
else
    echo "✅ starship-jj already installed"
fi

echo ""
echo "🎯 Optional packages (install as needed):"
echo "   yay -S impala bt-device"
echo ""
echo "✅ Core package installation complete!"
echo ""
echo "📋 Installed packages:"
echo "   • fish - Fish shell"
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
echo "   • sesh - Session manager"
echo "   • opencode - SST Claude CLI"
echo "   • starship-jj - jj prompt integration for Starship"
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
