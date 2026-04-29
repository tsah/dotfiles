#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/bootstrap-path.sh"

worktree_path="${1:-}"
session_name="${2:-}"
log_file="${XDG_STATE_HOME:-$HOME/.local/state}/tmux-wt-destroy.log"

if [[ -z "$worktree_path" || -z "$session_name" ]]; then
    tmux display-message "Cannot destroy worktree: missing tmux context" 2>/dev/null || true
    exit 1
fi

mkdir -p "$(dirname "$log_file")"

if ! tmux switch-client -p 2>/dev/null; then
    tmux display-message "No previous tmux session to switch to" 2>/dev/null || true
    exit 1
fi

(
    cd "$worktree_path"
    WT_DESTROY_ASSUME_YES=1 WT_DESTROY_TMUX_SESSION="$session_name" "$SCRIPT_DIR/wt" destroy
) >>"$log_file" 2>&1 &
