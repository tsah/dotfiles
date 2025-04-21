#!/bin/bash

# This script toggles a tmux popup window with a persistent session,
# ensuring unique sessions based on the outer session's ID.
# It works around issues where format strings don't expand correctly
# within the display-popup -E command string.

# Get the session name of the pane where the key binding was pressed.
# Use TMUX_PANE which tmux sets for run-shell.
CURRENT_SESSION_NAME=$(tmux display-message -p -t "${TMUX_PANE}" '#{session_name}')

# Check if the current session name indicates we are already inside a popup session.
if echo "${CURRENT_SESSION_NAME}" | grep -q '^popup_shell_'; then
    # --- INSIDE POPUP ---
    # We are inside the popup. The action is to detach the client, which
    # will cause the 'tmux new-session -A ...' command running via '-E'
    # to terminate, closing the popup window. The inner session persists.
    tmux detach-client

else
    # --- OUTSIDE POPUP ---
    # We are in a normal session. The action is to display the popup.
    # First, capture the session ID of the *outer* session reliably.
    OUTER_SESSION_ID=$(tmux display-message -p '#{session_name}')

    # Handle edge case where ID might still be empty (very unlikely, but safe)
    if [[ -z "${OUTER_SESSION_ID}" ]]; then
      echo "Error: Could not determine outer session ID." >&2
      # Use a fallback name or exit? Using fallback for now.
      OUTER_SESSION_ID="fallback_id"
    fi

    # Construct the unique popup session name using the captured ID.
    POPUP_SESSION_NAME="popup_shell_${OUTER_SESSION_ID}"

    # Construct and execute the display-popup command.
    # Ensure quoting inside the -E argument is correct for the shell running it.
    tmux display-popup -w 90% -h 90% -E "tmux new-session -A -s \"${POPUP_SESSION_NAME}\""
    # Example with size flags:
    # tmux display-popup -w 80% -h 75% -E "tmux new-session -A -s \"${POPUP_SESSION_NAME}\""
fi

exit 0
