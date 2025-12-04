# Created by Zap installer
[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh" ] && source "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh"
plug "zsh-users/zsh-autosuggestions"
plug "zap-zsh/supercharge"
plug "zsh-users/zsh-syntax-highlighting"

# Load and initialise completion system
autoload -Uz compinit
compinit

# Source SSH agent from Hyprland
if [ -f ~/.ssh-agent-info ]; then
    source ~/.ssh-agent-info > /dev/null
fi

# Vi mode
bindkey -v
export KEYTIMEOUT=1
export VI_MODE_SET_CURSOR=true
bindkey -M viins 'jk' vi-cmd-mode

function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]]; then
    echo -ne '\e[2 q'
  else
    echo -ne '\e[6 q'
  fi
}
zle -N zle-keymap-select

zle-line-init() {
  zle -K viins
  echo -ne '\e[6 q'
}
zle -N zle-line-init
echo -ne '\e[6 q'

function vi-yank-xclip {
  zle vi-yank
  echo "$CUTBUFFER" | wl-copy
}

zle -N vi-yank-xclip
bindkey -M vicmd 'y' vi-yank-xclip

autoload edit-command-line
zle -N edit-command-line
bindkey -M vicmd v edit-command-line

# Enable history search
autoload -U up-line-or-beginning-search
autoload -U down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey -M viins "^[[A" up-line-or-beginning-search
bindkey -M viins "^[[B" down-line-or-beginning-search
bindkey -M viins "^A" beginning-of-line
bindkey -M viins "^E" end-of-line
bindkey -M viins "^[[1~" beginning-of-line
bindkey -M viins "^[[4~" end-of-line
bindkey -M viins "^[[H" beginning-of-line

# Word movement
bindkey -M viins "^[f" forward-word
bindkey -M viins "^[b" backward-word
bindkey -M viins "^[[1;3C" forward-word
bindkey -M viins "^[[1;3D" backward-word
bindkey -M viins "^[^[[C" forward-word
bindkey -M viins "^[^[[D" backward-word


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

# nvim
export PATH=/home/tsah/nvim-linux-x86_64/bin:$PATH

# Set default editor
export EDITOR=nvim

# Configure word boundaries - exclude / and . from word characters
export WORDCHARS='*?_-[]~=&;!#$%^(){}<>'

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# opencode
export PATH=/home/tsah/.opencode/bin:$PATH

# bun completions
[ -s "/home/tsah/.bun/_bun" ] && source "/home/tsah/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
export PATH=$HOME/dev/personal/advent2025/zig-linux-x86_64-0.13.0:$PATH
export PATH=/home/tsah/dev/personal/advent2025/zig-linux-x86_64-0.13.0:$PATH
