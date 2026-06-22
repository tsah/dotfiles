#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Browser Personal
# @raycast.mode silent
# @raycast.packageName Browser

set -euo pipefail

BROWSER_APP="${BROWSER_APP:-Google Chrome}"
PROFILE_DIRECTORY="${BROWSER_PERSONAL_PROFILE:-Default}"

open -na "$BROWSER_APP" --args --profile-directory="$PROFILE_DIRECTORY"
