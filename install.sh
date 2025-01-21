#!/bin/sh

# ln -sf ~/dotfiles/nvim ~/.config/nvim
if [ ! -d "$HOME/.config/nvim" ]; then
    git clone git@github.com:tsah/kickstart-modular.nvim.git ~/.config/nvim
fi
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi
ln -sf ~/dotfiles/zshrc ~/.zshrc
ln -sf ~/dotfiles/.zprofile ~/.zprofile
ln -sf ~/dotfiles/.tmux.conf ~/.tmux.conf
ln -sf ~/dotfiles/alacritty.yml ~/.config/alacritty/alacritty.yml
ln -sf ~/dotfiles/wezterm ~/.config/wezterm
ln -sf ~/dotfiles/.aerospace.toml ~/.aerospace.toml
ln -sf ~/dotfiles/zellij-config.kdl ~/.config/zellij/config.kdl
mkdir -p ~/.config/ghostty
ln -sf ~/dotfiles/ghostty-config ~/.config/ghostty/config

