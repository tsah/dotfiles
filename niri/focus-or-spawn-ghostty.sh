#!/bin/bash

# Try to focus existing main-terminal window by title
TERMINAL_ID=$(niri msg windows | grep -B 5 'Title: "main-terminal"' | grep "Window ID" | head -1 | awk '{print $3}' | tr -d ':')

if [ -n "$TERMINAL_ID" ]; then
    niri msg action focus-window --id="$TERMINAL_ID"
else
    # Spawn new main terminal in background with nohup to prevent blocking
    nohup ghostty --title=main-terminal </dev/null >/dev/null 2>&1 &
    disown
fi