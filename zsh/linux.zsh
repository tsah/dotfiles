# Linux-only zsh settings (Omarchy desktop and servers), sourced by zshrc.

export BROWSER="xdg-open"
export PLANNOTATOR_BROWSER="${PLANNOTATOR_BROWSER:-$HOME/.local/bin/xdg-open}"
export PLANNOTATOR_REMOTE="${PLANNOTATOR_REMOTE:-1}"
# Migrate the old fixed remote port while preserving intentional overrides.
if [[ -z "${PLANNOTATOR_PORT-}" || "${PLANNOTATOR_PORT}" == "19432" ]]; then
  export PLANNOTATOR_PORT="19432-19439"
fi

# Real wl-copy on Wayland; on servers dotfiles/bin/wl-copy falls back to OSC52.
DOTFILES_CLIPBOARD_COPY=(wl-copy)

# Source SSH agent info from Hyprland (if present)
if [[ -f "$HOME/.ssh-agent-info" ]]; then
  source "$HOME/.ssh-agent-info" >/dev/null
fi
