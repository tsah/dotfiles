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

prepend_path "$HOME/.local/bin"

export PATH
unset -f prepend_path

# mise: activate global tool versions (e.g. python 3.12, node)
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
fi

export BUN_INSTALL="$HOME/.bun"
export EDITOR=nvim
export BROWSER=xdg-open
export WORDCHARS='*?_-[]~=&;!#$%^(){}<>'
export NVM_DIR="$HOME/.nvm"
export SHELL="$(command -v bash)"

IS_INTERACTIVE_SHELL=false
case $- in
    *i*) IS_INTERACTIVE_SHELL=true ;;
esac

alias v='nvim'
alias l='ls -ls'
alias lg='lazygit'
alias ocu='brew install sst/tap/opencode'
alias occ='oc -c'
alias worktrunk='wt'
alias wtd='wt destroy'
alias cmd="$HOME/dotfiles/bin/cmd"
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

s() { "$HOME/dotfiles/bin/workspace-picker"; }

if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck disable=SC1090
    . "$NVM_DIR/nvm.sh"
fi

if [ "$IS_INTERACTIVE_SHELL" = true ] && [ -s "$NVM_DIR/bash_completion" ]; then
    # shellcheck disable=SC1090
    . "$NVM_DIR/bash_completion"
fi

if [ -f "$HOME/google-cloud-sdk/path.bash.inc" ]; then
    # shellcheck disable=SC1091
    . "$HOME/google-cloud-sdk/path.bash.inc"
fi

if [ "$IS_INTERACTIVE_SHELL" = true ] && [ -f "$HOME/google-cloud-sdk/completion.bash.inc" ]; then
    # shellcheck disable=SC1091
    . "$HOME/google-cloud-sdk/completion.bash.inc"
fi

if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash)"
fi

if [ "$IS_INTERACTIVE_SHELL" = true ] && command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi

if [ "$IS_INTERACTIVE_SHELL" = true ] && command -v atuin >/dev/null 2>&1; then
    eval "$(atuin init bash --disable-up-arrow)"
fi

if [ "$IS_INTERACTIVE_SHELL" = true ]; then
    set -o vi
fi

if [ "$IS_INTERACTIVE_SHELL" = true ] && command -v wt >/dev/null 2>&1; then
    if WT_SHELL_INIT=$(command wt config shell init bash 2>/dev/null); then
        eval "$WT_SHELL_INIT"
    fi
fi
. "$HOME/.cargo/env"
