#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/bootstrap-path.sh"
. "$SCRIPT_DIR/lib/wt-compat.sh"

POST_SPAWN_RUN_COMMANDS=""

list_repo_choices() {
    zoxide query -l | while IFS= read -r dir; do
        if wt_compat_resolve_context "$dir"; then
            printf '%s\n' "$WT_COMPAT_CONTAINER_ROOT"
        fi
    done | awk '!seen[$0]++'
}

append_run_command() {
    local cmd="$1"

    if [[ -z "$cmd" ]]; then
        return 0
    fi

    if [[ -z "$POST_SPAWN_RUN_COMMANDS" ]]; then
        POST_SPAWN_RUN_COMMANDS="$cmd"
    else
        POST_SPAWN_RUN_COMMANDS="${POST_SPAWN_RUN_COMMANDS} && ${cmd}"
    fi
}

is_interactive_agent_command() {
    local cmd="$1"

    case "$cmd" in
        oc|oc\ *|opencode|opencode\ *|claude|claude\ *|pi|pi\ *)
            return 0
            ;;
    esac

    return 1
}

collect_setup_run_commands() {
    local setup_root="$1"
    local container_root="$2"
    local setup_mode="${WT_SPAWN_MODE:-manual}"
    local setup_config="$setup_root/.wtconfig"
    local post_spawn_file="$container_root/.wtcompat-post-spawn-run"

    POST_SPAWN_RUN_COMMANDS=""

    if [[ "$setup_mode" != "auto" ]]; then
        setup_mode="manual"
    fi

    if [[ -f "$setup_config" ]]; then
        while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
            local line="$raw_line"
            local key=""
            local value=""
            local apply=false

            line=${line#"${line%%[![:space:]]*}"}
            line=${line%"${line##*[![:space:]]}"}

            case "$line" in
                ''|\#*)
                    continue
                    ;;
            esac

            key=${line%%[[:space:]]*}
            value=${line#"$key"}
            value=${value#"${value%%[![:space:]]*}"}
            value=${value%"${value##*[![:space:]]}"}

            case "$key" in
                run)
                    apply=true
                    ;;
                run-manual)
                    [[ "$setup_mode" == "manual" ]] && apply=true
                    ;;
                run-auto)
                    [[ "$setup_mode" == "auto" ]] && apply=true
                    ;;
                *)
                    apply=false
                    ;;
            esac

            if [[ "$apply" != true || -z "$value" ]]; then
                continue
            fi

            if is_interactive_agent_command "$value"; then
                continue
            fi

            append_run_command "$value"
        done < "$setup_config"
    fi

    if [[ -f "$post_spawn_file" ]]; then
        while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
            local cmd="$raw_line"

            cmd=${cmd#"${cmd%%[![:space:]]*}"}
            cmd=${cmd%"${cmd##*[![:space:]]}"}

            case "$cmd" in
                ''|\#*)
                    continue
                    ;;
            esac

            if is_interactive_agent_command "$cmd"; then
                continue
            fi

            append_run_command "$cmd"
        done < "$post_spawn_file"
    fi
}

pick_assistant() {
    local options selected pick_status

    options=$'opencode\tOpenCode\tOpen OpenCode in the spawned worktree\nclaude\tClaude Code\tOpen Claude Code in the spawned worktree\npi\tPi\tOpen pi in the spawned worktree'

    set +e
    if command -v fzf-tmux >/dev/null 2>&1 && [[ -n "${TMUX:-}" ]]; then
        selected=$(printf '%s\n' "$options" | fzf-tmux -p 75%,40% \
            --delimiter=$'\t' \
            --with-nth=2,3 \
            --no-sort \
            --border \
            --bind 'alt-b:abort' \
            --border-label ' Launch agent ' \
            --prompt 'Agent > ' \
            --header 'Select which agent to open in the new worktree')
    else
        selected=$(printf '%s\n' "$options" | fzf \
            --delimiter=$'\t' \
            --with-nth=2,3 \
            --no-sort \
            --border \
            --bind 'alt-b:abort' \
            --border-label ' Launch agent ' \
            --prompt 'Agent > ' \
            --header 'Select which agent to open in the new worktree')
    fi
    pick_status=$?
    set -e

    if [[ $pick_status -ne 0 || -z "$selected" ]]; then
        return 1
    fi

    printf '%s\n' "${selected%%$'\t'*}"
}

require_assistant_command() {
    local assistant="$1"
    local required_cmd=""

    case "$assistant" in
        opencode)
            required_cmd="oc"
            ;;
        claude)
            required_cmd="claude"
            ;;
        pi)
            required_cmd="pi"
            ;;
        *)
            echo "Error: Unknown assistant: $assistant" >&2
            exit 1
            ;;
    esac

    if ! command -v "$required_cmd" >/dev/null 2>&1; then
        echo "Error: Required command not found: $required_cmd" >&2
        exit 1
    fi
}

