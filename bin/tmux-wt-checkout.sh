#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/bootstrap-path.sh"
. "$SCRIPT_DIR/lib/wt-compat.sh"

PANE_PATH=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || echo "$PWD")

if ! wt_compat_resolve_context "$PANE_PATH"; then
    echo "Error: Not in a supported git repository" >&2
    exit 1
fi

COMMON_DIR="$WT_COMPAT_COMMON_DIR"
CONTAINER_ROOT="$WT_COMPAT_CONTAINER_ROOT"
REPO_NAME="$WT_COMPAT_REPO_NAME"

git --git-dir="$COMMON_DIR" fetch origin --quiet

AVAILABLE=$(git --git-dir="$COMMON_DIR" branch -a --format='%(refname:short)' \
    | sed 's|^origin/||' \
    | grep -v '^HEAD$' \
    | grep -v '^origin$' \
    | sort -u)

if [[ -z "$AVAILABLE" ]]; then
    tmux display-message "No local or remote branches found"
    exit 0
fi

BRANCH_PREVIEW=$(printf 'branch="{}"; if [[ -n "$branch" ]]; then git --git-dir=%q log --oneline -10 "$branch" 2>/dev/null || git --git-dir=%q log --oneline -10 "origin/$branch" 2>/dev/null || echo "No commits"; else echo "No commits"; fi' "$COMMON_DIR" "$COMMON_DIR")

set +e
if command -v fzf-tmux >/dev/null 2>&1 && [[ -n "${TMUX:-}" ]]; then
    SELECTED=$(echo "$AVAILABLE" | fzf-tmux -p 80%,70% \
        --no-sort \
        --border-label " Checkout branch in $REPO_NAME " \
        --prompt '  ' \
        --header 'Enter: open existing worktree/session or create one' \
        --preview "$BRANCH_PREVIEW")
else
    SELECTED=$(echo "$AVAILABLE" | fzf \
        --no-sort \
        --border-label " Checkout branch in $REPO_NAME " \
        --prompt '  ' \
        --header 'Enter: open existing worktree/session or create one' \
        --preview "$BRANCH_PREVIEW")
fi
PICK_STATUS=$?
set -e

if [[ $PICK_STATUS -ne 0 || -z "$SELECTED" ]]; then
    exit 0
fi

BRANCH_NAME=$(echo "$SELECTED" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

cd "$PANE_PATH" || exit 1

"$SCRIPT_DIR/wt" spawn "$BRANCH_NAME"

WORKTREE_PATH=$(wt_compat_find_worktree_for_branch "$COMMON_DIR" "$BRANCH_NAME")
if [[ -n "$WORKTREE_PATH" ]]; then
    wt_compat_zoxide_add "$WORKTREE_PATH" || true
fi
