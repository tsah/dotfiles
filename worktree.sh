#!/bin/sh
# Git worktree management script with file copying

# Default configuration
DEFAULT_BASE_BRANCH="master"
CONFIG_FILE="$HOME/.wt_files"
DEFAULT_FILE_SET="standard"

usage() {
    echo "Usage: $0 <branch-name> [options]"
    echo "       $0 --remove"
    echo "       $0 --find"
    echo "       $0 --find-remove"
    echo ""
    echo "Options:"
    echo "  -c, --current     Base worktree on current branch instead of master"
    echo "  -f, --files SET   File set to copy (default: standard)"
    echo "  -w, --wip         Take all WIP changes (stash and apply to new worktree)"
    echo "  -r, --remove      Remove current worktree and switch to main repo"
    echo "      --find        Fuzzy find and select existing branch"
    echo "      --find-remove Fuzzy find and remove existing worktree"
    echo "  -h, --help        Show this help message"
    echo "  --list-sets       List available file sets"
    echo ""
    echo "Available file sets:"
    if [ -f "$CONFIG_FILE" ]; then
        # Extract keys from JSON (simple approach)
        grep -o '"[^"]*"[[:space:]]*:' "$CONFIG_FILE" | sed 's/"//g' | sed 's/[[:space:]]*://' | sed 's/^/  - /'
    else
        echo "  (config file not found)"
    fi
    echo ""
    echo "Examples:"
    echo "  $0 feature-branch"
    echo "  $0 hotfix --current"
    echo "  $0 experiment -f full"
    echo "  $0 bugfix --wip"
    echo "  $0 --find         # Fuzzy find existing branch"
    echo "  $0 --remove       # Remove current worktree"
    echo "  $0 --find-remove  # Fuzzy find and remove worktree"
}

# Parse command line arguments
BRANCH_NAME=""
BASE_ON_CURRENT=false
FILE_SET="$DEFAULT_FILE_SET"
TAKE_WIP=false
REMOVE_MODE=false
FIND_MODE=false
FIND_REMOVE_MODE=false

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
        -r|--remove)
            REMOVE_MODE=true
            shift
            ;;
        --find)
            FIND_MODE=true
            shift
            ;;
        --find-remove)
            FIND_REMOVE_MODE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --list-sets)
            if [ -f "$CONFIG_FILE" ]; then
                echo "Available file sets:"
                grep -o '"[^"]*"[[:space:]]*:' "$CONFIG_FILE" | sed 's/"//g' | sed 's/[[:space:]]*://' | sed 's/^/  - /'
            else
                echo "Config file $CONFIG_FILE not found"
            fi
            exit 0
            ;;
        -*)
            echo "Error: Unknown option $1"
            usage
            exit 1
            ;;
        *)
            if [ -z "$BRANCH_NAME" ]; then
                BRANCH_NAME="$1"
            else
                echo "Error: Multiple branch names provided"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Handle remove mode
