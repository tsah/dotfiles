#!/bin/bash

set -euo pipefail

SESSION_NAME="$1"
TARGET_CWD="$2"
HAS_OPENCODE="$3"
HAS_CLAUDE="$4"
PI_WINDOWS_CSV="$5"

window_id_for_name() {
    local target_name="$1"
    tmux list-windows -t "$SESSION_NAME" -F '#{window_name}|#{window_id}' 2>/dev/null | awk -F '|' -v target="$target_name" '$1 == target { print $2; exit }'
}

ensure_window_running() {
    local window_name="$1"
    local expected_cmd="$2"
    local launch_cmd="$3"
    local window_id
    local current_cmd

    window_id=$(window_id_for_name "$window_name")
    if [[ -n "$window_id" ]]; then
        current_cmd=$(tmux list-panes -t "$window_id" -F '#{pane_current_command}' 2>/dev/null | head -1)
        if [[ "$current_cmd" == "$expected_cmd" ]]; then
            return 0
        fi

        case "$current_cmd" in
            bash|zsh|sh|fish)
                tmux send-keys -t "$window_id" "$launch_cmd" Enter
                ;;
        esac
        return 0
    fi

    tmux new-window -d -t "$SESSION_NAME" -n "$window_name" -c "$TARGET_CWD" "$launch_cmd" >/dev/null
}

if [[ "$HAS_OPENCODE" == "true" ]]; then
    ensure_window_running "opencode" "opencode" "oc -c"
fi

if [[ "$HAS_CLAUDE" == "true" ]]; then
    ensure_window_running "claude" "claude" "claude -c"
fi

if [[ -n "$PI_WINDOWS_CSV" ]]; then
    IFS=',' read -r -a pi_windows <<< "$PI_WINDOWS_CSV"
    for window_name in "${pi_windows[@]}"; do
        [[ -z "$window_name" ]] && continue
        ensure_window_running "$window_name" "pi" "pi -c"
    done
fi
