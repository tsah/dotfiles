set -l is_remote_ssh false
if set -q SSH_CONNECTION; or set -q SSH_TTY
    set is_remote_ssh true
end

set -gx SHELL (command -s fish)

if test "$is_remote_ssh" = "true"
    set -g fish_escape_delay_ms 40
else
    set -g fish_escape_delay_ms 10
end

set -g fish_cursor_default block
set -g fish_cursor_insert line
set -g fish_cursor_replace_one underscore
set -g fish_cursor_visual block

function fish_user_key_bindings
    fish_vi_key_bindings
    bind -M insert jk 'set fish_bind_mode default; commandline -f repaint-mode'
    bind -M default v edit_command_buffer
    bind -M insert \e\[A history-search-backward
    bind -M insert \e\[B history-search-forward
    bind -M insert \ef forward-word
    bind -M insert \eb backward-word
    bind -M insert \e\[1\;3C forward-word
    bind -M insert \e\[1\;3D backward-word
end

function __load_simple_env_file --argument env_file
    if not test -f "$env_file"
        return
    end

    while read -l raw_line
        set -l line (string trim -- "$raw_line")
        if test -z "$line"
            continue
        end

        if string match -qr '^#' -- "$line"
            continue
        end

        if not string match -qr '^[A-Za-z_][A-Za-z0-9_]*=' -- "$line"
            continue
        end

        set -l pair (string split -m1 '=' -- "$line")
        set -l key "$pair[1]"
        set -l value "$pair[2]"

        set value (string trim -- "$value")

        if string match -qr '^".*"$' -- "$value"
            set value (string sub -s 2 -e -1 -- "$value")
        end

        set -gx "$key" "$value"
    end < "$env_file"
end

__load_simple_env_file "$HOME/.env"
functions -e __load_simple_env_file

set -l extra_paths \
    "$HOME/bin" \
    "$HOME/dotfiles/bin" \
    "$HOME/.opencode/bin" \
    "$HOME/.bun/bin" \
    "$HOME/.cargo/bin" \
    "/usr/local/opt/postgresql@15/bin" \
    "$HOME/nvim-linux-x86_64/bin" \
    "/Users/tsah/.local/bin" \
    "/Users/tsah/Library/Application Support/Coursier/bin" \
    "/Users/tsah/.opencode/bin" \
    "/usr/local/bin"

for path_entry in $extra_paths
    if test -d "$path_entry"
        fish_add_path --move --prepend "$path_entry"
    end
end

set -gx BUN_INSTALL "$HOME/.bun"
set -gx EDITOR nvim
set -gx WORDCHARS '*?_-[]~=&;!#$%^(){}<>'
set -gx NVM_DIR "$HOME/.nvm"

alias v nvim
alias l "ls -ls"
alias lg lazygit
alias ocu "brew install sst/tap/opencode"
alias occ "oc -c"
alias wtd "wt destroy"
alias cmd "$HOME/bin/cmd"
alias cmdyolo "cmd --yolo"

function ve
    if test -f .venv/bin/activate.fish
        source .venv/bin/activate.fish
        return
    end

    echo "No .venv/bin/activate.fish found"
    return 1
end

function s
    set -l selected (sesh list --icons | fzf --ansi --no-sort \
        --border-label " sesh " \
        --prompt "> " \
        --header "  ^a all ^t tmux ^g configs ^x zoxide" \
        --bind "ctrl-a:change-prompt(> )+reload(sesh list --icons)" \
        --bind "ctrl-t:change-prompt(T )+reload(sesh list -t --icons)" \
        --bind "ctrl-g:change-prompt(G )+reload(sesh list -c --icons)" \
        --bind "ctrl-x:change-prompt(X )+reload(sesh list -z --icons)" \
        --preview "sesh preview {}")

    if test -z "$selected"
        return
    end

    if set -q TMUX
        sesh connect "$selected"
        return
    end

    set -l name (string replace -r '^[^[:space:]]+[[:space:]]+' '' -- "$selected")
    set -l dir (string replace -r '^~' "$HOME" -- "$name")

    if test -d "$dir"
        tmux new-session -A -s (basename "$dir") -c "$dir"
    else
        tmux new-session -A -s "$name"
    end
end

if command -vq zoxide
    zoxide init fish | source
end

if command -vq starship
    starship init fish | source
end

if command -vq atuin
    atuin init fish --disable-up-arrow | source
end

if test -f "$HOME/google-cloud-sdk/path.fish.inc"
    source "$HOME/google-cloud-sdk/path.fish.inc"
end

if test -f "$HOME/google-cloud-sdk/completion.fish.inc"
    source "$HOME/google-cloud-sdk/completion.fish.inc"
end