if [ "$REMOVE_MODE" = true ]; then
    # Check if we're in a worktree
    CURRENT_DIR=$(pwd)
    MAIN_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
    
    if [ -z "$MAIN_REPO_ROOT" ]; then
        echo "Error: Not in a git repository"
        exit 1
    fi
    
    # Check if current directory is a worktree
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        WORKTREE_ROOT=$(git rev-parse --show-toplevel)
        REPO_NAME=$(basename "$MAIN_REPO_ROOT")
        
        # Check if we're in a worktree (not the main repo)
        if [ "$CURRENT_DIR" != "$MAIN_REPO_ROOT" ] && echo "$CURRENT_DIR" | grep -q "$REPO_NAME-worktrees"; then
            CURRENT_BRANCH=$(git branch --show-current)
            WORKTREE_NAME=$(basename "$WORKTREE_ROOT")
            
            echo "Removing worktree: $WORKTREE_ROOT"
            echo "Branch: $CURRENT_BRANCH"
            
            printf "Are you sure you want to remove this worktree and delete the branch? [y/N]: "
            read -r response
            case "$response" in
                [yY]|[yY][eE][sS])
                    # Kill tmux session if it exists
                    if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$WORKTREE_NAME" 2>/dev/null; then
                        echo "Killing tmux session '$WORKTREE_NAME'..."
                        tmux kill-session -t "$WORKTREE_NAME"
                    fi
                    
                    # Switch to main repo directory
                    cd "$MAIN_REPO_ROOT" || exit 1
                    
                    # Remove the worktree
                    echo "Removing worktree..."
                    if git worktree remove "$WORKTREE_ROOT" --force; then
                        echo "Worktree removed successfully"
                        
                        # Ask about deleting the branch
                        printf "Delete branch '$CURRENT_BRANCH'? [y/N]: "
                        read -r branch_response
                        case "$branch_response" in
                            [yY]|[yY][eE][sS])
                                if git branch -D "$CURRENT_BRANCH"; then
                                    echo "Branch '$CURRENT_BRANCH' deleted"
                                else
                                    echo "Failed to delete branch '$CURRENT_BRANCH'"
                                fi
                                ;;
                            *)
                                echo "Branch '$CURRENT_BRANCH' kept"
                                ;;
                        esac
                    else
                        echo "Failed to remove worktree"
                        exit 1
                    fi
                    
                    # Create or switch to main repo tmux session
                    MAIN_SESSION_NAME="$REPO_NAME-main"
                    if command -v tmux >/dev/null 2>&1; then
                        if [ -n "$TMUX" ]; then
                            if tmux has-session -t "$MAIN_SESSION_NAME" 2>/dev/null; then
                                echo "Switching to main repo session '$MAIN_SESSION_NAME'..."
                                tmux switch-client -t "$MAIN_SESSION_NAME"
                            else
                                tmux new-session -d -s "$MAIN_SESSION_NAME" -c "$MAIN_REPO_ROOT"
                                tmux rename-window -t "$MAIN_SESSION_NAME:1" 'Main'
                                echo "Created main repo session '$MAIN_SESSION_NAME', switching..."
                                tmux switch-client -t "$MAIN_SESSION_NAME"
                            fi
                        else
                            if tmux has-session -t "$MAIN_SESSION_NAME" 2>/dev/null; then
                                echo "Attaching to main repo session '$MAIN_SESSION_NAME'..."
                                tmux attach-session -t "$MAIN_SESSION_NAME"
                            else
                                tmux new-session -d -s "$MAIN_SESSION_NAME" -c "$MAIN_REPO_ROOT"
                                tmux rename-window -t "$MAIN_SESSION_NAME:1" 'Main'
                                echo "Created main repo session '$MAIN_SESSION_NAME', attaching..."
                                tmux attach-session -t "$MAIN_SESSION_NAME"
                            fi
                        fi
                    else
                        echo "Tmux not available, staying in main repo directory..."
                        exec "$SHELL"
                    fi
                    ;;
                *)
                    echo "Aborted."
                    exit 0
                    ;;
            esac
        else
            echo "Error: Not currently in a worktree directory"
            echo "Current directory: $CURRENT_DIR"
            echo "Main repo: $MAIN_REPO_ROOT"
            exit 1
        fi
    else
        echo "Error: Not in a git worktree"
        exit 1
    fi
    exit 0
fi

# Handle find-remove mode
if [ "$FIND_REMOVE_MODE" = true ]; then
    # Check if fzf is available
    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: fzf is required for fuzzy finding. Install with: brew install fzf"
        exit 1
    fi
    
    # Get main repo info
    MAIN_REPO_ROOT=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
    if [ -z "$MAIN_REPO_ROOT" ]; then
        MAIN_REPO_ROOT=$(git rev-parse --show-toplevel)
    fi
    
    # Get list of existing worktrees
    WORKTREES=$(git worktree list --porcelain | awk '
        /^worktree / { path = substr($0, 10) }
        /^branch / { 
            branch = substr($0, 8)
            if (path != "'"$MAIN_REPO_ROOT"'") {
                print path "|" branch
            }
        }
        /^detached$/ {
            if (path != "'"$MAIN_REPO_ROOT"'") {
                print path "|" "(detached)"
            }
        }
    ')
    
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
    
    # Extract path from selection
    SELECTED_PATH=$(echo "$SELECTED" | sed 's/.* - //')
    SELECTED_BRANCH=$(echo "$SELECTED" | sed 's/.*(\([^)]*\)).*/\1/')
    WORKTREE_NAME=$(basename "$SELECTED_PATH")
    
    echo "Selected worktree: $SELECTED_PATH"
    echo "Branch: $SELECTED_BRANCH"
    
    printf "Are you sure you want to remove this worktree? [y/N]: "
    read -r response
    case "$response" in
        [yY]|[yY][eE][sS])
            # Kill tmux session if it exists
            if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$WORKTREE_NAME" 2>/dev/null; then
                echo "Killing tmux session '$WORKTREE_NAME'..."
                tmux kill-session -t "$WORKTREE_NAME"
            fi
            
            # Remove the worktree
            echo "Removing worktree..."
            if git worktree remove "$SELECTED_PATH" --force; then
                echo "Worktree removed successfully"
                
                # Ask about deleting the branch (only if not detached)
                if [ "$SELECTED_BRANCH" != "(detached)" ]; then
                    printf "Delete branch '$SELECTED_BRANCH'? [y/N]: "
                    read -r branch_response
                    case "$branch_response" in
                        [yY]|[yY][eE][sS])
                            if git branch -D "$SELECTED_BRANCH"; then
                                echo "Branch '$SELECTED_BRANCH' deleted"
                            else
                                echo "Failed to delete branch '$SELECTED_BRANCH'"
                            fi
                            ;;
                        *)
                            echo "Branch '$SELECTED_BRANCH' kept"
                            ;;
                    esac
                fi
                
                echo "Worktree '$WORKTREE_NAME' removed successfully"
                echo "Current session remains active"
            else
                echo "Failed to remove worktree"
                exit 1
            fi
            ;;
        *)
            echo "Aborted."
            exit 0
            ;;
    esac
    exit 0
fi

