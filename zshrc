### Minimal Zsh config (no plugin manager)
### - starship prompt
### - atuin history search on Ctrl-R
### - vi mode + your aliases

IS_REMOTE_SSH=false
if [[ -n "${SSH_CONNECTION-}" || -n "${SSH_TTY-}" ]]; then
  IS_REMOTE_SSH=true
fi

# ---- env ----
export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"

# Configure word boundaries (exclude / and . from word characters)
export WORDCHARS='*?_-[]~=&;!#$%^(){}<>'

# ---- path ----
typeset -U path PATH
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"

path=(
  "$HOME/.local/bin"
  "$HOME/bin"
  "$HOME/dotfiles/bin"
  "$HOME/.opencode/bin"
  "$HOME/.cargo/bin"
  "$BUN_INSTALL/bin"
  $path
)

# Load private env (if present)
[[ -f "$HOME/.env" ]] && source "$HOME/.env"

# ---- history ----
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt APPEND_HISTORY SHARE_HISTORY
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS
setopt interactive_comments

# Prevent Ctrl-S/Ctrl-Q flow control from freezing terminals
setopt no_flow_control
stty -ixon -ixoff 2>/dev/null || true

# ---- completion ----
autoload -Uz compinit
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/compdump"
zstyle ':completion:*' menu select

# ---- zoxide ----
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# ---- nvm ----
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  source "$NVM_DIR/nvm.sh"
fi
if [[ -s "$NVM_DIR/bash_completion" ]]; then
  source "$NVM_DIR/bash_completion"
fi

# ---- bun completions ----
if [[ -s "$BUN_INSTALL/_bun" ]]; then
  source "$BUN_INSTALL/_bun"
elif [[ -s "$HOME/.bun/_bun" ]]; then
  source "$HOME/.bun/_bun"
fi

# ---- gcloud ----
if [[ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]]; then
  source "$HOME/google-cloud-sdk/path.zsh.inc"
fi
if [[ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]]; then
  source "$HOME/google-cloud-sdk/completion.zsh.inc"
fi

# Source SSH agent info from Hyprland (if present)
if [[ -f "$HOME/.ssh-agent-info" ]]; then
  source "$HOME/.ssh-agent-info" >/dev/null
fi

# ---- vi mode ----
bindkey -v
export VI_MODE_SET_CURSOR=true

if [[ "$IS_REMOTE_SSH" == true ]]; then
  export KEYTIMEOUT=40
else
  export KEYTIMEOUT=1
fi

bindkey -M viins 'jk' vi-cmd-mode

zle-keymap-select() {
  if [[ ${KEYMAP} == vicmd ]]; then
    printf '\e[2 q'
  else
    printf '\e[6 q'
  fi
}
zle -N zle-keymap-select

zle-line-init() {
  zle -K viins
  printf '\e[6 q'
}
zle -N zle-line-init
printf '\e[6 q'

if command -v wl-copy >/dev/null 2>&1; then
  vi-yank-wlcopy() {
    zle vi-yank
    print -rn -- "$CUTBUFFER" | wl-copy
  }

  zle -N vi-yank-wlcopy
  bindkey -M vicmd 'y' vi-yank-wlcopy
fi

autoload -Uz edit-command-line
zle -N edit-command-line
bindkey -M vicmd v edit-command-line

# History search on up/down (prefix match)
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
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

# ---- aliases (kept) ----
alias v=nvim
alias ve="source .venv/bin/activate"
alias l="ls -ls"
alias lg=lazygit
alias ocu="brew install sst/tap/opencode"
alias occ="oc -c"  # Continue most recent session for current directory
alias wtd="wt destroy"
alias cmd="$HOME/bin/cmd"
alias cmdyolo="cmd --yolo"

# sesh launcher (kept)
s() {
  local selected name dir
  selected=$(sesh list --icons | fzf --ansi --no-sort \
    --border-label " sesh " \
    --prompt "⚡  " \
    --header "  ^a all ^t tmux ^g configs ^x zoxide" \
    --bind "ctrl-a:change-prompt(⚡  )+reload(sesh list --icons)" \
    --bind "ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons)" \
    --bind "ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)" \
    --bind "ctrl-x:change-prompt(📁  )+reload(sesh list -z --icons)" \
    --preview "sesh preview {}")
  [[ -z "$selected" ]] && return
  if [[ -n "$TMUX" ]]; then
    sesh connect "$selected"
  else
    # Outside tmux: extract name after icon, attach or create session
    name=$(echo "$selected" | sed 's/^[^ ]* //')
    dir="${name/#\~/$HOME}"
    if [[ -d "$dir" ]]; then
      tmux new-session -A -s "$(basename "$dir")" -c "$dir"
    else
      tmux new-session -A -s "$name"
    fi
  fi
}

# ---- prompt ----
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
else
  PROMPT='%F{cyan}%~%f %# '
fi

# ---- atuin (Ctrl-R) ----
if command -v atuin >/dev/null 2>&1; then
  eval "$(atuin init zsh --disable-up-arrow)"
  if (( $+functions[_atuin_search_widget] )); then
    bindkey -M viins '^R' _atuin_search_widget
  fi
fi

# Optional local overrides
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
