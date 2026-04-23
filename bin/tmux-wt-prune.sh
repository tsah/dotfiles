#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/wt-compat.sh"

export PATH="$HOME/dotfiles/bin:$HOME/.local/bin:$PATH"

notify() {
    local message="$1"
    if command -v tmux >/dev/null 2>&1 && [[ -n "${TMUX:-}" ]]; then
        tmux display-message "$message"
    else
        printf '%s\n' "$message"
    fi
}


list_repo_choices() {
    zoxide query -l | while IFS= read -r dir; do
        if wt_compat_resolve_context "$dir"; then
            printf '%s\n' "$WT_COMPAT_CONTAINER_ROOT"
        fi
    done | awk '!seen[$0]++'
}


stale_reason_for_branch() {
    local common_dir="$1"
    local base_ref="$2"
    local branch_name="$3"
    local cherry_output
    local has_plus=0
    local line

    if ! git --git-dir="$common_dir" show-ref --verify --quiet "refs/heads/$branch_name"; then
        return 1
    fi

    if git --git-dir="$common_dir" merge-base --is-ancestor "refs/heads/$branch_name" "$base_ref" >/dev/null 2>&1; then
        printf 'ancestor\n'
        return 0
    fi

    cherry_output=$(git --git-dir="$common_dir" cherry "$base_ref" "refs/heads/$branch_name" 2>/dev/null || true)
    while IFS= read -r line; do
        case "$line" in
            +*)
                has_plus=1
                break
                ;;
        esac
    done <<< "$cherry_output"

    if [[ $has_plus -eq 0 ]]; then
        printf 'patch-equivalent\n'
        return 0
    fi

    return 1
}


worktree_dirty_state() {
    local worktree_path="$1"
    local status

    if [[ ! -d "$worktree_path" ]]; then
        printf 'missing\n'
        return 0
    fi

    status=$(git -C "$worktree_path" status --porcelain 2>/dev/null || true)
    if [[ -n "$status" ]]; then
        printf 'dirty\n'
    else
        printf 'clean\n'
    fi
}


