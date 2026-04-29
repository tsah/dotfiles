path_prepend() {
    local dir="$1"

    if [[ -d "$dir" && ":$PATH:" != *":$dir:"* ]]; then
        PATH="$dir:$PATH"
    fi
}


path_bootstrap_tmux_run_shell() {
    local latest_node_bin

    path_prepend "$HOME/bin"
    path_prepend "$HOME/dotfiles/bin"
    path_prepend "$HOME/.local/bin"
    path_prepend "$HOME/.opencode/bin"
    path_prepend "$HOME/.cargo/bin"
    path_prepend "${BUN_INSTALL:-$HOME/.bun}/bin"
    path_prepend "$HOME/.pi/agent/bin"

    latest_node_bin=$(find "$HOME/.local/node" -mindepth 2 -maxdepth 2 -type d -path "$HOME/.local/node/node-*/bin" 2>/dev/null | LC_ALL=C sort -V | tail -n 1 || true)
    if [[ -n "$latest_node_bin" ]]; then
        path_prepend "$latest_node_bin"
    fi

    export PATH
}


path_bootstrap_tmux_run_shell
