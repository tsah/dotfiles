#!/bin/bash

# Enhanced tmux popup script with support for:
# - Persistent or temporary sessions
# - Custom commands
# - Different session types
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

# For lazygit, default to temporary unless explicitly set to persistent
if [[ "$SESSION_TYPE" == "lazygit" && "$3" == "" ]]; then
    PERSISTENT="false"
fi

# Get the session name of the pane where the key binding was pressed.
CURRENT_SESSION_NAME=$(tmux display-message -p -t "${TMUX_PANE}" '#{session_name}')

# Remove quotes from session name if present
CURRENT_SESSION_NAME=$(echo "${CURRENT_SESSION_NAME}" | tr -d '"')

# Check if the current session name indicates we are already inside a popup session.
if echo "${CURRENT_SESSION_NAME}" | grep -q "^popup_${SESSION_TYPE}_"; then
    # --- INSIDE POPUP ---
    # We are inside the popup. The action is to detach the client, which
    # will cause the popup to close.

    tmux detach-client

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
    POPUP_SESSION_NAME="popup_${SESSION_TYPE}_${OUTER_SESSION_ID}"

    # Get current working directory
    CURRENT_PATH=$(tmux display-message -p '#{pane_current_path}')

    # Build the tmux command
    if [[ "$PERSISTENT" == "true" ]]; then
        # Persistent session - use -A flag to attach or create
        if [[ -n "$COMMAND" ]]; then
            # For persistent sessions with command, use a different approach
            # Create session with the command directly, or attach if exists
            TMUX_CMD="tmux new-session -A -s \\\"${POPUP_SESSION_NAME}\\\" \\\"${COMMAND}\\\""
        else
            # For persistent sessions without command, just create session
            TMUX_CMD="tmux new-session -A -s \\\"${POPUP_SESSION_NAME}\\\""
        fi
    else
        # Temporary session - don't use -A flag, session dies when command exits
        if [[ -n "$COMMAND" ]]; then
            TMUX_CMD="tmux new-session -s \\\"${POPUP_SESSION_NAME}\\\" \\\"${COMMAND}\\\""
        else
            TMUX_CMD="tmux new-session -s \\\"${POPUP_SESSION_NAME}\\\""
        fi
    fi

    # Construct and execute the display-popup command.
    tmux display-popup -d "${CURRENT_PATH}" -w 90% -h 90% -E "${TMUX_CMD}"
fi

exit 0
