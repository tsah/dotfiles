#!/bin/sh

ln -sf ~/dotfiles/nvim ~/.config/nvim

if command -v nvim >/dev/null 2>&1; then
  nvim --headless "+MasonInstall bash-language-server gopls lua-language-server texlab rust-analyzer helm-ls basedpyright zls" +qa || true
fi

if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi
if [ -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]; then
  "$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null 2>&1 || true
fi

if [ ! -f "$HOME/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
  mkdir -p "$HOME/.zsh/plugins"
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$HOME/.zsh/plugins/zsh-autosuggestions" >/dev/null 2>&1 || true
fi

ln -sf ~/dotfiles/zshrc ~/.zshrc
ln -sf ~/dotfiles/bashrc ~/.bashrc
ln -sf ~/dotfiles/inputrc ~/.inputrc
ln -sf ~/dotfiles/.zprofile ~/.zprofile
mkdir -p ~/.config/fish
ln -sf ~/dotfiles/fish/config.fish ~/.config/fish/config.fish
ln -sf ~/dotfiles/.gitconfig ~/.gitconfig
ln -sf ~/dotfiles/.tmux.conf ~/.tmux.conf

if command -v fish >/dev/null 2>&1; then
  FISH_PATH="$(command -v fish)"
  CURRENT_SHELL="${SHELL:-}"
  if command -v getent >/dev/null 2>&1; then
    CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7 2>/dev/null || printf '%s' "$CURRENT_SHELL")"
  fi
  if [ -n "$CURRENT_SHELL" ] && [ "$CURRENT_SHELL" != "$FISH_PATH" ]; then
    chsh -s "$FISH_PATH" "$USER" || true
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user set-environment SHELL="$FISH_PATH" 2>/dev/null || true
  fi

  if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd SHELL="$FISH_PATH" 2>/dev/null || true
  fi
fi

mkdir -p ~/.config/ghostty
ln -sf ~/dotfiles/ghostty-config ~/.config/ghostty/config

# Setup omarchy (Hyprland) configuration symlinks
rm -rf ~/.config/hypr
ln -sf ~/dotfiles/omarchy/hypr ~/.config/hypr

rm -rf ~/.config/waybar
ln -sf ~/dotfiles/omarchy/waybar ~/.config/waybar

mkdir -p ~/.config/omarchy/extensions
ln -sf ~/dotfiles/omarchy/extensions/menu.sh ~/.config/omarchy/extensions/menu.sh

# Setup omarchy branding
# mkdir -p ~/.config/omarchy/branding
# ln -sf ~/dotfiles/screensaver.txt ~/.config/omarchy/branding/screensaver.txt

# Setup opencode configuration
mkdir -p ~/.config/opencode
mkdir -p ~/dotfiles/opencode/agents
mkdir -p ~/dotfiles/opencode/commands
ln -sf ~/dotfiles/opencode.json ~/.config/opencode/opencode.json
rm -rf ~/.config/opencode/agents
ln -sf ~/dotfiles/opencode/agents ~/.config/opencode/agents
rm -rf ~/.config/opencode/commands
ln -sf ~/dotfiles/opencode/commands ~/.config/opencode/commands

# Setup Claude Code commands and shared skills
mkdir -p ~/.claude/commands
mkdir -p ~/.claude/skills
ln -sf ~/dotfiles/claude/commands/tworker.md ~/.claude/commands/tworker.md
ln -sf ~/dotfiles/claude/commands/tw.md ~/.claude/commands/tw.md
rm -rf ~/.claude/skills/opencode-spawn
rm -rf ~/.claude/skills/tmux-worktree-worker
rm -rf ~/.claude/skills/tmux-interactive-control
rm -rf ~/.claude/skills/grill-me
rm -rf ~/.claude/skills/tdd
ln -sf ~/dotfiles/claude/skills/tmux-worktree-worker ~/.claude/skills/tmux-worktree-worker
ln -sf ~/dotfiles/claude/skills/tmux-interactive-control ~/.claude/skills/tmux-interactive-control
ln -sf ~/dotfiles/claude/skills/grill-me ~/.claude/skills/grill-me
ln -sf ~/dotfiles/claude/skills/tdd ~/.claude/skills/tdd

# Setup pi configuration
mkdir -p ~/.pi/agent/extensions
mkdir -p ~/.pi/agent/agents
mkdir -p ~/.pi/agent/skills
rm -rf ~/.pi/agent/extensions/tmux-agents
rm -rf ~/.pi/agent/skills/grill-me
rm -rf ~/.pi/agent/skills/tdd
ln -sf ~/dotfiles/pi/extensions/tmux-agents ~/.pi/agent/extensions/tmux-agents
ln -sf ~/dotfiles/pi/agents/plan.md ~/.pi/agent/agents/plan.md
ln -sf ~/dotfiles/pi/agents/build.md ~/.pi/agent/agents/build.md
ln -sf ~/dotfiles/pi/agents/fast.md ~/.pi/agent/agents/fast.md
ln -sf ~/dotfiles/claude/skills/grill-me ~/.pi/agent/skills/grill-me
ln -sf ~/dotfiles/claude/skills/tdd ~/.pi/agent/skills/tdd

# Setup jj (jujutsu) configuration
mkdir -p ~/.config/jj
ln -sf ~/dotfiles/jj-config.toml ~/.config/jj/config.toml

# Setup starship prompt configuration
ln -sf ~/dotfiles/starship.toml ~/.config/starship.toml

# Setup atuin (shell history) configuration
mkdir -p ~/.config/atuin
ln -sf ~/dotfiles/atuin-config.toml ~/.config/atuin/config.toml

# Setup voxtype (dictation) configuration
mkdir -p ~/.config/voxtype
ln -sf ~/dotfiles/voxtype-config.toml ~/.config/voxtype/config.toml

# Setup starship-jj configuration (jj prompt integration)
mkdir -p ~/.config/starship-jj
ln -sf ~/dotfiles/starship-jj.toml ~/.config/starship-jj/starship-jj.toml

# Setup user systemd services
mkdir -p ~/.config/systemd/user
ln -sf ~/dotfiles/headset-cvsd-enforcer.service ~/.config/systemd/user/headset-cvsd-enforcer.service

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now headset-cvsd-enforcer.service >/dev/null 2>&1 || true
fi

# Setup niri configuration symlink
# rm -rf ~/.config/niri
# ln -sf ~/dotfiles/arch-niri ~/.config/niri

# Setup mako configuration
# mkdir -p ~/.config/mako
# ln -sf ~/dotfiles/mako-config ~/.config/mako/config

# Reload configuration based on current window manager
if [ -n "$NIRI_SOCKET" ]; then
    niri msg action load-config-file
elif [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    hyprctl reload
    makoctl reload 2>/dev/null || true
fi
