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
bindkey "^A" beginning-of-line                # Ctrl+A
bindkey "^E" end-of-line                      # Ctrl+E
bindkey "^[[1~" beginning-of-line             # Home key (alternative sequence)
bindkey "^[[4~" end-of-line                   # End key (alternative sequence)

# Word movement
bindkey "^[f" forward-word                    # Alt+f
bindkey "^[b" backward-word                   # Alt+b
bindkey "^[[1;3C" forward-word                # Alt+Right Arrow
bindkey "^[[1;3D" backward-word               # Alt+Left Arrow
bindkey "^[^[[C" forward-word                 # Alt+Right (alternative)
bindkey "^[^[[D" backward-word                # Alt+Left (alternative)


alias v=nvim
alias ve="source .venv/bin/activate"
alias l="ls -ls"
alias lg=lazygit
alias oc=opencode
alias ocu="brew install sst/tap/opencode"

source ~/.env
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"
export PATH="/usr/local/opt/postgresql@15/bin:$PATH"

export PATH="$HOME/bin:$HOME/dotfiles/bin:$PATH"
alias cmd="~/bin/cmd"
alias cmdyolo="cmd --yolo"

# opencode
export PATH=/Users/tsah/.opencode/bin:$PATH

# Set default editor
export EDITOR=nvim

# Configure word boundaries - exclude / and . from word characters
export WORDCHARS='*?_-[]~=&;!#$%^(){}<>'

# opencode
export PATH=/home/tsah/.opencode/bin:$PATH
