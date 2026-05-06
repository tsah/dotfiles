---
name: tw
description: Alias for /tworker
---

Spawn a separate **Claude Code** worker with `spawn-claude-tworker`.

Do **not** use `spawn-opencode-agent` or `spawn-pi-tworker` unless the user explicitly asks for OpenCode or pi.

Arguments: `$ARGUMENTS`

Interpret arguments in this order:
1. `--agent <agent-name> <branch-name> <initial-prompt>`
2. `<branch-name> <initial-prompt>`
3. `<initial-prompt>` (derive a short kebab-case branch name)

Default to one worker unless the user explicitly asks for multiple workers.

Tworkers should start in build mode, not plan mode. If planning, analysis, architecture exploration, or a written plan is needed, include that in the initial prompt and ask the worker to write its plan or findings to a document when useful.

After spawning, report:
- tmux session name
- tmux window name
- switch hint
