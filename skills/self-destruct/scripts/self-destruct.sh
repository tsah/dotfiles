#!/bin/bash

set -euo pipefail

for candidate in \
    "$HOME/dotfiles/bin/clanker-self-destruct" \
    "$(command -v clanker-self-destruct 2>/dev/null || true)"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
        exec "$candidate" "$@"
    fi
done

echo "Error: clanker-self-destruct not found" >&2
exit 1
