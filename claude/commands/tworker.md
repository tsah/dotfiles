---
name: tworker
description: Handoff work to a visible Claude Code tmux worktree worker
---

Handoff work to a separate visible **Claude Code** tmux worktree worker with `spawn-claude-tworker`.

A handoff is a separate visible tmux worktree worker. Do not treat normal agent/subagent requests as handoff requests.

Do **not** use `spawn-opencode-agent` or `spawn-pi-tworker` unless the user explicitly asks for OpenCode or pi.

Do **not** use `remote-tworker`, remote jobs, detached jobs, background jobs, or any headless mode unless the user explicitly asks for remote/headless execution. This command should create a tmux session/window the user can attach to.

Arguments: `$ARGUMENTS`

Interpret arguments in this order:
1. `--agent <agent-name> <branch-name> <initial-prompt>`
2. `<branch-name> <initial-prompt>`
3. `<initial-prompt>` (derive a short kebab-case branch name)

Default to one worker unless the user explicitly asks for multiple workers.

Workers should start in build mode, not plan mode. If planning, analysis, architecture exploration, or a written plan is needed, include that in the initial prompt and ask the worker to write its plan or findings to a document when useful.

After spawning, report:
- tmux session name
- tmux window name
- switch hint
