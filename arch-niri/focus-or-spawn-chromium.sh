#!/bin/bash

# Try to focus existing chromium window (but not Slack PWA or other chrome-apps)
CHROMIUM_ID=$(niri msg --json windows | jq -r '.[] | select(.app_id == "chromium") | .id' | head -1)

if [ -n "$CHROMIUM_ID" ]; then
    niri msg action focus-window --id "$CHROMIUM_ID"
else
    chromium &
    disown
fi
