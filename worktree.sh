#!/bin/sh
# Git worktree management script with file copying

# Configuration
DEFAULT_BASE_BRANCH="master"
CONFIG_FILE="$HOME/.wt_files"
DEFAULT_FILE_SET="standard"

# Helper functions
confirm() {
    printf "%s [y/N]: " "$1"
    read -r response
    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

get_main_repo_root() {
    # Get the main repository root (not worktree root)
    MAIN_REPO_ROOT=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
    if [ -z "$MAIN_REPO_ROOT" ]; then
        MAIN_REPO_ROOT=$(git rev-parse --show-toplevel)
    fi
    echo "$MAIN_REPO_ROOT"
}

handle_tmux_session() {
    session_name="$1"
    worktree_path="$2"
    
    if ! command -v tmux >/dev/null 2>&1; then
        echo "Tmux not available, staying in directory..."
        exec "$SHELL"
        return
    fi
    
    # Check if we're already in tmux
    if [ -n "$TMUX" ]; then
        if tmux has-session -t "$session_name" 2>/dev/null; then
            echo "Switching to existing tmux session '$session_name'..."
            tmux switch-client -t "$session_name"
        else
            tmux new-session -d -s "$session_name" -c "$worktree_path"
            tmux rename-window -t "$session_name:1" 'Main'
            echo "Created tmux session '$session_name', switching..."
            tmux switch-client -t "$session_name"
        fi
    else
        if tmux has-session -t "$session_name" 2>/dev/null; then
            echo "Attaching to existing tmux session '$session_name'..."
            tmux attach-session -t "$session_name"
        else
            tmux new-session -d -s "$session_name" -c "$worktree_path"
            tmux rename-window -t "$session_name:1" 'Main'
            echo "Created tmux session '$session_name', attaching..."
            tmux attach-session -t "$session_name"
        fi
    fi
}

kill_tmux_session() {
    session_name="$1"
    if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$session_name" 2>/dev/null; then
        echo "Killing tmux session '$session_name'..."
        tmux kill-session -t "$session_name"
    fi
}

remove_worktree_and_branch() {
    worktree_path="$1"
    branch_name="$2"
    
    echo "Removing worktree..."
    if git worktree remove "$worktree_path" --force; then
        echo "Worktree removed successfully"
        
        if [ "$branch_name" != "(detached)" ] && [ -n "$branch_name" ]; then
            if confirm "Delete branch '$branch_name'?"; then
                if git branch -D "$branch_name"; then
                    echo "Branch '$branch_name' deleted"
                else
                    echo "Failed to delete branch '$branch_name'"
                fi
            else
                echo "Branch '$branch_name' kept"
            fi
        fi
        return 0
    else
        echo "Failed to remove worktree"
        return 1
    fi
}

switch_to_main_session() {
    main_repo_root="$1"
    repo_name=$(basename "$main_repo_root")
    main_session_name="$repo_name-main"
    
    cd "$main_repo_root" || exit 1
    
    if command -v tmux >/dev/null 2>&1; then
        if [ -n "$TMUX" ]; then
            if tmux has-session -t "$main_session_name" 2>/dev/null; then
                echo "Switching to main repo session '$main_session_name'..."
                tmux switch-client -t "$main_session_name"
            else
                tmux new-session -d -s "$main_session_name" -c "$main_repo_root"
                tmux rename-window -t "$main_session_name:1" 'Main'
                echo "Created main repo session '$main_session_name', switching..."
                tmux switch-client -t "$main_session_name"
            fi
        else
            if tmux has-session -t "$main_session_name" 2>/dev/null; then
                echo "Attaching to main repo session '$main_session_name'..."
                tmux attach-session -t "$main_session_name"
            else
                tmux new-session -d -s "$main_session_name" -c "$main_repo_root"
                tmux rename-window -t "$main_session_name:1" 'Main'
                echo "Created main repo session '$main_session_name', attaching..."
                tmux attach-session -t "$main_session_name"
            fi
        fi
    else
        echo "Tmux not available, staying in main repo directory..."
        exec "$SHELL"
    fi
}

usage() {
    echo "Usage: $0 <command> [args] [options]"
    echo ""
    echo "Commands:"
    echo "  create <branch>   Create new worktree for branch"
    echo "  switch <branch>   Switch to existing worktree"
    echo "  find              Fuzzy find branch and create/switch to worktree"
    echo "  remove [branch]   Remove worktree (current if no branch specified)"
    echo "  list              List existing worktrees"
    echo "  config            Show available file sets"
    echo ""
    echo "Create Options:"
    echo "  -c, --current     Base worktree on current branch instead of master"
    echo "  -f, --files SET   File set to copy (default: standard)"
    echo "  -w, --wip         Take all WIP changes (stash and apply to new worktree)"
    echo ""
    echo "Available file sets:"
    if [ -f "$CONFIG_FILE" ]; then
        grep -o '"[^"]*"[[:space:]]*:' "$CONFIG_FILE" | sed 's/"//g' | sed 's/[[:space:]]*://' | sed 's/^/  - /'
    else
        echo "  (config file not found)"
    fi
    echo ""
    echo "Examples:"
    echo "  $0 create feature-branch"
    echo "  $0 create hotfix --current --wip"
    echo "  $0 create experiment --files full"
    echo "  $0 switch feature-branch"
    echo "  $0 find"
    echo "  $0 remove"
    echo "  $0 remove feature-branch"
    echo "  $0 list"
}

# Parse command and arguments
if [ $# -eq 0 ]; then
    usage
    exit 1
fi

COMMAND="$1"
shift

# Initialize variables
BRANCH_NAME=""
BASE_ON_CURRENT=false
FILE_SET="$DEFAULT_FILE_SET"
TAKE_WIP=false
FIND_BRANCH_MODE=false
LIST_MODE=false

# Handle commands
case "$COMMAND" in
    create)
        if [ $# -eq 0 ]; then
            echo "Error: create command requires a branch name"
            usage
            exit 1
        fi
        BRANCH_NAME="$1"
        shift
        
        # Parse create options
        while [ $# -gt 0 ]; do
            case $1 in
                -c|--current)
                    BASE_ON_CURRENT=true
                    shift
                    ;;
                -f|--files)
                    FILE_SET="$2"
                    shift 2
                    ;;
                -w|--wip)
                    TAKE_WIP=true
                    shift
                    ;;
                -h|--help)
                    usage
                    exit 0
                    ;;
                -*)
                    echo "Error: Unknown option $1 for create command"
                    usage
                    exit 1
                    ;;
                *)
                    echo "Error: Unexpected argument $1"
                    usage
                    exit 1
                    ;;
            esac
        done
        ;;
    switch)
        if [ $# -eq 0 ]; then
            echo "Error: switch command requires a branch name"
            usage
            exit 1
        fi
        BRANCH_NAME="$1"
        shift
        
        if [ $# -gt 0 ]; then
            echo "Error: switch command does not accept options"
            usage
            exit 1
        fi
        ;;
    find)
        if [ $# -gt 0 ]; then
            # Parse find options
            while [ $# -gt 0 ]; do
                case $1 in
                    -f|--files)
                        FILE_SET="$2"
                        shift 2
                        ;;
                    -c|--current)
                        BASE_ON_CURRENT=true
                        shift
                        ;;
                    -w|--wip)
                        TAKE_WIP=true
                        shift
                        ;;
                    -h|--help)
                        usage
                        exit 0
                        ;;
                    -*)
                        echo "Error: Unknown option $1 for find command"
                        usage
                        exit 1
                        ;;
                    *)
                        echo "Error: Unexpected argument $1"
                        usage
                        exit 1
                        ;;
                esac
            done
        fi
        
        # Find branch will be handled later in the script
        FIND_BRANCH_MODE=true
        ;;
    remove)
        if [ $# -gt 0 ]; then
            BRANCH_NAME="$1"
            shift
            if [ $# -gt 0 ]; then
                echo "Error: remove command accepts only one branch name"
                usage
                exit 1
            fi
        fi
        ;;
    list)
        if [ $# -gt 0 ]; then
            echo "Error: list command does not accept arguments"
            usage
            exit 1
        fi
        # List will be handled later in the script
        LIST_MODE=true
        ;;
    config)
        if [ $# -gt 0 ]; then
            echo "Error: config command does not accept arguments"
            usage
            exit 1
        fi
        if [ -f "$CONFIG_FILE" ]; then
            echo "Available file sets:"
            grep -o '"[^"]*"[[:space:]]*:' "$CONFIG_FILE" | sed 's/"//g' | sed 's/[[:space:]]*://' | sed 's/^/  - /'
        else
            echo "Config file $CONFIG_FILE not found"
        fi
        exit 0
        ;;
    -h|--help|help)
        usage
        exit 0
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'"
        usage
        exit 1
        ;;
esac

handle_remove_current() {
    CURRENT_DIR=$(pwd)
    MAIN_REPO_ROOT=$(get_main_repo_root)
    
    if [ -z "$MAIN_REPO_ROOT" ]; then
        echo "Error: Not in a git repository"
        exit 1
    fi
    
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "Error: Not in a git worktree"
        exit 1
    fi
    
    WORKTREE_ROOT=$(git rev-parse --show-toplevel)
    REPO_NAME=$(basename "$MAIN_REPO_ROOT")
    
    # Check if we're in a worktree (not the main repo)
    if [ "$CURRENT_DIR" = "$MAIN_REPO_ROOT" ] || ! echo "$CURRENT_DIR" | grep -q "$REPO_NAME-worktrees"; then
        echo "Error: Not currently in a worktree directory"
        echo "Current directory: $CURRENT_DIR"
        echo "Main repo: $MAIN_REPO_ROOT"
        exit 1
    fi
    
    CURRENT_BRANCH=$(git branch --show-current)
    WORKTREE_NAME=$(basename "$WORKTREE_ROOT")
    
    echo "Removing worktree: $WORKTREE_ROOT"
    echo "Branch: $CURRENT_BRANCH"
    
    if confirm "Are you sure you want to remove this worktree and delete the branch?"; then
        kill_tmux_session "$WORKTREE_NAME"
        
        if remove_worktree_and_branch "$WORKTREE_ROOT" "$CURRENT_BRANCH"; then
            switch_to_main_session "$MAIN_REPO_ROOT"
        else
            exit 1
        fi
    else
        echo "Aborted."
        exit 0
    fi
}



handle_find_branch() {
    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: fzf is required for fuzzy finding. Install with: brew install fzf"
        exit 1
    fi
    
    echo "Fetching latest branches..."
    git fetch --all --quiet 2>/dev/null || true
    
    # Get all branches (local and remote) and format them
    BRANCHES=$(git branch -a --format='%(refname:short)' | \
        grep -v '^HEAD' | \
        sed 's|^origin/||' | \
        sort -u | \
        grep -v '^$')
    
    if [ -z "$BRANCHES" ]; then
        echo "No branches found"
        exit 1
    fi
    
    # Use fzf to select branch
    SELECTED_BRANCH=$(echo "$BRANCHES" | fzf \
        --height=40% \
        --border \
        --prompt="Select branch: " \
        --preview="git log --oneline --max-count=10 {} 2>/dev/null || echo 'No commits found'" \
        --preview-window=right:50%)
    
    if [ -z "$SELECTED_BRANCH" ]; then
        echo "No branch selected"
        exit 0
    fi
    
    echo "Selected branch: $SELECTED_BRANCH"
    echo "$SELECTED_BRANCH"
}

handle_list_worktrees() {
    MAIN_REPO_ROOT=$(get_main_repo_root)
    WORKTREES=$(get_worktree_list "$MAIN_REPO_ROOT")
    
    if [ -z "$WORKTREES" ]; then
        echo "No worktrees found"
        return
    fi
    
    echo "Existing worktrees:"
    echo "$WORKTREES" | while IFS='|' read -r path branch; do
        worktree_name=$(basename "$path")
        printf "  %-30s %s\n" "$worktree_name" "($branch)"
    done
}

get_worktree_list() {
    main_repo_root="$1"
    git worktree list --porcelain | awk '
        /^worktree / { path = substr($0, 10) }
        /^branch / { 
            branch = substr($0, 8)
            if (path != "'"$main_repo_root"'") {
                print path "|" branch
            }
        }
        /^detached$/ {
            if (path != "'"$main_repo_root"'") {
                print path "|" "(detached)"
            }
        }
    '
}

handle_find_branch() {
    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: fzf is required for fuzzy finding. Install with: brew install fzf"
        exit 1
    fi
    
    echo "Fetching latest branches..."
    git fetch --all --quiet 2>/dev/null || true
    
    # Get all branches (local and remote) and format them
    BRANCHES=$(git branch -a --format='%(refname:short)' | \
        grep -v '^HEAD' | \
        sed 's|^origin/||' | \
        sort -u | \
        grep -v '^$')
    
    if [ -z "$BRANCHES" ]; then
        echo "No branches found"
        exit 1
    fi
    
    # Use fzf to select branch
    SELECTED_BRANCH=$(echo "$BRANCHES" | fzf \
        --height=40% \
        --border \
        --prompt="Select branch: " \
        --preview="git log --oneline --max-count=10 {} 2>/dev/null || echo 'No commits found'" \
        --preview-window=right:50%)
    
    if [ -z "$SELECTED_BRANCH" ]; then
        echo "No branch selected"
        exit 0
    fi
    
    echo "Selected branch: $SELECTED_BRANCH"
    echo "$SELECTED_BRANCH"
}

handle_list_worktrees() {
    MAIN_REPO_ROOT=$(get_main_repo_root)
    WORKTREES=$(get_worktree_list "$MAIN_REPO_ROOT")
    
    if [ -z "$WORKTREES" ]; then
        echo "No worktrees found"
        return
    fi
    
    echo "Existing worktrees:"
    echo "$WORKTREES" | while IFS='|' read -r path branch; do
        worktree_name=$(basename "$path")
        printf "  %-30s %s\n" "$worktree_name" "($branch)"
    done
}

# Handle list mode
if [ "$LIST_MODE" = true ]; then
    handle_list_worktrees
    exit 0
fi

# Handle find mode
if [ "$FIND_BRANCH_MODE" = true ]; then
    BRANCH_NAME=$(handle_find_branch)
    if [ -z "$BRANCH_NAME" ]; then
        exit 0
    fi
fi

handle_list_worktrees() {
    MAIN_REPO_ROOT=$(get_main_repo_root)
    WORKTREES=$(get_worktree_list "$MAIN_REPO_ROOT")
    
    if [ -z "$WORKTREES" ]; then
        echo "No worktrees found"
        return
    fi
    
    echo "Existing worktrees:"
    echo "$WORKTREES" | while IFS='|' read -r path branch; do
        worktree_name=$(basename "$path")
        printf "  %-30s %s\n" "$worktree_name" "($branch)"
    done
}

handle_remove_by_name() {
    branch_name="$1"
    
    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: fzf is required for branch-based removal. Install with: brew install fzf"
        exit 1
    fi
    
    MAIN_REPO_ROOT=$(get_main_repo_root)
    WORKTREES=$(get_worktree_list "$MAIN_REPO_ROOT")
    
    if [ -z "$WORKTREES" ]; then
        echo "No worktrees found"
        exit 0
    fi
    
    # Find matching worktree
    MATCHING_WORKTREE=$(echo "$WORKTREES" | grep "|$branch_name$" | head -1)
    
    if [ -z "$MATCHING_WORKTREE" ]; then
        echo "No worktree found for branch '$branch_name'"
        echo "Available worktrees:"
        handle_list_worktrees
        exit 1
    fi
    
    WORKTREE_PATH=$(echo "$MATCHING_WORKTREE" | cut -d'|' -f1)
    WORKTREE_NAME=$(basename "$WORKTREE_PATH")
    
    echo "Found worktree: $WORKTREE_PATH"
    echo "Branch: $branch_name"
    
    if confirm "Are you sure you want to remove this worktree?"; then
        kill_tmux_session "$WORKTREE_NAME"
        
        if remove_worktree_and_branch "$WORKTREE_PATH" "$branch_name"; then
            echo "Worktree '$WORKTREE_NAME' removed successfully"
        else
            exit 1
        fi
    else
        echo "Aborted."
        exit 0
    fi
}

handle_find_remove() {
    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: fzf is required for fuzzy finding. Install with: brew install fzf"
        exit 1
    fi
    
    MAIN_REPO_ROOT=$(get_main_repo_root)
    WORKTREES=$(get_worktree_list "$MAIN_REPO_ROOT")
    
    if [ -z "$WORKTREES" ]; then
        echo "No worktrees found to remove"
        exit 0
    fi
    
    # Format for fzf display
    FORMATTED_WORKTREES=$(echo "$WORKTREES" | while IFS='|' read -r path branch; do
        worktree_name=$(basename "$path")
        echo "$worktree_name ($branch) - $path"
    done)
    
    # Use fzf to select worktree
    SELECTED=$(echo "$FORMATTED_WORKTREES" | fzf \
        --height=40% \
        --border \
        --prompt="Select worktree to remove: " \
        --preview="echo 'Path: {}' && echo '' && git -C \$(echo '{}' | sed 's/.* - //') log --oneline --max-count=5 2>/dev/null || echo 'No commits found'" \
        --preview-window=right:50%)
    
    if [ -z "$SELECTED" ]; then
        echo "No worktree selected"
        exit 0
    fi
    
    # Extract info from selection
    SELECTED_PATH=$(echo "$SELECTED" | sed 's/.* - //')
    SELECTED_BRANCH=$(echo "$SELECTED" | sed 's/.*(\([^)]*\)).*/\1/')
    WORKTREE_NAME=$(basename "$SELECTED_PATH")
    
    echo "Selected worktree: $SELECTED_PATH"
    echo "Branch: $SELECTED_BRANCH"
    
    if confirm "Are you sure you want to remove this worktree?"; then
        kill_tmux_session "$WORKTREE_NAME"
        
        if remove_worktree_and_branch "$SELECTED_PATH" "$SELECTED_BRANCH"; then
            echo "Worktree '$WORKTREE_NAME' removed successfully"
            echo "Current session remains active"
        else
            exit 1
        fi
    else
        echo "Aborted."
        exit 0
    fi
}

# Handle remove command
if [ "$COMMAND" = "remove" ]; then
    if [ -n "$BRANCH_NAME" ]; then
        handle_remove_by_name "$BRANCH_NAME"
    else
        handle_remove_current
    fi
    exit 0
fi

handle_find_branch() {
    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: fzf is required for fuzzy finding. Install with: brew install fzf"
        exit 1
    fi
    
    echo "Fetching latest branches..."
    git fetch --all --quiet 2>/dev/null || true
    
    # Get all branches (local and remote) and format them
    BRANCHES=$(git branch -a --format='%(refname:short)' | \
        grep -v '^HEAD' | \
        sed 's|^origin/||' | \
        sort -u | \
        grep -v '^$')
    
    if [ -z "$BRANCHES" ]; then
        echo "No branches found"
        exit 1
    fi
    
    # Use fzf to select branch
    SELECTED_BRANCH=$(echo "$BRANCHES" | fzf \
        --height=40% \
        --border \
        --prompt="Select branch: " \
        --preview="git log --oneline --max-count=10 {} 2>/dev/null || echo 'No commits found'" \
        --preview-window=right:50%)
    
    if [ -z "$SELECTED_BRANCH" ]; then
        echo "No branch selected"
        exit 0
    fi
    
    echo "Selected branch: $SELECTED_BRANCH"
    echo "$SELECTED_BRANCH"
}

# Handle find mode
if [ "$FIND_MODE" = true ]; then
    BRANCH_NAME=$(handle_find_branch)
    if [ -z "$BRANCH_NAME" ]; then
        exit 0
    fi
fi

# Handle switch command - check if worktree exists and switch to it
if [ "$COMMAND" = "switch" ]; then
    PATHS=$(setup_worktree_paths "$BRANCH_NAME")
    WORKTREE_PATH=$(echo "$PATHS" | cut -d'|' -f1)
    WORKTREE_NAME=$(echo "$PATHS" | cut -d'|' -f2)
    
    if [ ! -d "$WORKTREE_PATH" ]; then
        echo "Error: No worktree found for branch '$BRANCH_NAME'"
        echo "Use 'wt create $BRANCH_NAME' to create it first"
        exit 1
    fi
    
    switch_to_existing_worktree "$WORKTREE_PATH" "$WORKTREE_NAME"
    exit 0
fi

# At this point, we're handling create or find commands
# Both need a branch name
if [ -z "$BRANCH_NAME" ]; then
    echo "Error: Branch name is required"
    usage
    exit 1
fi

# Determine base branch
if [ "$BASE_ON_CURRENT" = true ]; then
    BASE_BRANCH=$(git branch --show-current)
    if [ -z "$BASE_BRANCH" ]; then
        echo "Error: Could not determine current branch"
        exit 1
    fi
    echo "Using current branch '$BASE_BRANCH' as base"
else
    # Check if master exists, fallback to main
    if git show-ref --verify --quiet refs/heads/master; then
        BASE_BRANCH="master"
    elif git show-ref --verify --quiet refs/heads/main; then
        BASE_BRANCH="main"
    else
        BASE_BRANCH="$DEFAULT_BASE_BRANCH"
        echo "Warning: Neither 'master' nor 'main' branch found, using '$BASE_BRANCH'"
    fi
    echo "Using '$BASE_BRANCH' as base branch"
fi

setup_worktree_paths() {
    branch_name="$1"
    
    MAIN_REPO_ROOT=$(get_main_repo_root)
    REPO_NAME=$(basename "$MAIN_REPO_ROOT")
    REPO_PARENT=$(dirname "$MAIN_REPO_ROOT")
    
    # Create worktree directory structure: parent/repo-worktrees/repo-branch
    WORKTREE_DIR="$REPO_PARENT/$REPO_NAME-worktrees"
    WORKTREE_NAME="$REPO_NAME-$branch_name"
    WORKTREE_PATH="$WORKTREE_DIR/$WORKTREE_NAME"
    
    mkdir -p "$WORKTREE_DIR"
    
    echo "$WORKTREE_PATH|$WORKTREE_NAME"
}

# Setup paths
PATHS=$(setup_worktree_paths "$BRANCH_NAME")
WORKTREE_PATH=$(echo "$PATHS" | cut -d'|' -f1)
WORKTREE_NAME=$(echo "$PATHS" | cut -d'|' -f2)

switch_to_existing_worktree() {
    worktree_path="$1"
    worktree_name="$2"
    
    echo "Worktree directory '$worktree_path' already exists."
    echo "Switching to existing worktree and session..."
    
    # Register directory with z and navigate
    if command -v z >/dev/null 2>&1; then
        z "$worktree_path" 2>/dev/null || cd "$worktree_path" || exit 1
    else
        cd "$worktree_path" || exit 1
    fi
    
    echo "Creating/switching to tmux session '$worktree_name'..."
    handle_tmux_session "$worktree_name" "$worktree_path"
}

# Check if branch already exists
BRANCH_EXISTS=false
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    BRANCH_EXISTS=true
    echo "Branch '$BRANCH_NAME' already exists."
    
    # Check if worktree already exists
    if [ -d "$WORKTREE_PATH" ]; then
        switch_to_existing_worktree "$WORKTREE_PATH" "$WORKTREE_NAME"
        exit 0
    else
        # Branch exists but worktree doesn't
        if ! confirm "Create worktree for existing branch '$BRANCH_NAME'?"; then
            echo "Aborted."
            exit 0
        fi
        echo "Creating worktree for existing branch '$BRANCH_NAME'..."
    fi
fi

# Check if worktree directory exists (for new branches)
if [ "$BRANCH_EXISTS" = false ] && [ -d "$WORKTREE_PATH" ]; then
    echo "Error: Worktree directory '$WORKTREE_PATH' already exists but branch '$BRANCH_NAME' doesn't exist"
    echo "Please remove the directory or choose a different branch name"
    exit 1
fi

# Handle WIP changes if requested
STASH_NAME=""
if [ "$TAKE_WIP" = true ]; then
    # Check if there are any changes to stash
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Stashing WIP changes..."
        STASH_NAME="wip-for-$BRANCH_NAME-$(date +%s)"
        if ! git stash push -m "$STASH_NAME"; then
            echo "Error: Failed to stash changes"
            exit 1
        fi
        echo "Changes stashed as: $STASH_NAME"
    else
        echo "No WIP changes to stash"
        TAKE_WIP=false
    fi
fi

# Create the worktree
if [ "$BRANCH_EXISTS" = true ]; then
    echo "Creating worktree for existing branch '$BRANCH_NAME'..."
    if ! git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"; then
        echo "Error: Failed to create worktree for existing branch"
        # If we stashed changes, restore them
        if [ -n "$STASH_NAME" ]; then
            echo "Restoring stashed changes..."
            git stash pop
        fi
        exit 1
    fi
else
    echo "Creating new worktree '$BRANCH_NAME' based on '$BASE_BRANCH'..."
    if ! git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE_BRANCH"; then
        echo "Error: Failed to create worktree"
        # If we stashed changes, restore them
        if [ -n "$STASH_NAME" ]; then
            echo "Restoring stashed changes..."
            git stash pop
        fi
        exit 1
    fi
fi

echo "Worktree created at: $WORKTREE_PATH"

# Get files from config
get_files_from_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Config file $CONFIG_FILE not found"
        exit 1
    fi
    
    # Extract files for the specified set using a simple JSON parser
    # This looks for the pattern: "set_name": [ "file1", "file2", ... ]
    awk -v set="$1" '
    BEGIN { in_set = 0; files = "" }
    $0 ~ "\"" set "\"[[:space:]]*:" { in_set = 1; next }
    in_set && /\]/ { in_set = 0; next }
    in_set && /\"[^\"]+\"/ {
        gsub(/[[:space:]]*\"/, "", $0)
        gsub(/\"[[:space:]]*,?/, "", $0)
        if ($0 != "") files = files $0 " "
    }
    END { print files }
    ' "$CONFIG_FILE"
}

