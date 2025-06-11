# Created by Zap installer
[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh" ] && source "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh"
plug "zsh-users/zsh-autosuggestions"
plug "zap-zsh/supercharge"
plug "zsh-users/zsh-syntax-highlighting"

# Load and initialise completion system
autoload -Uz compinit
compinit

# Enable history search
autoload -U up-line-or-beginning-search
autoload -U down-line-or-beginning-search
autoload -Uz edit-command-line
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey "^[[A" up-line-or-beginning-search    # Up arrow
bindkey "^[[B" down-line-or-beginning-search  # Down arrow


alias v=nvim
alias ve="source .venv/bin/activate"
alias l="ls -ls"
alias lg=lazygit

source ~/.env
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"
export PATH="/usr/local/opt/postgresql@15/bin:$PATH"

# pnpm
export PNPM_HOME="/Users/tsah/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# Added by Windsurf
export PATH="$HOME/bin:$HOME/dotfiles/bin:$PATH"
alias cmd="~/bin/cmd"
alias cmdyolo="cmd --yolo"

# opencode
export PATH=/Users/tsah/.opencode/bin:$PATH
