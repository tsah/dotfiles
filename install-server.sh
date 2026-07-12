#!/bin/sh
set -eu
DOTFILES_DIR=${DOTFILES_DIR:-"$HOME/dotfiles"}
[ -d "$DOTFILES_DIR" ] || { echo "Dotfiles not found: $DOTFILES_DIR" >&2; exit 1; }
"$DOTFILES_DIR/bin/dotfiles-install" server
if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
    tmux source-file "$HOME/.tmux.conf"
fi
mkdir -p "$HOME/.tmux/plugins"
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"; fi
[ -f "$HOME/.env" ] || : > "$HOME/.env"
echo "Server dotfiles setup complete."