build_stale_rows() {
    local common_dir="$1"
    local container_root="$2"
    local mode="$3"
    local base_ref="$4"
    local default_branch="$5"
    local wt_path
    local branch_name
    local reason
    local dirty_state
    local session_name
    local session_state
    local pretty_path
    local display

    git --git-dir="$common_dir" worktree list --porcelain 2>/dev/null | awk '
        $1 == "worktree" {
            wt = substr($0, 10)
            branch = ""
            detached = 0
            next
        }
        $1 == "branch" {
            branch = $2
            sub(/^refs\/heads\//, "", branch)
            next
        }
        $1 == "detached" {
            detached = 1
            next
        }
        $0 == "" {
            if (wt != "" && branch != "" && detached == 0) {
                print wt "\t" branch
            }
            wt = ""
            branch = ""
            detached = 0
        }
        END {
            if (wt != "" && branch != "" && detached == 0) {
                print wt "\t" branch
            }
        }
    ' | while IFS=$'\t' read -r wt_path branch_name; do
        [[ -z "$wt_path" || -z "$branch_name" ]] && continue

        if [[ -n "$default_branch" && "$branch_name" == "$default_branch" ]]; then
            continue
        fi

        if [[ "$mode" == "legacy" && "$wt_path" == "$container_root" ]]; then
            continue
        fi

        reason=$(stale_reason_for_branch "$common_dir" "$base_ref" "$branch_name" 2>/dev/null || true)
        [[ -z "$reason" ]] && continue

        dirty_state=$(worktree_dirty_state "$wt_path")
        session_name=$(wt_compat_session_name "$container_root" "$branch_name")
        session_state='closed'
        if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$session_name" 2>/dev/null; then
            session_state='open'
        fi

        if [[ "$wt_path" == "$HOME/"* ]]; then
            pretty_path="~/${wt_path#$HOME/}"
        else
            pretty_path="$wt_path"
        fi
        display=$(printf '[%s] [%s] [%s] %s -> %s' "$dirty_state" "$session_state" "$reason" "$branch_name" "$pretty_path")

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$display" "$branch_name" "$wt_path" "$dirty_state" "$session_state" "$reason" "$session_name"
    done
}


preview_row() {
    local common_dir="$1"
    local base_ref="$2"
    local branch_name="$3"
    local worktree_path="$4"
    local reason
    local dirty_state
    local unique_commits
    local status_lines

    reason=$(stale_reason_for_branch "$common_dir" "$base_ref" "$branch_name" 2>/dev/null || true)
    [[ -z "$reason" ]] && reason='not stale anymore'

    dirty_state=$(worktree_dirty_state "$worktree_path")

    printf 'Branch: %s\n' "$branch_name"
    printf 'Worktree: %s\n' "$worktree_path"
    printf 'Base: %s\n' "$base_ref"
    printf 'Merge check: %s\n' "$reason"
    printf 'Worktree state: %s\n\n' "$dirty_state"

    printf 'Commits in %s not in %s:\n' "$branch_name" "$base_ref"
    unique_commits=$(git --git-dir="$common_dir" log --oneline --no-decorate -12 "$base_ref..refs/heads/$branch_name" 2>/dev/null || true)
    if [[ -n "$unique_commits" ]]; then
        printf '%s\n' "$unique_commits"
    else
        printf '(none)\n'
    fi

    printf '\nWorktree status:\n'
    if [[ "$dirty_state" == 'missing' ]]; then
        printf '(directory missing)\n'
        return 0
    fi

    status_lines=$(git -C "$worktree_path" status --short 2>/dev/null || true)
    if [[ -n "$status_lines" ]]; then
        printf '%s\n' "$status_lines"
    else
        printf '(clean)\n'
    fi
}


delete_worktree() {
    local repo_path="$1"
    local branch_name="$2"
    local worktree_path="$3"
    local common_dir
    local container_root
    local mode
    local base_ref
    local reason
    local dirty_state
    local session_name
    local current_session

    if ! wt_compat_resolve_context "$repo_path"; then
        notify "Could not resolve repository context"
        return 1
    fi

    common_dir="$WT_COMPAT_COMMON_DIR"
    container_root="$WT_COMPAT_CONTAINER_ROOT"
    mode="$WT_COMPAT_MODE"

    base_ref=$(wt_compat_default_base_ref "$common_dir" 2>/dev/null || true)
    if [[ -n "$base_ref" ]]; then
        reason=$(stale_reason_for_branch "$common_dir" "$base_ref" "$branch_name" 2>/dev/null || true)
        if [[ -z "$reason" ]]; then
            notify "Skipped $branch_name: not stale anymore"
            return 1
        fi
    fi

    dirty_state=$(worktree_dirty_state "$worktree_path")

    if [[ "$mode" == 'bare' ]]; then
        if ! "$SCRIPT_DIR/wwt" -C "$container_root" remove --foreground --force --no-delete-branch "$branch_name" >/dev/null 2>&1; then
            notify "Failed deleting $branch_name"
            return 1
        fi
    else
        if ! git -C "$container_root" worktree remove "$worktree_path" --force >/dev/null 2>&1; then
            notify "Failed deleting $branch_name"
            return 1
        fi
    fi

    if command -v tmux >/dev/null 2>&1; then
        session_name=$(wt_compat_session_name "$container_root" "$branch_name")
        if tmux has-session -t "$session_name" 2>/dev/null; then
            current_session=$(tmux display-message -p '#S' 2>/dev/null || true)
            if [[ -n "${TMUX:-}" && "$current_session" == "$session_name" ]]; then
                tmux switch-client -p 2>/dev/null || tmux switch-client -n 2>/dev/null || true
            fi
            tmux kill-session -t "$session_name" >/dev/null 2>&1 || true
        fi
    fi

    notify "Deleted $branch_name ($dirty_state)"
    return 0
}


jump_or_reopen_session() {
    local repo_path="$1"
    local branch_name="$2"
    local worktree_path="$3"
    local container_root
    local session_name

    if ! command -v tmux >/dev/null 2>&1; then
        notify "tmux is not available"
        return 1
    fi

    if ! wt_compat_resolve_context "$repo_path"; then
        notify "Could not resolve repository context"
        return 1
    fi

    container_root="$WT_COMPAT_CONTAINER_ROOT"
    session_name=$(wt_compat_session_name "$container_root" "$branch_name")

    if tmux has-session -t "$session_name" 2>/dev/null; then
        if [[ -n "${TMUX:-}" ]]; then
            tmux switch-client -t "$session_name" >/dev/null 2>&1 || true
        else
            tmux attach-session -t "$session_name"
        fi
        return 0
    fi

    if [[ ! -d "$worktree_path" ]]; then
        notify "Cannot reopen session: worktree missing for $branch_name"
        return 1
    fi

    if ! tmux new-session -d -s "$session_name" -c "$worktree_path" >/dev/null 2>&1; then
        notify "Failed creating session $session_name"
        return 1
    fi

    tmux rename-window -t "$session_name:1" 'opencode' >/dev/null 2>&1 || true

    if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "$session_name" >/dev/null 2>&1 || true
    else
        tmux attach-session -t "$session_name"
    fi
}


pick_repo_context() {
    local pane_path
    local git_repos
    local selected_repo
    local pick_status
    local -a repo_fzf_opts

    pane_path=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || echo "$PWD")

    if wt_compat_resolve_context "$pane_path"; then
        REPO_PATH="$WT_COMPAT_CONTAINER_ROOT"
        REPO_NAME="$WT_COMPAT_REPO_NAME"
        COMMON_DIR="$WT_COMPAT_COMMON_DIR"
        CONTAINER_ROOT="$WT_COMPAT_CONTAINER_ROOT"
        MODE="$WT_COMPAT_MODE"
        return 0
    fi

    git_repos=$(list_repo_choices)
    [[ -z "$git_repos" ]] && return 1

    repo_fzf_opts=(
        --no-sort --border
        --bind 'alt-b:abort'
        --border-label ' NOT IN A GIT REPO '
        --border-label-pos 3
        --color 'header:#e5c07b,prompt:#e5c07b:bold,pointer:#e5c07b,border:#e5c07b,label:#e5c07b:bold,info:8'
        --header 'Select a git repository to prune stale worktrees in'
        --prompt 'Git Repo > '
        --preview 'path={}; if git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then git -C "$path" log --oneline -10 2>/dev/null || echo "No commits"; elif [ -d "$path/.git" ] && [ "$(git --git-dir="$path/.git" rev-parse --is-bare-repository 2>/dev/null || true)" = "true" ]; then git --git-dir="$path/.git" log --oneline -10 2>/dev/null || echo "No commits"; else echo "No commits"; fi'
    )

    set +e
    if command -v fzf-tmux >/dev/null 2>&1 && [[ -n "${TMUX:-}" ]]; then
        selected_repo=$(echo "$git_repos" | fzf-tmux -p 95%,80% "${repo_fzf_opts[@]}")
    else
        selected_repo=$(echo "$git_repos" | fzf "${repo_fzf_opts[@]}")
    fi
    pick_status=$?
    set -e

    if [[ $pick_status -ne 0 || -z "$selected_repo" ]]; then
        return 1
    fi

    if ! wt_compat_resolve_context "$selected_repo"; then
        notify "Could not resolve repository context for $selected_repo"
        return 1
    fi

    REPO_PATH="$WT_COMPAT_CONTAINER_ROOT"
    REPO_NAME="$WT_COMPAT_REPO_NAME"
    COMMON_DIR="$WT_COMPAT_COMMON_DIR"
    CONTAINER_ROOT="$WT_COMPAT_CONTAINER_ROOT"
    MODE="$WT_COMPAT_MODE"
    return 0
}