# Validate file set exists
if [ -f "$CONFIG_FILE" ]; then
    if ! grep -q "\"$FILE_SET\"[[:space:]]*:" "$CONFIG_FILE"; then
        echo "Error: File set '$FILE_SET' not found in $CONFIG_FILE"
        echo "Available sets:"
        grep -o '"[^"]*"[[:space:]]*:' "$CONFIG_FILE" | sed 's/"//g' | sed 's/[[:space:]]*://' | sed 's/^/  - /'
        exit 1
    fi
else
    echo "Error: Config file $CONFIG_FILE not found"
    exit 1
fi

# Copy files from config
echo "Copying files from '$FILE_SET' set to new worktree..."
FILES_TO_COPY=$(get_files_from_config "$FILE_SET")

for file in $FILES_TO_COPY; do
    # Skip empty entries
    [ -z "$file" ] && continue
    
    if [ -f "$file" ]; then
        echo "  Copying $file"
        cp "$file" "$WORKTREE_PATH/"
    elif [ -d "$file" ]; then
        echo "  Copying directory $file"
        cp -r "$file" "$WORKTREE_PATH/"
    else
        echo "  Warning: $file not found, skipping"
    fi
done

# Change to the new worktree and commit the copied files
cd "$WORKTREE_PATH" || exit 1

