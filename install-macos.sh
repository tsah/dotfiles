#!/bin/sh

set -e

mkdir -p ~/.hammerspoon
ln -sf ~/dotfiles/hammerspoon/init.lua ~/.hammerspoon/init.lua

mkdir -p ~/.config/ghostty
ln -sf ~/dotfiles/ghostty-config ~/.config/ghostty/config
mkdir -p ~/Library/Application\ Support/com.mitchellh.ghostty
ln -sf ~/dotfiles/ghostty-macos-config ~/Library/Application\ Support/com.mitchellh.ghostty/config

mkdir -p ~/Library/Application\ Support/Raycast/script-commands
ln -sf ~/dotfiles/raycast/browser-personal.sh ~/Library/Application\ Support/Raycast/script-commands/browser-personal.sh
ln -sf ~/dotfiles/raycast/browser-work.sh ~/Library/Application\ Support/Raycast/script-commands/browser-work.sh
