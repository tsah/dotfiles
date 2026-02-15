#!/bin/sh

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

if [ ! -d "$DOTFILES_DIR" ]; then
    echo "Error: Dotfiles directory not found at $DOTFILES_DIR" >&2
    echo "Set DOTFILES_DIR or clone this repository to ~/dotfiles." >&2
    exit 1
fi

mkdir -p "$HOME/.config"
mkdir -p "$HOME/.tmux/plugins"

ln -sf "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
ln -sf "$DOTFILES_DIR/zshrc" "$HOME/.zshrc"
ln -sf "$DOTFILES_DIR/bashrc" "$HOME/.bashrc"
ln -sf "$DOTFILES_DIR/inputrc" "$HOME/.inputrc"
ln -sf "$DOTFILES_DIR/.zprofile" "$HOME/.zprofile"
mkdir -p "$HOME/.config/fish"
ln -sf "$DOTFILES_DIR/fish/config.fish" "$HOME/.config/fish/config.fish"
ln -sf "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
ln -sf "$DOTFILES_DIR/.tmux.conf" "$HOME/.tmux.conf"

mkdir -p "$HOME/.config/opencode"
ln -sf "$DOTFILES_DIR/opencode.json" "$HOME/.config/opencode/opencode.json"
rm -rf "$HOME/.config/opencode/agents"
ln -sf "$DOTFILES_DIR/opencode/agents" "$HOME/.config/opencode/agents"
rm -rf "$HOME/.config/opencode/commands"
ln -sf "$DOTFILES_DIR/opencode/commands" "$HOME/.config/opencode/commands"

mkdir -p "$HOME/.config/jj"
ln -sf "$DOTFILES_DIR/jj-config.toml" "$HOME/.config/jj/config.toml"

ln -sf "$DOTFILES_DIR/starship.toml" "$HOME/.config/starship.toml"

mkdir -p "$HOME/.config/atuin"
ln -sf "$DOTFILES_DIR/atuin-config.toml" "$HOME/.config/atuin/config.toml"

mkdir -p "$HOME/.config/starship-jj"
ln -sf "$DOTFILES_DIR/starship-jj.toml" "$HOME/.config/starship-jj/starship-jj.toml"

if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi

if [ -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]; then
    "$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null 2>&1 || true
fi

if [ ! -f "$HOME/.env" ]; then
    touch "$HOME/.env"
fi

if command -v fish >/dev/null 2>&1; then
    FISH_PATH="$(command -v fish)"
    CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7 2>/dev/null || true)"

    if [ -f /etc/shells ] && ! grep -Fx "$FISH_PATH" /etc/shells >/dev/null 2>&1; then
        if command -v sudo >/dev/null 2>&1; then
            printf '%s\n' "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
        else
            printf '%s\n' "$FISH_PATH" >> /etc/shells
        fi
    fi

    if [ -n "$CURRENT_SHELL" ] && [ "$CURRENT_SHELL" != "$FISH_PATH" ]; then
        if command -v sudo >/dev/null 2>&1; then
            sudo chsh -s "$FISH_PATH" "$USER" || true
        else
            chsh -s "$FISH_PATH" "$USER" || true
        fi
    fi
fi

echo "Server dotfiles setup complete."
