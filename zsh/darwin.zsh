# macOS-only zsh settings, sourced by zshrc.

# Login shells get Homebrew from .zprofile; this covers non-login shells.
if [[ -z "${HOMEBREW_PREFIX-}" && -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

export BROWSER="open"

DOTFILES_CLIPBOARD_COPY=(pbcopy)
