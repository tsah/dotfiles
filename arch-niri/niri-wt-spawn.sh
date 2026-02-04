#!/bin/bash
# Niri worktree spawn picker
# Shows branch picker, then spawns worktree + workspace
#
# Keybind: Mod+Y

SELECTION_FILE=$(mktemp)
trap "rm -f $SELECTION_FILE" EXIT

# Need to be in a git repo - use most recent zoxide entry that's a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    REPO_PATH=$(zoxide query -l | while read -r dir; do
        [[ -d "$dir/.git" ]] && echo "$dir" && break
    done)
    
    if [[ -z "$REPO_PATH" ]]; then
        notify-send "Worktree Spawn" "No git repository found"
        exit 1
    fi
    cd "$REPO_PATH" || exit 1
fi

# Get main repo root
MAIN_REPO_ROOT=$(git worktree list --porcelain | grep -E "^worktree " | head -1 | cut -d' ' -f2)
if [[ -n "$MAIN_REPO_ROOT" ]]; then
    cd "$MAIN_REPO_ROOT" || exit 1
fi

REPO_NAME=$(basename "$(pwd)")

# Get branches
BRANCHES=$(git branch -a --format='%(refname:short)' | sed 's|^origin/||' | grep -v '^HEAD$' | sort -u)

# Run fzf in ghostty popup - write selection to file
ghostty --class=wt-spawn-picker -e bash -c '
BRANCHES="'"$BRANCHES"'"
REPO_NAME="'"$REPO_NAME"'"
SELECTION_FILE="'"$SELECTION_FILE"'"

SELECTED=$(echo "$BRANCHES" | fzf \
    --prompt="Branch ($REPO_NAME)> " \
    --reverse --height=100% \
    --print-query \
    --header="Enter: select | Type new branch name" \
    | tail -1)

if [[ -n "$SELECTED" ]]; then
    BRANCH=$(echo "$SELECTED" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]/-/g")
    echo "$BRANCH" > "$SELECTION_FILE"
fi
'

# Wait a moment for file to be written
sleep 0.2

# Read selection and spawn
if [[ -s "$SELECTION_FILE" ]]; then
    BRANCH=$(cat "$SELECTION_FILE")
    cd "$MAIN_REPO_ROOT" || exit 1
    
    # Run nwt spawn (this will create workspace on current/new workspace)
    nwt spawn "$BRANCH"
fi
