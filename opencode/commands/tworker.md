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

If the user does not provide `--agent`, use `--agent build`.

Do not start tworkers in `plan` mode. If the worker needs planning, analysis, architecture exploration, or a written plan, keep it in `build` mode and include those instructions in the initial prompt. Ask it to write its plan or findings to a document when useful.

Only use another agent when explicitly requested:
- `fast`: quick iterations, lightweight edits, or triage
- `plan`: only when the user explicitly asks for a plan-mode worker

Default to one worker unless the user explicitly asks for multiple workers.

After spawning, report:
- tmux session name
- tmux window name
- switch hint
