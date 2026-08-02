---
name: handoff
description: >-
  Create a visible agent worker in a separate Worktrunk worktree and tmux
  session. Use when the user asks to hand off, handoff this, delegate work,
  spawn an isolated or visible worker, create a worktree worker, run work in a
  separate worktree, or give a task to another agent. Do not use for
  communicating with an already-running agent.
---

# Handoff

A handoff creates a new visible worker in its own Worktrunk-managed worktree and
tmux session. Use it for independent implementation, research, investigation,
or orchestration where isolation is intentional.

Do not use handoff for:

- an existing visible agent: use the `agent-coordination` skill
- same-session delegation: use the harness's native subagent mechanism
- a shell, REPL, debugger, or test watcher: use appropriate interactive tooling
- remote/headless work unless the user explicitly asks for it

## Launch rules

Stay inside the current harness unless the user asks for another one:

- Claude Code: `env -u ANTHROPIC_API_KEY worker-claude`
- OpenCode: `worker-opencode`
- Pi: `worker-pi`

All launchers accept:

```text
[--agent AGENT_NAME] [--base BASE] [--window WINDOW]
[--no-parent | --parent WORKSPACE_ID]
BRANCH INITIAL_PROMPT
```

Use a concise branch name and make the initial prompt self-contained; workers do
not inherit the current conversation.

## Lineage

Normal handoffs are linked to the caller's workspace. Use `--no-parent` only
when the user says **standalone**, or when the task is genuinely self-contained
and the caller will not monitor, review, coordinate, or continue from its
result.

Do not infer standalone from **independent**, **isolated**, or **separate**;
every handoff already has those properties.

Use `--parent WORKSPACE_ID` only when the user or orchestration flow explicitly
requires a particular recorded parent.

## Launch examples

```bash
env -u ANTHROPIC_API_KEY worker-claude <branch> '<self-contained prompt>'
worker-opencode <branch> '<self-contained prompt>'
worker-pi <branch> '<self-contained prompt>'
```

Standalone forms:

```bash
env -u ANTHROPIC_API_KEY worker-claude --no-parent <branch> '<prompt>'
worker-opencode --no-parent <branch> '<prompt>'
worker-pi --no-parent <branch> '<prompt>'
```

## Result of a handoff

Report the created worktree, branch, tmux session/window, harness, and stable
`agentId` returned by the launcher. Retain the `agentId`; do not use a mutable
session/window name as orchestration identity.

If the request also asks to monitor, wait for, message, steer, or collect the
worker's result, continue with the `agent-coordination` skill after launch.

A failed or timed-out launch must leave any visible worker/worktree available
unless the native launcher says it was never created. Never inspect or drive an
agent through tmux terminal input or pane capture.
