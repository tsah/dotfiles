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

# ---- input sources ----
# Only U.S. and Hebrew - PC, so Ctrl+Space toggles between exactly those two.
# Hebrew - PC matches Windows/Linux: Shift+letter types an English capital.
# Apple's plain Hebrew layout puts Hebrew symbols on Shift instead.
swift - <<'SWIFT'
import Carbon
func sources(_ id: String) -> [TISInputSource] {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    return TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
}
for source in sources("com.apple.keylayout.Hebrew-PC") { TISEnableInputSource(source) }
for id in ["com.apple.keylayout.ABC", "com.apple.keylayout.Hebrew"] {
    for source in sources(id) { TISDisableInputSource(source) }
}
SWIFT

# ---- scrolling ----
# Natural scrolling, which macOS applies to trackpad and mouse alike.
# LinearMouse reverses the mouse wheel back (see linearmouse/linearmouse.json).
defaults write -g com.apple.swipescrolldirection -bool true

# ---- screen saver and power (pmset needs root) ----
# The screen saver delay is one setting for battery and charger alike: 1 hour.
# On battery the display turns off at 10 minutes, so the screen saver never shows.
# On the charger the display stays on for 70 minutes, so the screen saver runs for 10 minutes before the display turns off.
defaults -currentHost write com.apple.screensaver idleTime -int 3600
sudo pmset -b displaysleep 10
sudo pmset -c displaysleep 70

echo "Applied macOS defaults."
