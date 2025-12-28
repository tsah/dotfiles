#!/bin/bash

# Enhanced tmux popup script with support for:
# - Persistent or temporary sessions
# - Custom commands
# - Different session types
# - Switching between popup types without nesting
#
# Popup session naming format: _OUTER__TYPE__PERSISTENCE
# The leading underscore keeps popups separate from regular sessions in lists
#
# Usage:
#   tmux_popup.sh [session_type] [command] [persistent]
#
# Examples:
#   tmux_popup.sh                    # Default shell popup (persistent)
#   tmux_popup.sh lazygit lazygit    # Lazygit popup (temporary by default)
#   tmux_popup.sh shell "" true      # Persistent shell popup

# Parse arguments
SESSION_TYPE="${1:-shell}"
COMMAND="${2:-}"
PERSISTENT="${3:-true}"

# Get the session name of the pane where the key binding was pressed.
CURRENT_SESSION_NAME=$(tmux display-message -p -t "${TMUX_PANE}" '#{session_name}')

# No need to remove quotes - we don't add them anymore

# Strip branch name from wt-style sessions (format: dir@branch)
# This ensures popups use the base directory name as the outer session ID
strip_branch_name() {
    echo "$1" | sed 's/@.*//'
}

# Check if we are inside ANY popup session (starts with _ and ends with __persistent or __temp)
if echo "${CURRENT_SESSION_NAME}" | grep -qE "^_.*__(persistent|temp)$"; then
    # --- INSIDE A POPUP ---
    # Extract the type and outer session from the current popup session name
    # Format is: _OUTER__TYPE__PERSISTENCE
    # Note: OUTER may contain @ from wt-style sessions, but we preserve it here
    # Remove leading underscore and extract outer session (everything before first __)
    # Extract components by working backwards from the known suffixes
    # Format: _OUTER__TYPE__PERSISTENCE
    # PERSISTENCE is either "persistent" or "temp"
    # TYPE is a single word without underscores (e.g., "opencode", "lazygit", "shell")
    # OUTER can contain underscores (e.g., "qmk_firmware")
    PERSISTENCE=$(echo "${CURRENT_SESSION_NAME}" | sed -E 's/.*__(persistent|temp)$/\1/')
    # Remove the __PERSISTENCE suffix, then extract TYPE (last component after __)
    WITHOUT_PERSISTENCE=$(echo "${CURRENT_SESSION_NAME}" | sed -E 's/__(persistent|temp)$//')
    POPUP_TYPE=$(echo "${WITHOUT_PERSISTENCE}" | sed -E 's/.*__([^_]+)$/\1/')
    # OUTER is everything between leading _ and the __TYPE part
    OUTER_SESSION_ID=$(echo "${WITHOUT_PERSISTENCE}" | sed -E 's/^_(.*)__[^_]+$/\1/')
    # Check if this is the same type of popup
    if [[ "${POPUP_TYPE}" == "${SESSION_TYPE}" ]]; then
        # Same type - toggle off (detach to close popup)
        tmux detach-client
    else
        # Different type - switch to (or create) the other popup type
        # Construct the target popup session name
        PERSISTENCE_LABEL="persistent"
        if [[ "$PERSISTENT" != "true" ]]; then
            PERSISTENCE_LABEL="temp"
        fi
        TARGET_POPUP_SESSION="_${OUTER_SESSION_ID}__${SESSION_TYPE}__${PERSISTENCE_LABEL}"
        
        # Get current working directory
        CURRENT_PATH=$(tmux display-message -p '#{pane_current_path}')
        
        # Check if the target popup session exists
        if tmux has-session -t "${TARGET_POPUP_SESSION}" 2>/dev/null; then
            # Session exists - switch to it
            tmux switch-client -t "${TARGET_POPUP_SESSION}"
        else
            # Session doesn't exist - create it
            if [[ "$PERSISTENT" == "true" ]]; then
                if [[ -n "$COMMAND" ]]; then
                    tmux new-session -d -s "${TARGET_POPUP_SESSION}" -c "${CURRENT_PATH}" "${COMMAND}"
                else
                    tmux new-session -d -s "${TARGET_POPUP_SESSION}" -c "${CURRENT_PATH}"
                fi
            else
                if [[ -n "$COMMAND" ]]; then
                    tmux new-session -d -s "${TARGET_POPUP_SESSION}" -c "${CURRENT_PATH}" "${COMMAND}"
                else
                    tmux new-session -d -s "${TARGET_POPUP_SESSION}" -c "${CURRENT_PATH}"
                fi
            fi
            # Hide status bar in popup session
            tmux set-option -t "${TARGET_POPUP_SESSION}" status off
            # Now switch to it
            tmux switch-client -t "${TARGET_POPUP_SESSION}"
        fi
    fi

else
    # --- OUTSIDE POPUP ---
    # We are in a normal session. The action is to display the popup.

    # First, capture the session ID of the *outer* session reliably.
    OUTER_SESSION_ID=$(tmux display-message -p '#{session_name}')
    
    # Strip branch name from wt-style sessions (format: dir@branch)
    # This ensures all branches in the same worktree directory share popups
    OUTER_SESSION_ID=$(strip_branch_name "${OUTER_SESSION_ID}")

    # Handle edge case where ID might still be empty (very unlikely, but safe)
    if [[ -z "${OUTER_SESSION_ID}" ]]; then
      echo "Error: Could not determine outer session ID." >&2
      OUTER_SESSION_ID="fallback_id"
    fi

    # Construct the unique popup session name using the captured ID.
    # Format: _OUTER__TYPE__PERSISTENCE
    PERSISTENCE_LABEL="persistent"
    if [[ "$PERSISTENT" != "true" ]]; then
        PERSISTENCE_LABEL="temp"
    fi
    POPUP_SESSION_NAME="_${OUTER_SESSION_ID}__${SESSION_TYPE}__${PERSISTENCE_LABEL}"

    # Get current working directory
    CURRENT_PATH=$(tmux display-message -p '#{pane_current_path}')

    # Build the tmux command
    if [[ "$PERSISTENT" == "true" ]]; then
        # Persistent session - use -A flag to attach or create
        if [[ -n "$COMMAND" ]]; then
            # For persistent sessions with command, use a different approach
            # Create session with the command directly, or attach if exists
            TMUX_CMD="tmux new-session -A -s ${POPUP_SESSION_NAME} ${COMMAND} \\; set-option -t ${POPUP_SESSION_NAME} status off"
        else
            # For persistent sessions without command, just create session
            TMUX_CMD="tmux new-session -A -s ${POPUP_SESSION_NAME} \\; set-option -t ${POPUP_SESSION_NAME} status off"
        fi
    else
        # Temporary session - don't use -A flag, session dies when command exits
        if [[ -n "$COMMAND" ]]; then
            TMUX_CMD="tmux new-session -s ${POPUP_SESSION_NAME} ${COMMAND} \\; set-option -t ${POPUP_SESSION_NAME} status off"
        else
            TMUX_CMD="tmux new-session -s ${POPUP_SESSION_NAME} \\; set-option -t ${POPUP_SESSION_NAME} status off"
        fi
    fi

    # Construct and execute the display-popup command.
    tmux display-popup -d "${CURRENT_PATH}" -w 95% -h 95% -E "${TMUX_CMD}"
fi

exit 0
