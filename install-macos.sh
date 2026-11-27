#!/bin/sh
set -eu
DOTFILES_DIR=${DOTFILES_DIR:-"$HOME/dotfiles"}
"$DOTFILES_DIR/bin/dotfiles-install" macos
# Text files open in Neovim inside Rex ("Rex Nvim.app", default for text types).
"$DOTFILES_DIR/macos/build-rex-nvim.sh"
