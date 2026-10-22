#!/bin/sh
set -eu
DOTFILES_DIR=${DOTFILES_DIR:-"$HOME/dotfiles"}
"$DOTFILES_DIR/bin/dotfiles-install" macos
