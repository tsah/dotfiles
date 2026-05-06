#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/bootstrap-path.sh"

worktree_path="${1:-}"
session_name="${2:-}"

notify() {
    local message="$1"

    tmux display-message "$message" 2>/dev/null || printf '%s\n' "$message"
}

if [[ -z "$worktree_path" || ! -d "$worktree_path" ]]; then
    notify "Cannot open PR: current pane path is unavailable"
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    notify "Cannot open PR: gh is not installed"
    exit 1
fi

if ! command -v xdg-open >/dev/null 2>&1; then
    notify "Cannot open PR: xdg-open is not installed"
    exit 1
fi

branch_name=$(git -C "$worktree_path" branch --show-current 2>/dev/null || true)
if [[ -z "$branch_name" ]]; then
    notify "Cannot open PR: no git branch for ${session_name:-current session}"
    exit 1
fi

pr_url=$(gh -R "$(git -C "$worktree_path" remote get-url origin 2>/dev/null || true)" pr view "$branch_name" --json url --jq .url 2>/dev/null || true)
if [[ -z "$pr_url" ]]; then
    pr_url=$(cd "$worktree_path" && gh pr view "$branch_name" --json url --jq .url 2>/dev/null || true)
fi

if [[ -z "$pr_url" ]]; then
    notify "No PR found for $branch_name"
    exit 1
fi

notify "Opening PR for $branch_name"
xdg-open "$pr_url" >/dev/null 2>&1 &
