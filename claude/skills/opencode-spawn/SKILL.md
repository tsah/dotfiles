---
name: Opencode Spawn
description: >-
  Use this skill when the user asks to delegate work to another interactive
  opencode worker in tmux and wants that worker to start immediately.
---

# Opencode Spawn Skill

Use this skill for requests like:
- "spawn an agent"
- "delegate this task"
- "run these in parallel"
- "start another opencode session to handle X"

## Core Rule

Always use the helper script:

```bash
spawn-opencode-agent "<branch-name>" "<initial-prompt>"
```

If a specific opencode agent is requested:

```bash
spawn-opencode-agent --agent "<agent-name>" "<branch-name>" "<initial-prompt>"
```

## Operating Constraints

- Do not run preflight commands (`ls`, `git worktree list`, `git fetch`).
- Do not create worktrees manually (`git worktree add`).
- For N independent delegated tasks, run exactly N spawn commands in parallel.
- Run extra commands only if a spawn command fails.

## Branch Naming

- Use lowercase kebab-case.
- Keep names short and task-specific.
- Example: `investigate-startup-health-check`.

## Initial Prompt Quality

Include:
- concrete objective
- constraints from the user
- expected output (summary, files changed, tests run)

## Response Format

After spawning, report:
- tmux session name
- tmux window name
- switch hint (`Alt+k` picker or `tmux switch-client -t "<session>"`)
