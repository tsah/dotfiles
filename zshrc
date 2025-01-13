# Created by Zap installer
[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh" ] && source "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh"
plug "zsh-users/zsh-autosuggestions"
plug "zap-zsh/supercharge"
plug "zsh-users/zsh-syntax-highlighting"

# Load and initialise completion system
autoload -Uz compinit
compinit

alias v=nvim
alias ve=source .venv/bin/activate
alias l=ls -ln
alias lg=lazygit

export ANTHROPIC_API_KEY=YOUR_API_KEY_HERE # Redacted

eval "$(zoxide init zsh)"
eval "$(starship init zsh)"
export PATH="/usr/local/opt/postgresql@15/bin:$PATH"
