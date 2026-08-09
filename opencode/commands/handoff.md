---
description: Handoff work to a visible tmux workshop clanker
---

Handoff work to a separate visible **OpenCode** tmux workshop clanker with `workshop-opencode`.

A handoff is a separate visible tmux workshop clanker for independent, isolated implementation, research, or orchestration. The new worktree + tmux session is intentional: it keeps the clanker's edits and experiments separate from the current worktree/session. An orchestrator clanker may keep tabs on, review, and coordinate an implementor clanker, but they must not share worktrees, mutable state, or PR ownership. Do not treat normal local harness/subagent requests or tmux-interactive collaboration as handoff requests.

Do **not** use `workshop-pi` or `workshop-claude` unless the user explicitly asks for pi or Claude Code. If invoking Claude Code, run it without `ANTHROPIC_API_KEY` in the environment, e.g. `env -u ANTHROPIC_API_KEY workshop-claude ...`, so the subscription is used instead of direct API access.


Arguments: `$ARGUMENTS`

Interpret arguments in this order:
1. `--profile <profile-name> --base <ref> --copy <path> <branch-name> <initial-prompt>`
2. `--profile <profile-name> <branch-name> <initial-prompt>`
3. `<branch-name> <initial-prompt>`
4. `<initial-prompt>` (derive a short kebab-case branch name)

Pass through these options when requested:
- `--base <ref>`: base the new worktree branch on this ref. If omitted, `workshop-opencode` defaults to `origin/master` after fetching.
- `--copy <path>`: copy a file or directory from the current worktree into the spawned worktree at the same relative path. Repeat it for multiple files, such as plan files.

If the user does not provide `--profile`, use `--profile build`.

Do not start clankers in `plan` mode. If the clanker needs planning, analysis, architecture exploration, or a written plan, keep it in `build` mode and include those instructions in the initial prompt. Ask it to write its plan or findings to a document when useful.

Only use another harness when explicitly requested:
- `fast`: quick iterations, lightweight edits, or triage
- `plan`: only when the user explicitly asks for a plan-mode clanker

Default to one clanker unless the user explicitly asks for multiple clankers.

After spawning, report:
- tmux session name
- tmux window name
- switch hint