rows_for_repo_path() {
    local repo_path="$1"
    local base_ref
    local default_branch

    [[ -z "$repo_path" ]] && return 1

    if ! wt_compat_resolve_context "$repo_path"; then
        return 1
    fi

    base_ref=$(wt_compat_default_base_ref "$WT_COMPAT_COMMON_DIR" 2>/dev/null || true)
    [[ -z "$base_ref" ]] && return 1

    default_branch=$(wt_compat_default_branch_name "$WT_COMPAT_COMMON_DIR" 2>/dev/null || true)
    if [[ -z "$default_branch" ]]; then
        default_branch="${base_ref#origin/}"
    fi

    build_stale_rows "$WT_COMPAT_COMMON_DIR" "$WT_COMPAT_CONTAINER_ROOT" "$WT_COMPAT_MODE" "$base_ref" "$default_branch"
}


if [[ "${1:-}" == "--rows" ]]; then
    rows_for_repo_path "${2:-}"
    exit 0
fi

if [[ "${1:-}" == "--preview" ]]; then
    preview_row "${2:-}" "${3:-}" "${4:-}" "${5:-}"
    exit 0
fi

if [[ "${1:-}" == "--delete" ]]; then
    delete_worktree "${2:-}" "${3:-}" "${4:-}"
    exit 0