# Handle find mode
if [ "$FIND_MODE" = true ]; then
    # Check if fzf is available
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
    BRANCH_NAME="$SELECTED_BRANCH"
    
    # Continue with normal worktree creation flow
fi

# Validate required arguments for create mode
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

# Get repo info for directory structure
# Get the main repository root (not worktree root)
MAIN_REPO_ROOT=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
if [ -z "$MAIN_REPO_ROOT" ]; then
    # Not in a worktree, get the regular repo root
    MAIN_REPO_ROOT=$(git rev-parse --show-toplevel)
fi

REPO_NAME=$(basename "$MAIN_REPO_ROOT")
REPO_PARENT=$(dirname "$MAIN_REPO_ROOT")

# Create worktree directory structure: parent/repo-worktrees/repo-branch
WORKTREE_DIR="$REPO_PARENT/$REPO_NAME-worktrees"
WORKTREE_NAME="$REPO_NAME-$BRANCH_NAME"

# Create worktree directory if it doesn't exist
mkdir -p "$WORKTREE_DIR"

# Full path to the new worktree
WORKTREE_PATH="$WORKTREE_DIR/$WORKTREE_NAME"

# Check if branch already exists
BRANCH_EXISTS=false
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    BRANCH_EXISTS=true
    echo "Branch '$BRANCH_NAME' already exists."
    
    # Check if worktree already exists
    if [ -d "$WORKTREE_PATH" ]; then
        echo "Worktree directory '$WORKTREE_PATH' already exists."
        echo "Switching to existing worktree and session..."
        
        # Register directory with z and navigate
        if command -v z >/dev/null 2>&1; then
            z "$WORKTREE_PATH" 2>/dev/null || cd "$WORKTREE_PATH" || exit 1
        else
            cd "$WORKTREE_PATH" || exit 1
        fi
        
        # Jump to tmux session creation/switching
        SESSION_NAME="$WORKTREE_NAME"
        echo "Creating/switching to tmux session '$SESSION_NAME'..."
        
        # Check if tmux is available and handle session
        if command -v tmux >/dev/null 2>&1; then
            if [ -n "$TMUX" ]; then
                if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
                    echo "Switching to existing tmux session '$SESSION_NAME'..."
                    tmux switch-client -t "$SESSION_NAME"
                else
                    tmux new-session -d -s "$SESSION_NAME" -c "$WORKTREE_PATH"
                    tmux rename-window -t "$SESSION_NAME:1" 'Main'
                    echo "Created new tmux session '$SESSION_NAME', switching..."
                    tmux switch-client -t "$SESSION_NAME"
                fi
            else
                if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
                    echo "Attaching to existing tmux session '$SESSION_NAME'..."
                    tmux attach-session -t "$SESSION_NAME"
                else
                    tmux new-session -d -s "$SESSION_NAME" -c "$WORKTREE_PATH"
                    tmux rename-window -t "$SESSION_NAME:1" 'Main'
                    echo "Created new tmux session '$SESSION_NAME', attaching..."
                    tmux attach-session -t "$SESSION_NAME"
                fi
            fi
        else
            echo "Tmux not available, staying in worktree directory..."
            exec "$SHELL"
        fi
        exit 0
    else
        # Branch exists but worktree doesn't
        printf "Create worktree for existing branch '$BRANCH_NAME'? [y/N]: "
        read -r response
        case "$response" in
            [yY]|[yY][eE][sS])
                echo "Creating worktree for existing branch '$BRANCH_NAME'..."
                ;;
            *)
                echo "Aborted."
                exit 0
                ;;
        esac
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

# Check if tmux is available
if command -v tmux >/dev/null 2>&1; then
    # Check if we're already in a tmux session
    if [ -n "$TMUX" ]; then
        echo "Already in tmux session, switching to new session..."
        # Check if target session already exists
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            echo "Tmux session '$SESSION_NAME' already exists, switching..."
            tmux switch-client -t "$SESSION_NAME"
        else
            # Create new session in the worktree directory
            tmux new-session -d -s "$SESSION_NAME" -c "$WORKTREE_PATH"
            tmux rename-window -t "$SESSION_NAME:1" 'Main'
            echo "Tmux session '$SESSION_NAME' created, switching..."
            tmux switch-client -t "$SESSION_NAME"
        fi
    else
        # Not in tmux, can attach normally
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            echo "Tmux session '$SESSION_NAME' already exists, attaching..."
            tmux attach-session -t "$SESSION_NAME"
        else
            # Create new session in the worktree directory
            tmux new-session -d -s "$SESSION_NAME" -c "$WORKTREE_PATH"
            tmux rename-window -t "$SESSION_NAME:1" 'Main'
            echo "Tmux session '$SESSION_NAME' created, attaching..."
            tmux attach-session -t "$SESSION_NAME"
        fi
    fi
else
    echo "Tmux not available, staying in worktree directory..."
    exec "$SHELL"
fi

echo ""
echo "To remove the worktree later:"
echo "  git worktree remove $WORKTREE_PATH"
echo "  git branch -d $BRANCH_NAME"
