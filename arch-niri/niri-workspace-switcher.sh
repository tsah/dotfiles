#!/bin/bash
# fzf-based picker for Niri workspaces (runs in ghostty popup)
# Keybinds:
#   Enter   - Switch to selected workspace
#   Ctrl+D  - Destroy selected worktree (only for named workspaces)

# Get workspaces with output and idx for proper switching
# Format: "* Name [output]|output|idx|name" or "  Name [output]|output|idx|"
WORKSPACES=$(niri msg --json workspaces | jq -r '
    sort_by(.output, .idx) |
    .[] | 
    (if .is_focused then "*" else " " end) +
    " " +
    (if .name then .name else "Workspace \(.idx)" end) + 
    " [\(.output // "unknown")]" +
    "|" + .output +
    "|" + (.idx | tostring) +
    "|" + (.name // "")
')

if [[ -z "$WORKSPACES" ]]; then
    notify-send "Workspaces" "No workspaces found"
    exit 1
fi

# Escape for bash
WORKSPACES_ESCAPED=$(printf '%s' "$WORKSPACES" | sed "s/'/'\\\\''/g")
NIRI_SOCKET_ESCAPED=$(printf '%s' "$NIRI_SOCKET" | sed "s/'/'\\\\''/g")

# Run in a small ghostty window with inline script
ghostty --class=workspace-picker -e bash -c '
WORKSPACES='"'$WORKSPACES_ESCAPED'"'
export NIRI_SOCKET='"'$NIRI_SOCKET_ESCAPED'"'

# fzf with keybinds - output format: "action:selected_line"
RESULT=$(echo "$WORKSPACES" | cut -d"|" -f1 | fzf \
    --prompt="Workspace> " \
    --reverse \
    --height=100% \
    --header="Enter: switch | Ctrl+D: destroy worktree" \
    --expect=ctrl-d)

# Parse result - first line is the key pressed (empty for Enter), second is selection
KEY=$(echo "$RESULT" | head -1)
SELECTED=$(echo "$RESULT" | tail -1)

if [[ -z "$SELECTED" ]]; then
    exit 0
fi

# Find matching line and extract data
while IFS= read -r line; do
    display="${line%%|*}"
    rest="${line#*|}"
    output="${rest%%|*}"
    rest="${rest#*|}"
    idx="${rest%%|*}"
    ws_name="${rest#*|}"
    
    if [[ "$display" == "$SELECTED" ]]; then
        if [[ "$KEY" == "ctrl-d" ]]; then
            # Destroy worktree
            if [[ -z "$ws_name" ]]; then
                notify-send "Destroy Worktree" "Cannot destroy unnamed workspace"
                exit 1
            fi
            # Run destroy script synchronously (fast enough, ensures completion)
            /home/tsah/.config/niri/nwt-destroy-by-name.sh "$ws_name"
        else
            # Switch to workspace
            niri msg action focus-monitor "$output"
            niri msg action focus-workspace "$idx"
        fi
        break
    fi
done <<< "$WORKSPACES"
'
