#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/wt-compat.sh"

export PATH="$HOME/dotfiles/bin:$HOME/.local/bin:$PATH"

list_repo_choices() {
    zoxide query -l | while IFS= read -r dir; do
        if wt_compat_resolve_context "$dir"; then
            printf '%s\n' "$WT_COMPAT_CONTAINER_ROOT"
        fi
    done | awk '!seen[$0]++'
}


PANE_PATH=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || echo "$PWD")

if wt_compat_resolve_context "$PANE_PATH"; then
    REPO_PATH="$WT_COMPAT_CONTAINER_ROOT"
    REPO_NAME="$WT_COMPAT_REPO_NAME"
    COMMON_DIR="$WT_COMPAT_COMMON_DIR"
    START_PATH="$PANE_PATH"
else
    GIT_REPOS=$(list_repo_choices)
    [[ -z "$GIT_REPOS" ]] && exit 0

    REPO_FZF_OPTS=(
        --no-sort --border
        --bind 'alt-b:abort'
        --border-label ' NOT IN A GIT REPO '
        --border-label-pos 3
        --color 'header:#e5c07b,prompt:#e5c07b:bold,pointer:#e5c07b,border:#e5c07b,label:#e5c07b:bold,info:8'
        --header 'Select a git repository to spawn a worktree in'
        --prompt 'Git Repo > '
        --preview 'path={}; if git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then git -C "$path" log --oneline -10 2>/dev/null || echo "No commits"; elif [ -d "$path/.git" ] && [ "$(git --git-dir="$path/.git" rev-parse --is-bare-repository 2>/dev/null || true)" = "true" ]; then git --git-dir="$path/.git" log --oneline -10 2>/dev/null || echo "No commits"; else echo "No commits"; fi'
    )

    set +e
    if command -v fzf-tmux >/dev/null 2>&1 && [[ -n "${TMUX:-}" ]]; then
        SELECTED_REPO=$(echo "$GIT_REPOS" | fzf-tmux -p 95%,80% "${REPO_FZF_OPTS[@]}")
    else
        SELECTED_REPO=$(echo "$GIT_REPOS" | fzf "${REPO_FZF_OPTS[@]}")
    fi
    REPO_PICK_STATUS=$?
    set -e

    if [[ $REPO_PICK_STATUS -ne 0 || -z "$SELECTED_REPO" ]]; then
        exit 0
    fi

    if ! wt_compat_resolve_context "$SELECTED_REPO"; then
        echo "Error: Could not resolve repository context for $SELECTED_REPO" >&2
        exit 1
    fi

    REPO_PATH="$WT_COMPAT_CONTAINER_ROOT"
    REPO_NAME="$WT_COMPAT_REPO_NAME"
    COMMON_DIR="$WT_COMPAT_COMMON_DIR"
    START_PATH="$REPO_PATH"
fi

BRANCHES=$(git --git-dir="$COMMON_DIR" branch -a --format='%(refname:short)' | sed 's|^origin/||' | grep -v '^HEAD$' | sort -u)
BRANCH_PREVIEW=$(printf 'branch="{}"; if [[ -n "$branch" ]]; then git --git-dir=%q log --oneline -10 "$branch" 2>/dev/null || echo "New branch"; else echo "New branch"; fi' "$COMMON_DIR")

set +e
if command -v fzf-tmux >/dev/null 2>&1 && [[ -n "${TMUX:-}" ]]; then
    BRANCH=$(echo "$BRANCHES" | fzf-tmux -p 80%,70% \
        --print-query --no-sort \
        --border-label " Spawn worktree in $REPO_NAME " \
        --prompt '🌿  ' \
        --header 'Enter: select | Ctrl-N: use typed text' \
        --bind 'ctrl-n:become(echo "{q}")' \
        --preview "$BRANCH_PREVIEW")
else
    BRANCH=$(echo "$BRANCHES" | fzf \
        --print-query --no-sort \
        --border-label " Spawn worktree in $REPO_NAME " \
        --prompt '🌿  ' \
        --header 'Enter: select | Ctrl-N: use typed text' \
        --bind 'ctrl-n:become(echo "{q}")' \
        --preview "$BRANCH_PREVIEW")
fi
BRANCH_PICK_STATUS=$?
set -e

if [[ $BRANCH_PICK_STATUS -eq 130 || $BRANCH_PICK_STATUS -eq 2 || -z "$BRANCH" ]]; then
    exit 0
fi

QUERY=$(echo "$BRANCH" | head -1)
SELECTED=$(echo "$BRANCH" | tail -1)
BRANCH_NAME="${SELECTED:-$QUERY}"

[[ -z "$BRANCH_NAME" ]] && exit 0

BRANCH_NAME=$(echo "$BRANCH_NAME" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]/-/g')

cd "$START_PATH" || exit 1

"$SCRIPT_DIR/wt" spawn "$BRANCH_NAME"

WORKTREE_PATH=$(wt_compat_find_worktree_for_branch "$COMMON_DIR" "$BRANCH_NAME")
if [[ -n "$WORKTREE_PATH" ]]; then
    wt_compat_zoxide_add "$WORKTREE_PATH" || true
fi
