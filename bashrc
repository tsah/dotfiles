if [ -f "$HOME/.env" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$HOME/.env"
    set +a
fi

prepend_path() {
    if [ -d "$1" ] && [[ ":$PATH:" != *":$1:"* ]]; then
        PATH="$1:$PATH"
    fi
}

prepend_path "$HOME/bin"
prepend_path "$HOME/dotfiles/bin"
prepend_path "$HOME/.opencode/bin"
prepend_path "$HOME/.bun/bin"
prepend_path "$HOME/.cargo/bin"
prepend_path "/usr/local/opt/postgresql@15/bin"
prepend_path "$HOME/nvim-linux-x86_64/bin"
prepend_path "/Users/tsah/.local/bin"
prepend_path "/Users/tsah/Library/Application Support/Coursier/bin"
prepend_path "/Users/tsah/.opencode/bin"
prepend_path "/usr/local/bin"

export PATH
unset -f prepend_path

export BUN_INSTALL="$HOME/.bun"
export EDITOR=nvim
export WORDCHARS='*?_-[]~=&;!#$%^(){}<>'
export NVM_DIR="$HOME/.nvm"
export SHELL="$(command -v bash)"

alias v='nvim'
alias l='ls -ls'
alias lg='lazygit'
alias ocu='brew install sst/tap/opencode'
alias occ='oc -c'
alias wtd='wt destroy'
alias cmd="$HOME/bin/cmd"
alias cmdyolo='cmd --yolo'

ve() {
    if [ -f .venv/bin/activate ]; then
        # shellcheck disable=SC1091
        . .venv/bin/activate
    else
        echo "No .venv/bin/activate found"
        return 1
    fi
}

s() {
    local selected name dir
    selected=$(sesh list --icons | fzf --ansi --no-sort \
        --border-label " sesh " \
        --prompt "> " \
        --header "  ^a all ^t tmux ^g configs ^x zoxide" \
        --bind "ctrl-a:change-prompt(> )+reload(sesh list --icons)" \
        --bind "ctrl-t:change-prompt(T )+reload(sesh list -t --icons)" \
        --bind "ctrl-g:change-prompt(G )+reload(sesh list -c --icons)" \
        --bind "ctrl-x:change-prompt(X )+reload(sesh list -z --icons)" \
        --preview "sesh preview {}")

    [ -z "$selected" ] && return

    if [ -n "$TMUX" ]; then
        sesh connect "$selected"
        return
    fi

    name=$(printf '%s' "$selected" | sed 's/^[^ ]* //')
    dir="${name/#\~/$HOME}"

    if [ -d "$dir" ]; then
        tmux new-session -A -s "$(basename "$dir")" -c "$dir"
    else
        tmux new-session -A -s "$name"
    fi
}

if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck disable=SC1090
    . "$NVM_DIR/nvm.sh"
fi

if [ -s "$NVM_DIR/bash_completion" ]; then
    # shellcheck disable=SC1090
    . "$NVM_DIR/bash_completion"
fi

if [ -f "$HOME/google-cloud-sdk/path.bash.inc" ]; then
    # shellcheck disable=SC1091
    . "$HOME/google-cloud-sdk/path.bash.inc"
fi

if [ -f "$HOME/google-cloud-sdk/completion.bash.inc" ]; then
    # shellcheck disable=SC1091
    . "$HOME/google-cloud-sdk/completion.bash.inc"
fi

if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash)"
fi

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi

if command -v atuin >/dev/null 2>&1; then
    eval "$(atuin init bash --disable-up-arrow)"
fi

set -o vi
