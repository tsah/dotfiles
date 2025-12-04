#!/bin/bash

if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    layout=$(hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .active_keymap')
    case "$layout" in
        *"English"*|*"US"*) echo "us" ;;
        *"Hebrew"*|*"Israeli"*) echo "il" ;;
        *) echo "${layout:0:2}" ;;
    esac
elif command -v niri >/dev/null 2>&1; then
    active_index=$(niri msg keyboard-layouts | awk '/^\s*\*/ {print $2}')
    if [ "$active_index" = "0" ]; then
        echo "us"
    elif [ "$active_index" = "1" ]; then
        echo "il"
    else
        echo "unknown"
    fi
else
    echo "n/a"
fi