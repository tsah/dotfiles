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

# Setup hypr configuration symlinks
rm -rf ~/.config/hypr
mkdir -p ~/.config/hypr
ln -sf ~/dotfiles/hypr/autostart.conf ~/.config/hypr/autostart.conf
ln -sf ~/dotfiles/hypr/bindings.conf ~/.config/hypr/bindings.conf
ln -sf ~/dotfiles/hypr/envs.conf ~/.config/hypr/envs.conf
ln -sf ~/dotfiles/hypr/hypridle.conf ~/.config/hypr/hypridle.conf
ln -sf ~/dotfiles/hypr/hyprland.conf ~/.config/hypr/hyprland.conf
ln -sf ~/dotfiles/hypr/hyprlock.conf ~/.config/hypr/hyprlock.conf
ln -sf ~/dotfiles/hypr/hyprsunset.conf ~/.config/hypr/hyprsunset.conf
ln -sf ~/dotfiles/hypr/input.conf ~/.config/hypr/input.conf
ln -sf ~/dotfiles/hypr/monitors.conf ~/.config/hypr/monitors.conf

# Setup waybar configuration symlink
rm -rf ~/.config/waybar
ln -sf ~/dotfiles/waybar ~/.config/waybar

# Setup omarchy branding
mkdir -p ~/.config/omarchy/branding
ln -sf ~/dotfiles/screensaver.txt ~/.config/omarchy/branding/screensaver.txt

# Setup opencode configuration
mkdir -p ~/.config/opencode
ln -sf ~/dotfiles/opencode.json ~/.config/opencode/opencode.json
