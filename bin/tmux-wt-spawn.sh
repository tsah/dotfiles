#!/bin/bash
# Tmux-native worktree spawn picker
# If in git repo: show branch picker directly
# If not: show repo picker first, then branch picker
#
# Used with Alt+w keybinding in tmux

# Ensure ~/dotfiles/bin is in PATH — tmux run-shell doesn't source zshrc.
export PATH="$HOME/dotfiles/bin:$HOME/.local/bin:$PATH"

# Get the current pane's working directory
PANE_PATH=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || echo "$PWD")

# Check if in git repo
if git -C "$PANE_PATH" rev-parse --is-inside-work-tree &>/dev/null; then
    cd "$PANE_PATH"
    REPO_PATH=$(git worktree list --porcelain | grep "^worktree " | head -1 | cut -d' ' -f2)
    REPO_NAME=$(basename "$REPO_PATH")
else
    # Pick repo from zoxide (filtered to git repos)
    GIT_REPOS=$(zoxide query -l | while IFS= read -r dir; do
        if [ -d "$dir/.git" ]; then
            echo "$dir"
        fi
    done)

    [[ -z "$GIT_REPOS" ]] && exit 0

    REPO_FZF_OPTS=(
        --no-sort --border
        --bind 'alt-b:abort'
        --border-label ' NOT IN A GIT REPO '
        --border-label-pos 3
        --color 'header:#e5c07b,prompt:#e5c07b:bold,pointer:#e5c07b,border:#e5c07b,label:#e5c07b:bold,info:8'
        --header 'Select a git repository to spawn a worktree in'
        --prompt 'Git Repo > '
        --preview 'cd {} && git log --oneline -10 2>/dev/null || echo "No commits"'
    )

    if command -v fzf-tmux >/dev/null 2>&1 && [[ -n "${TMUX:-}" ]]; then
        SELECTED_REPO=$(echo "$GIT_REPOS" | fzf-tmux -p 95%,80% "${REPO_FZF_OPTS[@]}")
    else
        SELECTED_REPO=$(echo "$GIT_REPOS" | fzf "${REPO_FZF_OPTS[@]}")
    fi

    [[ -z "$SELECTED_REPO" ]] && exit 0
    REPO_PATH="$SELECTED_REPO"
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
