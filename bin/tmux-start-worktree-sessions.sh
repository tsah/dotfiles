#!/bin/bash
# Auto-start tmux sessions for all existing worktrees under ~/dev/work
# Run this on startup to restore your work environment

WORK_BASE="${1:-$HOME/dev/work}"

if [[ ! -d "$WORK_BASE" ]]; then
    echo "Work directory not found: $WORK_BASE"
    exit 1
fi

# Find all git repositories (including worktrees) under ~/dev/work
find "$WORK_BASE" -type d -name ".git" 2>/dev/null | while read -r gitdir; do
    worktree_path=$(dirname "$gitdir")
    
    # Get all worktrees for this repo
    cd "$worktree_path" 2>/dev/null || continue
    
    git worktree list --porcelain 2>/dev/null | grep "^worktree " | cut -d' ' -f2- | while read -r wt_path; do
        # Skip broken repos
        [[ "$wt_path" == *".broken_repos"* ]] && continue
        
        session_name=$(basename "$wt_path")
        
        # Skip if session already exists
        tmux has-session -t "$session_name" 2>/dev/null && continue
        
        # Create detached session in the worktree
        tmux new-session -d -s "$session_name" -c "$wt_path"
        echo "Created session: $session_name -> $wt_path"
    done
done

echo "Worktree sessions initialized"
