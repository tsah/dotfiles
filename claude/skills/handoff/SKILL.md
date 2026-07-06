---
name: handoff
description: >-
  Use when the user asks to hand off work, handoff this, spawn a visible tmux
  worktree worker, use /handoff, or run a separate worker in the current
  harness. A handoff means a visible tmux session/window with its own worktree,
  not a normal in-session agent/subagent and not remote/headless execution.
---

# Handoff

A handoff is for independent, isolated implementation or research. It creates a
visible tmux worktree worker: a separate tmux session/window with its own git
worktree, launched from the current harness.

The separate worktree + tmux session is the point of a handoff: the worker can
make changes, run experiments, or research independently without disturbing the
current working tree or current tmux session.

Use this skill when the user asks to:

- hand off work
- handoff this
- hand this off
- spawn a tmux worker
- spawn a worktree worker
- run a separate visible worker
- use `/handoff`

Do not use this skill for local, collaborative, in-session agent/subagent
delegation. For that, use tmux interactive control or the harness's same-session
subagent mechanism instead.

## Core Rules

Stay inside the current harness unless the user explicitly asks for another one.

- Claude Code uses `/handoff` or `spawn-claude-tworker`.
  When invoking Claude Code, ensure `ANTHROPIC_API_KEY` is unset so the Claude
  subscription is used rather than direct API access.
- OpenCode uses `/handoff` or `spawn-opencode-agent`.
- pi uses `tworker`, `tmux_tworker`, or `spawn-pi-tworker`.

Do not launch remote/headless workers unless the user explicitly asks for a
remote job, background job, detached job, or headless mode.

Prefer a visible tmux session/window worker using the native launcher below.

## Handoff vs Tmux Interactive Control

Use **handoff** when the user wants a separate worker to own an isolated task:

- independent implementation
- independent research/investigation
- orchestration where a parent/orchestrator agent keeps tabs on an implementor agent
- exploratory changes that should not touch the current worktree
- a task branch/worktree the user can inspect or merge later

Orchestration is allowed, but isolation still applies: the orchestrator and
implementor must not share worktrees, mutable state, or PR ownership. The
orchestrator may monitor, review, and coordinate; the implementor owns its
separate worktree/task branch.

Use **tmux interactive control** when the work is local to the current tmux
session and feels like collaborating with a nearby sub-agent or CLI:

- driving an existing pane, REPL, debugger, test watcher, shell, or agent
- sending keys and reading output in the current session
- coordinating with the current worktree instead of creating an isolated one

If the user says “handoff”, create a new worktree + tmux session. If the user
asks to interact with or control something already in tmux, do not create a new
worktree worker.

## Manual Launcher Reference

### Claude Code

```bash
env -u ANTHROPIC_API_KEY spawn-claude-tworker [--agent <agent-name>] <branch-name> <initial-prompt>
```

The launcher also unsets `ANTHROPIC_API_KEY` before executing `claude`.

### OpenCode

```bash
spawn-opencode-agent [--agent <agent-name>] <branch-name> <initial-prompt>
```

### pi

```bash
spawn-pi-tworker [--agent <agent-name>] <branch-name> <initial-prompt>
```
