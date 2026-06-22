#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Browser Work
# @raycast.mode silent
# @raycast.packageName Browser

set -euo pipefail

BROWSER_APP="${BROWSER_APP:-Google Chrome}"
PROFILE_DIRECTORY="${BROWSER_WORK_PROFILE:-Profile 1}"

open -na "$BROWSER_APP" --args --profile-directory="$PROFILE_DIRECTORY"
