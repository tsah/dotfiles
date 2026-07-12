#!/bin/bash

set -euo pipefail

for candidate in \
    "$HOME/dotfiles/bin/agent-self-destruct" \
    "$(command -v agent-self-destruct 2>/dev/null || true)"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
        exec "$candidate" "$@"
    fi
done

echo "Error: agent-self-destruct not found" >&2
exit 1
