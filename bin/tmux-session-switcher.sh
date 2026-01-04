#!/bin/bash

# Tmux session switcher with wt integration
# Handles popup detection, session switching, and automatic wt -f execution

CURRENT_SESSION=$(tmux display-message -p '#{session_name}')

# Check if we're in a popup session (starts with _ and ends with __persistent or __temp)
if echo "${CURRENT_SESSION}" | grep -qE "^_.*__(persistent|temp)$"; then
    # Inside a popup - just detach
    tmux detach-client
else
    # Not in a popup - show session switcher and switch
    # Filter out popup sessions (_*__persistent|temp) and numbered sessions (just digits after icon)
    FILTER='(_.*__(persistent|temp)| [0-9]+$)'
    SELECTED=$(sesh list --icons | grep -vE "$FILTER" | fzf-tmux -p 80%,70% \
        --no-sort \
        --ansi \
        --border-label ' sesh ' \
        --prompt '⚡  ' \
        --header '  ^a all ^t tmux ^g configs ^x zoxide ^d tmux kill ^f find' \
        --bind 'tab:down,btab:up' \
        --bind 'alt-j:abort' \
        --bind "ctrl-a:change-prompt(⚡  )+reload(sesh list --icons | grep -vE '$FILTER')" \
        --bind "ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons | grep -vE '$FILTER')" \
        --bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)' \
        --bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z --icons)' \
        --bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' \
        --bind "ctrl-d:execute(tmux kill-session -t {2..})+change-prompt(⚡  )+reload(sesh list --icons | grep -vE '$FILTER')" \
        --preview-window 'right:55%' \
        --preview 'sesh preview {}')
    
    # If user selected something, connect and run wt -f in the new session
    if [[ -n "$SELECTED" ]]; then
        sesh connect "$SELECTED"
        # Run wt -f in the new session's context using send-keys
        # The command checks if it's a git repo and runs wt -f if so
        # tmux send-keys "git rev-parse --is-inside-work-tree >/dev/null 2>&1 && ~/dotfiles/bin/wt -f; clear" Enter
    fi
fi
