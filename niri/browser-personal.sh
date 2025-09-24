#!/bin/bash
# Launch or focus personal browser profile

USER_DATA_DIR="$HOME/.config/chromium-personal"

# Get personal browser window ID by parsing niri msg windows output
browser_id=$(niri msg windows | grep -B5 -A5 "chromium-personal" | grep "Window ID" | head -1 | cut -d' ' -f3 | tr -d ':')

if [ -n "$browser_id" ]; then
    # Focus existing window
    niri msg action focus-window --id "$browser_id"
else
    # Launch new personal browser instance
    chromium --user-data-dir="${USER_DATA_DIR}" --class="chromium-personal" &
fi