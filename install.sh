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

# Store Hyprland signature before sudo operations
HYPR_SIG="$HYPRLAND_INSTANCE_SIGNATURE"

# Setup systemd user service for lid switch handling
mkdir -p ~/.config/systemd/user
ln -sf ~/dotfiles/lid-switch-handler.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable lid-switch-handler.service
systemctl --user start lid-switch-handler.service
echo "Lid switch systemd service installed"

# Reload Hyprland configuration if running
if pgrep -x "Hyprland" > /dev/null && [ -n "$HYPR_SIG" ]; then
    HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG" hyprctl reload
fi
