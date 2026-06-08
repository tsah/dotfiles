---
name: handoff
description: >-
  Use when the user asks to hand off work, handoff this, spawn a visible tmux
  worktree worker, create a tworker, or run a separate worker in the current
  harness. A handoff means a visible tmux session/window with its own worktree,
  not a normal in-session agent/subagent and not remote/headless execution.
---

# Handoff

A handoff is a visible tmux worktree worker: a separate tmux session/window with
its own worktree, launched from the current harness.

Use this skill when the user asks to:

- hand off work
- handoff this
- hand this off
- spawn a tworker
- spawn a tmux worker
- spawn a worktree worker
- run a separate visible worker
- use `/tw` or `/tworker`

Do not use this skill for normal in-session agent/subagent delegation.

## Core Rules

Stay inside the current harness unless the user explicitly asks for another one.

- Claude Code uses `/tworker` or `spawn-claude-tworker`.
- OpenCode uses `/tworker` or `spawn-opencode-agent`.
- pi uses `tworker`, `tmux_tworker`, or `spawn-pi-tworker`.

Do not launch remote/headless workers unless the user explicitly asks for a
remote job, background job, detached job, or headless mode.

Prefer a visible tmux session/window worker using the native launcher below.

## Manual Launcher Reference

### Claude Code

```bash
spawn-claude-tworker [--agent <agent-name>] <branch-name> <initial-prompt>
```

### OpenCode

```bash
spawn-opencode-agent [--agent <agent-name>] <branch-name> <initial-prompt>
```

### pi

```bash
spawn-pi-tworker [--agent <agent-name>] <branch-name> <initial-prompt>
```
