#!/bin/bash

# Try to focus existing chromium window
CHROMIUM_ID=$(niri msg windows | grep -B 5 'App ID: "chromium"' | grep "Window ID" | head -1 | awk '{print $3}' | tr -d ':')

if [ -n "$CHROMIUM_ID" ]; then
    niri msg action focus-window --id="$CHROMIUM_ID"
else
    # Spawn new chromium browser
    chromium --ozone-platform=wayland --enable-features=UseOzonePlatform &
fi