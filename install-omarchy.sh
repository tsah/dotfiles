#!/bin/sh
set -eu
DOTFILES_DIR=${DOTFILES_DIR:-"$HOME/dotfiles"}
"$DOTFILES_DIR/bin/dotfiles-install" desktop
"$DOTFILES_DIR/bin/install-pi-packages"
if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then tmux source-file "$HOME/.tmux.conf"; fi
if command -v nvim >/dev/null 2>&1; then nvim --headless "+MasonInstall bash-language-server gopls lua-language-server texlab rust-analyzer helm-ls basedpyright zls" +qa || true; fi
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"; fi
if [ -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]; then "$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null 2>&1 || true; fi
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then hyprctl reload; makoctl reload 2>/dev/null || true; fi
