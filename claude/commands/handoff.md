---
name: handoff
description: Handoff work to a visible Claude Code tmux worktree worker
---

Handoff work to a separate visible **Claude Code** tmux worktree worker with `spawn-claude-tworker`.

Claude Code must run without `ANTHROPIC_API_KEY` in its environment so the subscription is used instead of direct API access. Prefer `env -u ANTHROPIC_API_KEY spawn-claude-tworker ...`; the launcher also unsets it before executing `claude`.

A handoff is a separate visible tmux worktree worker for independent, isolated implementation, research, or orchestration. The new worktree + tmux session is intentional: it keeps the worker's edits and experiments separate from the current worktree/session. An orchestrator agent may keep tabs on, review, and coordinate an implementor agent, but they must not share worktrees, mutable state, or PR ownership. Do not treat normal local agent/subagent requests or tmux-interactive collaboration as handoff requests.

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
