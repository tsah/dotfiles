#!/bin/bash
# Create named Niri workspaces for all existing worktrees under ~/dev/work
# Also ensures tmux sessions exist (calls existing script)
# Run this on Niri startup to restore your work environment
#
# Usage:
#   niri-start-worktree-workspaces.sh [work_base_dir]
#
# Default work_base_dir is ~/dev/work

WORK_BASE="${1:-$HOME/dev/work}"

echo "Starting Niri worktree workspace initialization..."
echo "Work base: $WORK_BASE"

# First, ensure tmux sessions exist (reuse existing logic)
TMUX_SCRIPT="$HOME/dotfiles/bin/tmux-start-worktree-sessions.sh"
if [[ -x "$TMUX_SCRIPT" ]]; then
    echo "Initializing tmux sessions..."
    "$TMUX_SCRIPT" "$WORK_BASE"
else
    echo "Warning: tmux session script not found at $TMUX_SCRIPT"
fi

# Check if we're running under Niri
if [[ -z "$NIRI_SOCKET" ]]; then
    echo "Not running under Niri, skipping workspace creation"
    exit 0
fi

if [[ ! -d "$WORK_BASE" ]]; then
    echo "Work directory not found: $WORK_BASE"
    exit 1
fi

# Collect all worktree paths and names first
declare -a WORKTREES=()

while IFS= read -r -d '' gitdir; do
    worktree_path=$(dirname "$gitdir")
    
    cd "$worktree_path" 2>/dev/null || continue
    
    while IFS= read -r wt_path; do
        # Skip empty lines
        [[ -z "$wt_path" ]] && continue
        
        # Skip broken repos
        [[ "$wt_path" == *".broken_repos"* ]] && continue
        
        workspace_name=$(basename "$wt_path")
        WORKTREES+=("$workspace_name|$wt_path")
    done < <(git worktree list --porcelain 2>/dev/null | grep "^worktree " | cut -d' ' -f2-)
done < <(find "$WORK_BASE" -type d -name ".git" -print0 2>/dev/null)

if [[ ${#WORKTREES[@]} -eq 0 ]]; then
    echo "No worktrees found under $WORK_BASE"
    exit 0
fi

echo "Found ${#WORKTREES[@]} worktrees to initialize"

# Get current workspace count to know where we're starting
INITIAL_WS=$(niri msg --json workspaces | jq 'length')

CREATED=0
for entry in "${WORKTREES[@]}"; do
    workspace_name="${entry%%|*}"
    wt_path="${entry#*|}"
    
    # Check if workspace with this name already exists
    EXISTING=$(niri msg --json workspaces | jq -r ".[] | select(.name == \"$workspace_name\") | .id")
    
    if [[ -n "$EXISTING" ]]; then
        echo "Workspace already exists: $workspace_name (id: $EXISTING)"
        continue
    fi
    
    # Check if tmux session exists
    if ! tmux has-session -t "$workspace_name" 2>/dev/null; then
        echo "Warning: tmux session '$workspace_name' not found, creating it..."
        tmux new-session -d -s "$workspace_name" -c "$wt_path"
    fi
    
    echo "Creating workspace: $workspace_name -> $wt_path"
    
    # Create a new workspace by focusing down (creates empty workspace at end)
    niri msg action focus-workspace-down
    
    # Small delay to let workspace be created
    sleep 0.2
    
    # Name the workspace
    niri msg action set-workspace-name "$workspace_name"
    
    # Spawn ghostty attached to the tmux session for this worktree
    ghostty -e tmux attach-session -t "$workspace_name" &
    disown
    
    ((CREATED++))
    
    # Brief pause between workspace creations
    sleep 0.5
done

# Return to first workspace
sleep 0.3
niri msg action focus-workspace 1

echo ""
echo "Niri worktree workspaces initialized"
echo "  Total worktrees found: ${#WORKTREES[@]}"
echo "  Workspaces created: $CREATED"
