---
description: Spawn a tworker
---

Spawn a separate **OpenCode** worker with `spawn-opencode-agent`.

Do **not** use `spawn-pi-tworker` or `spawn-claude-tworker` unless the user explicitly asks for pi or Claude Code.

Arguments: `$ARGUMENTS`

Interpret arguments in this order:
1. `--agent <agent-name> --base <ref> --copy <path> <branch-name> <initial-prompt>`
2. `--agent <agent-name> <branch-name> <initial-prompt>`
3. `<branch-name> <initial-prompt>`
4. `<initial-prompt>` (derive a short kebab-case branch name)

Pass through these options when requested:
- `--base <ref>`: base the new worktree branch on this ref. If omitted, `spawn-opencode-agent` defaults to `origin/master` after fetching.
- `--copy <path>`: copy a file or directory from the current worktree into the spawned worktree at the same relative path. Repeat it for multiple files, such as plan files.

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
