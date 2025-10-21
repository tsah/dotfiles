#!/bin/sh

ln -sf ~/dotfiles/nvim ~/.config/nvim
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi
ln -sf ~/dotfiles/zshrc ~/.zshrc
ln -sf ~/dotfiles/.zprofile ~/.zprofile
ln -sf ~/dotfiles/.gitconfig ~/.gitconfig
ln -sf ~/dotfiles/.tmux.conf ~/.tmux.conf
mkdir -p ~/.config/ghostty
ln -sf ~/dotfiles/ghostty-config ~/.config/ghostty/config

# Setup hypr configuration symlink
rm -rf ~/.config/hypr
ln -sf ~/dotfiles/hypr ~/.config/hypr

# Setup waybar configuration symlink
rm -rf ~/.config/waybar
ln -sf ~/dotfiles/waybar ~/.config/waybar

# Setup omarchy branding
mkdir -p ~/.config/omarchy/branding
ln -sf ~/dotfiles/screensaver.txt ~/.config/omarchy/branding/screensaver.txt

# Setup opencode configuration
mkdir -p ~/.config/opencode
ln -sf ~/dotfiles/opencode.json ~/.config/opencode/opencode.json

# Setup niri configuration symlink
rm -rf ~/.config/niri
ln -sf ~/dotfiles/niri ~/.config/niri

# Setup mako configuration
mkdir -p ~/.config/mako
ln -sf ~/dotfiles/mako-config ~/.config/mako/config

# Reload configuration based on current window manager
if [ -n "$NIRI_SOCKET" ]; then
    niri msg action load-config-file
elif [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    hyprctl reload
    makoctl reload 2>/dev/null || true
fi
