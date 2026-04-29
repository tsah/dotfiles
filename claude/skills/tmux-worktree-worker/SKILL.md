---
name: tmux-worktree-worker
description: >-
  Legacy manual reference for harness-native tmux worktree workers. Kept only
  as documentation; use the native tworker mechanism for the current harness.
disable-model-invocation: true
---

# Tmux Worktree Worker Reference

This file is a **manual reference only**.

Do **not** auto-load this skill for generic worker requests. Each harness should
spawn its own native worker:

- **Claude Code** → `/tworker` or `spawn-claude-tworker`
- **OpenCode** → `/tworker` or `spawn-opencode-agent`
- **pi** → `tworker` / `tmux_tworker` or `spawn-pi-tworker`

## Core Rule

Stay inside the current harness unless the user explicitly asks for another
one.

- Do not launch OpenCode workers from pi.
- Do not launch pi workers from OpenCode.
- Do not launch OpenCode workers from Claude Code.

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
