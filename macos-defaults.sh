#!/bin/sh
# macOS system settings, applied idempotently. Re-run after changing a value.
# Settings in System Settings that have no command-line equivalent are not here.
set -eu

[ "$(uname -s)" = Darwin ] || { echo "macos-defaults.sh: macOS only" >&2; exit 1; }

# ---- keyboard shortcuts ----
# Free Cmd+Space for Raycast: turn off "Show Spotlight search" (symbolic hotkey 64).
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
  '<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array><key>type</key><string>standard</string></dict></dict>'
# Ctrl+Space switches input source (English <-> Hebrew): "Select the previous input
# source" (symbolic hotkey 60), Ctrl = 262144, Space = 49.
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 60 \
  '<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>262144</integer></array><key>type</key><string>standard</string></dict></dict>'
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

# ---- power (pmset needs root) ----
# Turn the display off after 10 minutes, on battery and on the charger.
sudo pmset -b displaysleep 10
sudo pmset -c displaysleep 10

echo "Applied macOS defaults."
