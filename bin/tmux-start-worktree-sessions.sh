#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/wt-compat.sh"

WORK_BASE="${1:-$HOME/dev/work}"

if [[ ! -d "$WORK_BASE" ]]; then
    echo "Work directory not found: $WORK_BASE"
    exit 1
fi

find "$WORK_BASE" -type d -name ".git" 2>/dev/null | while read -r gitdir; do
    repo_candidate=$(dirname "$gitdir")

    if ! wt_compat_resolve_context "$repo_candidate"; then
        continue
    fi

    printf '%s\t%s\t%s\n' "$WT_COMPAT_CONTAINER_ROOT" "$WT_COMPAT_COMMON_DIR" "$WT_COMPAT_REPO_NAME"
done | awk -F '\t' '!seen[$1]++' | while IFS=$'\t' read -r container_root common_dir repo_name; do
    git --git-dir="$common_dir" worktree list --porcelain 2>/dev/null | awk '
        $1 == "worktree" {
            wt = substr($0, 10)
            next
        }
        $1 == "branch" {
            branch = $2
            sub(/^refs\/heads\//, "", branch)
            print wt "\t" branch
        }
    ' | while IFS=$'\t' read -r wt_path branch_name; do
        [[ -z "$wt_path" || -z "$branch_name" ]] && continue
        [[ "$wt_path" == *".broken_repos"* ]] && continue

        session_name=$(wt_compat_session_name "$container_root" "$branch_name")

        tmux has-session -t "$session_name" 2>/dev/null && continue

        tmux new-session -d -s "$session_name" -c "$wt_path"
        tmux rename-window -t "$session_name:1" 'opencode'
        echo "Created session: $session_name -> $wt_path"
    done
done

echo "Worktree sessions initialized"
