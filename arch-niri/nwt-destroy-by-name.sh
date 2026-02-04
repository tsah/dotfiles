#!/bin/bash
# Destroy a worktree/workspace by its name
# Called from the workspace switcher with Ctrl+D
#
# Usage: nwt-destroy-by-name.sh "workspace-name"
#
# This script handles:
# - Worktree + tmux session + Niri workspace (full cleanup)
# - Just Niri workspace (if no worktree exists)

WS_NAME="$1"

if [[ -z "$WS_NAME" ]]; then
    notify-send "Destroy Worktree" "No workspace name provided"
    exit 1
fi

DESTROYED_SOMETHING=false

# 1. Kill tmux session if exists
if tmux has-session -t "$WS_NAME" 2>/dev/null; then
    tmux kill-session -t "$WS_NAME"
    DESTROYED_SOMETHING=true
fi

# 2. Try to find and destroy worktree
WORKTREE_PATH=""

# Search in common locations
for base in ~ ~/dev ~/src ~/code; do
    if [[ -d "$base/$WS_NAME" && -d "$base/$WS_NAME/.git" ]]; then
        WORKTREE_PATH="$base/$WS_NAME"
        break
    fi
done

# Also check git worktree list from home
if [[ -z "$WORKTREE_PATH" ]]; then
    # Try to find it in any git repo's worktree list
    for repo in ~/dotfiles ~/dev/* ~/src/* ~/code/*; do
        if [[ -d "$repo/.git" ]]; then
            FOUND=$(cd "$repo" && git worktree list 2>/dev/null | grep -F "/$WS_NAME " | awk '{print $1}')
            if [[ -n "$FOUND" && -d "$FOUND" ]]; then
                WORKTREE_PATH="$FOUND"
                break
            fi
        fi
    done
fi

if [[ -n "$WORKTREE_PATH" && -d "$WORKTREE_PATH" ]]; then
    cd "$WORKTREE_PATH"
    
    if command -v wt >/dev/null 2>&1; then
        wt destroy 2>/dev/null || true
    else
        # Fallback: manual cleanup
        MAIN_REPO=$(git worktree list --porcelain 2>/dev/null | grep "^worktree " | head -1 | cut -d' ' -f2)
        if [[ -n "$MAIN_REPO" ]]; then
            cd "$MAIN_REPO"
            git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || true
        fi
    fi
    DESTROYED_SOMETHING=true
fi

# 3. Unset Niri workspace name so empty workspace auto-removes
if [[ -n "$NIRI_SOCKET" ]]; then
    # Save current workspace to return to
    CURRENT=$(niri msg --json workspaces | jq -r '.[] | select(.is_focused) | "\(.output)|\(.idx)"')
    CURRENT_OUTPUT="${CURRENT%|*}"
    CURRENT_IDX="${CURRENT#*|}"
    
    # Find target workspace
    TARGET=$(niri msg --json workspaces | jq -r ".[] | select(.name == \"$WS_NAME\") | \"\(.output)|\(.idx)\"")
    if [[ -n "$TARGET" ]]; then
        TARGET_OUTPUT="${TARGET%|*}"
        TARGET_IDX="${TARGET#*|}"
        
        # Switch, unset name, switch back
        niri msg action focus-monitor "$TARGET_OUTPUT"
        niri msg action focus-workspace "$TARGET_IDX"
        niri msg action unset-workspace-name
        niri msg action focus-monitor "$CURRENT_OUTPUT"
        niri msg action focus-workspace "$CURRENT_IDX"
        
        DESTROYED_SOMETHING=true
    fi
fi

if [[ "$DESTROYED_SOMETHING" == "true" ]]; then
    notify-send "Destroyed" "$WS_NAME"
else
    notify-send "Nothing to destroy" "No worktree or workspace found for: $WS_NAME"
fi