fi

if [[ "${1:-}" == "--jump" ]]; then
    jump_or_reopen_session "${2:-}" "${3:-}" "${4:-}"
    exit 0
fi

if ! pick_repo_context; then
    exit 0
fi

git --git-dir="$COMMON_DIR" fetch origin --quiet >/dev/null 2>&1 || true

BASE_REF=$(wt_compat_default_base_ref "$COMMON_DIR" 2>/dev/null || true)
if [[ -z "$BASE_REF" ]]; then
    notify "Could not determine default branch for $REPO_NAME"
    exit 1
fi

DEFAULT_BRANCH=$(wt_compat_default_branch_name "$COMMON_DIR" 2>/dev/null || true)
if [[ -z "$DEFAULT_BRANCH" ]]; then
    DEFAULT_BRANCH="${BASE_REF#origin/}"
fi

ROWS=$(build_stale_rows "$COMMON_DIR" "$CONTAINER_ROOT" "$MODE" "$BASE_REF" "$DEFAULT_BRANCH")
if [[ -z "$ROWS" ]]; then
    notify "No stale worktrees in $REPO_NAME"
    exit 0
fi

SELF=$(realpath "$0")
SELF_Q=$(printf '%q' "$SELF")
REPO_Q=$(printf '%q' "$REPO_PATH")
COMMON_Q=$(printf '%q' "$COMMON_DIR")
BASE_Q=$(printf '%q' "$BASE_REF")

set +e
if command -v fzf-tmux >/dev/null 2>&1 && [[ -n "${TMUX:-}" ]]; then
    printf '%s\n' "$ROWS" | fzf-tmux -p 95%,80% \
        --ansi \
        --no-sort \
        --delimiter=$'\t' \
        --with-nth=1 \
        --border-label " Prune stale worktrees in $REPO_NAME " \
        --prompt 'prune> ' \
        --header 'Enter: jump/reopen session | Ctrl-D: delete selected worktree (+tmux session)' \
        --preview "$SELF_Q --preview $COMMON_Q $BASE_Q {2} {3}" \
        --bind "enter:execute-silent($SELF_Q --jump $REPO_Q {2} {3})+abort" \
        --bind "ctrl-d:execute-silent($SELF_Q --delete $REPO_Q {2} {3})+reload($SELF_Q --rows $REPO_Q)" \
        --bind 'alt-b:abort' >/dev/null
else
    printf '%s\n' "$ROWS" | fzf \
        --ansi \
        --no-sort \
        --delimiter=$'\t' \
        --with-nth=1 \
        --border-label " Prune stale worktrees in $REPO_NAME " \
        --prompt 'prune> ' \
        --header 'Enter: jump/reopen session | Ctrl-D: delete selected worktree (+tmux session)' \
        --preview "$SELF_Q --preview $COMMON_Q $BASE_Q {2} {3}" \
        --bind "enter:execute-silent($SELF_Q --jump $REPO_Q {2} {3})+abort" \
        --bind "ctrl-d:execute-silent($SELF_Q --delete $REPO_Q {2} {3})+reload($SELF_Q --rows $REPO_Q)" \
        --bind 'alt-b:abort' >/dev/null
fi
set -e
