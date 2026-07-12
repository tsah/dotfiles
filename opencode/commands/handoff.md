---
description: Handoff work to a visible tmux worktree worker
---

Handoff work to a separate visible **OpenCode** tmux worktree worker with `worker-opencode`.

A handoff is a separate visible tmux worktree worker for independent, isolated implementation, research, or orchestration. The new worktree + tmux session is intentional: it keeps the worker's edits and experiments separate from the current worktree/session. An orchestrator agent may keep tabs on, review, and coordinate an implementor agent, but they must not share worktrees, mutable state, or PR ownership. Do not treat normal local agent/subagent requests or tmux-interactive collaboration as handoff requests.

Do **not** use `worker-pi` or `worker-claude` unless the user explicitly asks for pi or Claude Code. If invoking Claude Code, run it without `ANTHROPIC_API_KEY` in the environment, e.g. `env -u ANTHROPIC_API_KEY worker-claude ...`, so the subscription is used instead of direct API access.


Arguments: `$ARGUMENTS`

Interpret arguments in this order:
1. `--agent <agent-name> --base <ref> --copy <path> <branch-name> <initial-prompt>`
2. `--agent <agent-name> <branch-name> <initial-prompt>`
3. `<branch-name> <initial-prompt>`
4. `<initial-prompt>` (derive a short kebab-case branch name)

Pass through these options when requested:
- `--base <ref>`: base the new worktree branch on this ref. If omitted, `worker-opencode` defaults to `origin/master` after fetching.
- `--copy <path>`: copy a file or directory from the current worktree into the spawned worktree at the same relative path. Repeat it for multiple files, such as plan files.

If the user does not provide `--agent`, use `--agent build`.

Do not start workers in `plan` mode. If the worker needs planning, analysis, architecture exploration, or a written plan, keep it in `build` mode and include those instructions in the initial prompt. Ask it to write its plan or findings to a document when useful.

Only use another agent when explicitly requested:
- `fast`: quick iterations, lightweight edits, or triage
- `plan`: only when the user explicitly asks for a plan-mode worker

Default to one worker unless the user explicitly asks for multiple workers.

After spawning, report:
- tmux session name
- tmux window name
- switch hint