# Apply stashed changes if we have them
if [ "$TAKE_WIP" = true ] && [ -n "$STASH_NAME" ]; then
    echo "Applying WIP changes to new worktree..."
    # Go back to original directory to access the stash
    cd - > /dev/null || exit 1
    
    # Apply the stash to the new worktree
    if git -C "$WORKTREE_PATH" stash pop "stash@{0}"; then
        echo "WIP changes applied successfully"
    else
        echo "Warning: Failed to apply WIP changes, they remain in stash"
        echo "You can manually apply them later with: git -C $WORKTREE_PATH stash pop"
    fi
    
    # Return to worktree directory
    cd "$WORKTREE_PATH" || exit 1
fi

# Only copy files and commit for new branches
if [ "$BRANCH_EXISTS" = false ]; then
    # Check if there are any changes to commit (from copied files)
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Committing changes..."
        git add .
        if [ "$TAKE_WIP" = true ]; then
            git commit -m "Initial commit: Copy base files from $BASE_BRANCH and apply WIP changes"
        else
            git commit -m "Initial commit: Copy base files from $BASE_BRANCH"
        fi
    else
        echo "No changes to commit"
    fi
fi

echo ""
echo "Worktree setup complete!"
echo "Path: $WORKTREE_PATH"
echo "Branch: $BRANCH_NAME"
echo "Base: $BASE_BRANCH"
echo "File set: $FILE_SET"
if [ "$TAKE_WIP" = true ]; then
    echo "WIP changes: Applied"
fi
echo ""

# Create and switch to tmux session
SESSION_NAME="$WORKTREE_NAME"
echo "Creating tmux session '$SESSION_NAME'..."

# Register directory with z and navigate
if command -v z >/dev/null 2>&1; then
    echo "Registering directory with z..."
    z "$WORKTREE_PATH" 2>/dev/null || cd "$WORKTREE_PATH" || exit 1
else
    cd "$WORKTREE_PATH" || exit 1
fi

# Create and switch to tmux session
echo "Creating tmux session '$SESSION_NAME'..."
handle_tmux_session "$SESSION_NAME" "$WORKTREE_PATH"

echo ""
echo "To remove the worktree later:"
echo "  git worktree remove $WORKTREE_PATH"
echo "  git branch -d $BRANCH_NAME"
