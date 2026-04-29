---
description: Spawn a tworker
---

Spawn a separate **OpenCode** worker with `spawn-opencode-agent`.

Do **not** use `spawn-pi-tworker` or `spawn-claude-tworker` unless the user explicitly asks for pi or Claude Code.

Arguments: `$ARGUMENTS`

Interpret arguments in this order:
1. `--agent <agent-name> <branch-name> <initial-prompt>`
2. `<branch-name> <initial-prompt>`
3. `<initial-prompt>` (derive a short kebab-case branch name)

If the user does not provide `--agent`, choose one of: `plan`, `build`, `fast`.
- `plan`: planning, architecture, or exploratory analysis
- `build`: implementation and code changes (default)
- `fast`: quick iterations, lightweight edits, or triage

Default to one worker unless the user explicitly asks for multiple workers.

After spawning, report:
- tmux session name
- tmux window name
- switch hint
