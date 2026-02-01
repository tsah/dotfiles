#!/bin/bash
# Tmux-native worktree spawn picker
# If in git repo: show branch picker directly
# If not: show repo picker first, then branch picker
#
# Used with Alt+w keybinding in tmux

# Check if in git repo
if git rev-parse --is-inside-work-tree &>/dev/null; then
    REPO_PATH=$(git worktree list --porcelain | grep "^worktree " | head -1 | cut -d' ' -f2)
    REPO_NAME=$(basename "$REPO_PATH")
else
    # Pick repo from sesh/zoxide (filtered to git repos)
    REPOS=$(sesh list -z | while read -r dir; do
        expanded="${dir/#\~/$HOME}"
        [[ -d "$expanded/.git" ]] && echo "$dir"
    done)
    
    [[ -z "$REPOS" ]] && exit 0
    
    SELECTED_REPO=$(echo "$REPOS" | fzf-tmux -p 80%,70% \
        --no-sort --border-label ' Select Git Repository ' \
        --prompt '📁  ' \
        --preview 'dir="${1/#\~/$HOME}"; cd "$dir" && git log --oneline -10 2>/dev/null || echo "No commits"')
    
    [[ -z "$SELECTED_REPO" ]] && exit 0
    REPO_PATH="${SELECTED_REPO/#\~/$HOME}"
    cd "$REPO_PATH" || exit 1
    REPO_NAME=$(basename "$REPO_PATH")
fi

# Get the main worktree root (in case we selected a worktree)
MAIN_REPO_ROOT=$(git worktree list --porcelain | grep -E "^worktree " | head -1 | cut -d' ' -f2)
if [[ -n "$MAIN_REPO_ROOT" && "$REPO_PATH" != "$MAIN_REPO_ROOT" ]]; then
    cd "$MAIN_REPO_ROOT" || exit 1
    REPO_NAME=$(basename "$MAIN_REPO_ROOT")
fi

# Show branch picker with ability to type new names
BRANCHES=$(git branch -a --format='%(refname:short)' | sed 's|^origin/||' | grep -v '^HEAD$' | sort -u)

BRANCH=$(echo "$BRANCHES" | fzf-tmux -p 80%,70% \
    --print-query --no-sort \
    --border-label " Spawn worktree in $REPO_NAME " \
    --prompt '🌿  ' \
    --header 'Enter: select | Ctrl-N: use typed text' \
    --bind 'ctrl-n:become(echo "{q}")' \
    --preview 'branch="{}"; [[ -n "$branch" ]] && git log --oneline -10 "$branch" 2>/dev/null || echo "New branch"')

# Parse result (query on line 1, selection on line 2)
QUERY=$(echo "$BRANCH" | head -1)
SELECTED=$(echo "$BRANCH" | tail -1)
BRANCH_NAME="${SELECTED:-$QUERY}"

[[ -z "$BRANCH_NAME" ]] && exit 0

# Clean up branch name
BRANCH_NAME=$(echo "$BRANCH_NAME" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]/-/g')

# Spawn worktree and switch to session (tmux mode)
exec ~/dotfiles/bin/wt spawn "$BRANCH_NAME"
