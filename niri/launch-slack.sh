#!/bin/bash

# Get Slack window ID by parsing niri msg windows output
slack_id=$(niri msg windows | grep -B5 -A5 "chrome-app.slack.com" | grep "Window ID" | head -1 | cut -d' ' -f3 | tr -d ':')

if [ -n "$slack_id" ]; then
    # Focus existing Slack window
    niri msg action focus-window --id "$slack_id"
else
    # Launch new Slack instance
    chromium --app="https://app.slack.com/client/T086WDUM9LM/C087BVCGJ49" &
fi