#!/bin/bash
# fzf-based picker for Niri workspaces (runs in ghostty popup)

# Get workspaces with output and idx for proper switching
# Format: "* Name [output]|output|idx" or "  Name [output]|output|idx"
WORKSPACES=$(niri msg --json workspaces | jq -r '
    sort_by(.output, .idx) |
    .[] | 
    (if .is_focused then "*" else " " end) +
    " " +
    (if .name then .name else "Workspace \(.idx)" end) + 
    " [\(.output // "unknown")]" +
    "|" + .output +
    "|" + (.idx | tostring)
')

if [[ -z "$WORKSPACES" ]]; then
    notify-send "Workspaces" "No workspaces found"
    exit 1
fi

# Escape for bash
WORKSPACES_ESCAPED=$(printf '%s' "$WORKSPACES" | sed "s/'/'\\\\''/g")

# Run in a small ghostty window with inline script
ghostty --class=workspace-picker -e bash -c '
WORKSPACES='"'$WORKSPACES_ESCAPED'"'

SELECTED=$(echo "$WORKSPACES" | cut -d"|" -f1 | fzf --prompt="Workspace> " --reverse --height=100%)

if [[ -n "$SELECTED" ]]; then
    # Find matching line and extract output and idx
    while IFS= read -r line; do
        display="${line%%|*}"
        rest="${line#*|}"
        output="${rest%%|*}"
        idx="${rest##*|}"
        
        if [[ "$display" == "$SELECTED" ]]; then
            # First focus the monitor, then the workspace index
            niri msg action focus-monitor "$output"
            niri msg action focus-workspace "$idx"
            break
        fi
    done <<< "$WORKSPACES"
fi
'
