#!/bin/bash

# Enhanced tmux popup script with support for:
# - Persistent or temporary sessions
# - Custom commands
# - Different session types
# - Switching between popup types without nesting
#
# Popup session naming format: OUTER__TYPE__PERSISTENCE__popup
# This groups popups by outer session when listing sessions
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

# Check if we are inside ANY popup session
if echo "${CURRENT_SESSION_NAME}" | grep -q "__popup$"; then
    # --- INSIDE A POPUP ---
    # Extract the type and outer session from the current popup session name
    # Format is: OUTER__TYPE__PERSISTENCE__popup
    OUTER_SESSION_ID=$(echo "${CURRENT_SESSION_NAME}" | cut -d'_' -f1)
    POPUP_TYPE=$(echo "${CURRENT_SESSION_NAME}" | sed -E 's/^[^_]+__([^_]+)__(persistent|temp)__popup$/\1/')
    
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
        TARGET_POPUP_SESSION="${OUTER_SESSION_ID}__${SESSION_TYPE}__${PERSISTENCE_LABEL}__popup"
        
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
            # Now switch to it
            tmux switch-client -t "${TARGET_POPUP_SESSION}"
        fi
    fi

else
    # --- OUTSIDE POPUP ---
    # We are in a normal session. The action is to display the popup.

    # First, capture the session ID of the *outer* session reliably.
    OUTER_SESSION_ID=$(tmux display-message -p '#{session_name}')

    # Handle edge case where ID might still be empty (very unlikely, but safe)
    if [[ -z "${OUTER_SESSION_ID}" ]]; then
      echo "Error: Could not determine outer session ID." >&2
      OUTER_SESSION_ID="fallback_id"
    fi

    # Construct the unique popup session name using the captured ID.
    # Format: OUTER__TYPE__PERSISTENCE__popup
    PERSISTENCE_LABEL="persistent"
    if [[ "$PERSISTENT" != "true" ]]; then
        PERSISTENCE_LABEL="temp"
    fi
    POPUP_SESSION_NAME="${OUTER_SESSION_ID}__${SESSION_TYPE}__${PERSISTENCE_LABEL}__popup"

    # Get current working directory
    CURRENT_PATH=$(tmux display-message -p '#{pane_current_path}')

    # Build the tmux command
    if [[ "$PERSISTENT" == "true" ]]; then
        # Persistent session - use -A flag to attach or create
        if [[ -n "$COMMAND" ]]; then
            # For persistent sessions with command, use a different approach
            # Create session with the command directly, or attach if exists
            TMUX_CMD="tmux new-session -A -s ${POPUP_SESSION_NAME} ${COMMAND}"
        else
            # For persistent sessions without command, just create session
            TMUX_CMD="tmux new-session -A -s ${POPUP_SESSION_NAME}"
        fi
    else
        # Temporary session - don't use -A flag, session dies when command exits
        if [[ -n "$COMMAND" ]]; then
            TMUX_CMD="tmux new-session -s ${POPUP_SESSION_NAME} ${COMMAND}"
        else
            TMUX_CMD="tmux new-session -s ${POPUP_SESSION_NAME}"
        fi
    fi

    # Construct and execute the display-popup command.
    tmux display-popup -d "${CURRENT_PATH}" -w 95% -h 95% -E "${TMUX_CMD}"
fi

exit 0