assistant_window_name() {
    local assistant="$1"

    case "$assistant" in
        opencode)
            printf 'opencode\n'
            ;;
        claude)
            printf 'claude\n'
            ;;
        pi)
            printf 'p:pi\n'
            ;;
        *)
            echo "Error: Unknown assistant: $assistant" >&2
            exit 1
            ;;
    esac
}

assistant_launch_command() {
    local assistant="$1"
    local worktree_path="$2"
    local assistant_cmd=""
    local launch_command="cd \"$worktree_path\""

    case "$assistant" in
        opencode)
            assistant_cmd="oc"
            ;;
        claude)
            assistant_cmd="claude"
            ;;
        pi)
            assistant_cmd="pi"
            ;;
        *)
            echo "Error: Unknown assistant: $assistant" >&2
            exit 1
            ;;
    esac

    if [[ -n "$POST_SPAWN_RUN_COMMANDS" ]]; then
        launch_command+=" && $POST_SPAWN_RUN_COMMANDS"
    fi

    if [[ "$assistant" != "opencode" ]]; then
        launch_command+=' && if [ -f ".venv/bin/activate" ]; then . ".venv/bin/activate"; elif [ -f "venv/bin/activate" ]; then . "venv/bin/activate"; else true; fi'
    fi

    launch_command+=" && ${assistant_cmd}"
    printf '%s\n' "$launch_command"
}

launch_assistant() {
    local assistant="$1"
    local session_name="$2"
    local worktree_path="$3"
    local session_already_exists="$4"
    local window_name launch_command

    window_name=$(assistant_window_name "$assistant")
    launch_command=$(assistant_launch_command "$assistant" "$worktree_path")

    if [[ "$session_already_exists" == true ]]; then
        local window_meta window_index

        window_meta=$(tmux new-window -P -F '#{window_id}|#{window_index}|#{window_name}|#{pane_id}|#{pane_index}' -t "$session_name" -n "$window_name" -c "$worktree_path")
        IFS='|' read -r _window_id window_index _window_name _pane_id _pane_index <<< "$window_meta"
        tmux send-keys -t "$session_name:$window_index" "$launch_command" Enter
        tmux select-window -t "$session_name:$window_index"
        return 0
    fi

    tmux rename-window -t "$session_name:1" "$window_name"
    tmux send-keys -t "$session_name:1" "$launch_command" Enter
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
        --bind 'ctrl-n:become(printf "%s\n" {q})' \
        --preview "$BRANCH_PREVIEW")
else
    BRANCH=$(echo "$BRANCHES" | fzf \
        --print-query --no-sort \
        --border-label " Spawn worktree in $REPO_NAME " \
        --prompt '🌿  ' \
        --header 'Enter: select | Ctrl-N: use typed text' \
        --bind 'ctrl-n:become(printf "%s\n" {q})' \
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

ASSISTANT=$(pick_assistant || true)
[[ -z "$ASSISTANT" ]] && exit 0

require_assistant_command "$ASSISTANT"

WORKTREE_ALREADY_EXISTS=false
EXISTING_WORKTREE=$(wt_compat_find_worktree_for_branch "$COMMON_DIR" "$BRANCH_NAME")
if [[ -n "$EXISTING_WORKTREE" ]]; then
    WORKTREE_ALREADY_EXISTS=true
fi

SESSION_NAME=$(wt_compat_session_name "$REPO_PATH" "$BRANCH_NAME")
SESSION_ALREADY_EXISTS=false
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    SESSION_ALREADY_EXISTS=true
fi

if [[ "$WORKTREE_ALREADY_EXISTS" == false ]]; then
    SETUP_ROOT=$(wt_compat_setup_root "$REPO_PATH")
    collect_setup_run_commands "$SETUP_ROOT" "$REPO_PATH"
else
    POST_SPAWN_RUN_COMMANDS=""
fi

cd "$START_PATH" || exit 1

WT_SKIP_RUN_OC=1 WT_SKIP_RUN_COMMANDS=1 "$SCRIPT_DIR/wt" spawn "$BRANCH_NAME"

WORKTREE_PATH=$(wt_compat_find_worktree_for_branch "$COMMON_DIR" "$BRANCH_NAME")
if [[ -z "$WORKTREE_PATH" ]]; then
    echo "Error: Could not resolve worktree path for branch '$BRANCH_NAME'" >&2
    exit 1
fi

wt_compat_zoxide_add "$WORKTREE_PATH" || true
launch_assistant "$ASSISTANT" "$SESSION_NAME" "$WORKTREE_PATH" "$SESSION_ALREADY_EXISTS"
