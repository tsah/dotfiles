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
sudo pacman -S --needed \
    cliphist \
    wtype \
    lazygit \
    waybar \
    mako \
    fuzzel \
    nautilus \
    chromium \
    blueberry \
    brightnessctl \
    playerctl \
    pipewire-pulse

echo "📦 Installing AUR packages..."
yay -S --needed \
    sesh-bin \
    ghostty \
    hyprlock \
    wiremix \
    uwsm

echo "📦 Installing OpenCode (SST Claude CLI)..."
if ! command -v opencode &> /dev/null; then
    curl -sSL https://install.opencode.dev | bash
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
echo "   • cliphist - Clipboard history manager"
echo "   • wtype - Keyboard input simulation"
echo "   • lazygit - Git TUI"
echo "   • ghostty - Terminal emulator"
echo "   • sesh - Session manager"
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
echo "   • hyprlock - Screen locker"
echo "   • wiremix - Audio mixer"
echo "   • uwsm - Universal Wayland Session Manager"
echo ""
echo "🔄 You may need to restart your shell or source your config files."