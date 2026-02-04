#!/bin/bash
# Fuzzel-based picker for Niri workspaces
#
# Shows all workspaces with their names (or "Workspace N" for unnamed)
# and allows quick switching via fuzzel.
#
# Usage: niri-workspace-switcher.sh
# Typically bound to a key like Mod+G

set -e

if [[ -z "$NIRI_SOCKET" ]]; then
    notify-send "Error" "Not running under Niri"
    exit 1
fi

# Get workspaces as JSON and format for display
# Format: "name [output]" or "Workspace N [output]" for unnamed
# We store the ID after a pipe character for extraction later
WORKSPACES=$(niri msg --json workspaces | jq -r '
    sort_by(.idx) |
    .[] | 
    (if .name then .name else "Workspace \(.idx)" end) + 
    " [\(.output // "unknown")]" +
    "|\(.id)"
')

if [[ -z "$WORKSPACES" ]]; then
    notify-send "Workspaces" "No workspaces found"
    exit 1
fi

# Count workspaces for display
WS_COUNT=$(echo "$WORKSPACES" | wc -l)

# Show picker (display part before |)
# Use fuzzel in dmenu mode
SELECTED=$(echo "$WORKSPACES" | cut -d'|' -f1 | fuzzel --dmenu --prompt="Workspace ($WS_COUNT): " --width=50)

if [[ -z "$SELECTED" ]]; then
    # User cancelled
    exit 0
fi

# Find the ID for selected workspace by matching the display string
WS_ID=$(echo "$WORKSPACES" | grep -F "${SELECTED}|" | head -1 | cut -d'|' -f2)

if [[ -n "$WS_ID" ]]; then
    niri msg action focus-workspace "$WS_ID"
else
    notify-send "Error" "Could not find workspace: $SELECTED"
    exit 1
fi
