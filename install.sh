#!/bin/sh

ln -sf ~/dotfiles/nvim ~/.config/nvim
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi
ln -sf ~/dotfiles/zshrc ~/.zshrc
ln -sf ~/dotfiles/.zprofile ~/.zprofile
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

# Reload Hyprland configuration if running
if pgrep -x "Hyprland" > /dev/null; then
    hyprctl reload
fi
