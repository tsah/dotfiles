#!/bin/bash
# Get current keyboard layout from niri
active_index=$(niri msg keyboard-layouts | awk '/^\s*\*/ {print $2}')
if [ "$active_index" = "0" ]; then
    echo "us"
elif [ "$active_index" = "1" ]; then
    echo "il"
else
    echo "unknown"
fi