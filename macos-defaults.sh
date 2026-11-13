#!/bin/sh
# macOS system settings, applied idempotently. Re-run after changing a value.
# Settings in System Settings that have no command-line equivalent are not here.
set -eu

[ "$(uname -s)" = Darwin ] || { echo "macos-defaults.sh: macOS only" >&2; exit 1; }

# ---- power (pmset needs root) ----
# Turn the display off after 10 minutes, on battery and on the charger.
sudo pmset -b displaysleep 10
sudo pmset -c displaysleep 10

echo "Applied macOS defaults."
