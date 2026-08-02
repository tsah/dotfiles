#!/bin/sh
set -eu
DOTFILES_DIR=${DOTFILES_DIR:-"$HOME/dotfiles"}
[ -d "$DOTFILES_DIR" ] || { echo "Dotfiles not found: $DOTFILES_DIR" >&2; exit 1; }
"$DOTFILES_DIR/bin/dotfiles-install" server
"$DOTFILES_DIR/bin/install-pi-packages"
REAL_HOME=$(getent passwd "$(id -un)" | cut -d: -f6)
if [ "$HOME" = "$REAL_HOME" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload
    systemctl --user enable --now wayfinder-resource-guard.service
    if command -v loginctl >/dev/null 2>&1 && [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)" != "yes" ]; then
        echo "Warning: run 'sudo loginctl enable-linger $(id -un)' so the resource guard survives SSH logout." >&2
    fi
fi
if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
    tmux source-file "$HOME/.tmux.conf"
fi
mkdir -p "$HOME/.tmux/plugins"
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"; fi
[ -f "$HOME/.env" ] || : > "$HOME/.env"
echo "Server dotfiles setup complete."
