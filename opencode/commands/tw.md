---
description: Alias for /tworker
---

Use the `Tworker` skill and follow its instructions exactly.

Spawn a separate opencode worker with `spawn-opencode-agent`.

Arguments: `$ARGUMENTS`

Interpret arguments in this order:
1. `--agent <agent-name> <branch-name> <initial-prompt>`
2. `<branch-name> <initial-prompt>`
3. `<initial-prompt>` (derive a short kebab-case branch name)

Default to one worker unless the user explicitly asks for multiple workers.

After spawning, report:
- tmux session name
- tmux window name
- switch hint
