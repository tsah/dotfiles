---
name: self-destruct
description: >-
  Use only when the user's message contains the literal phrase "self destruct"
  or "self-destruct" addressed to this current agent, such as "Do X and then
  self destruct". If that exact phrase is absent, this skill is irrelevant.
---

# Self Destruct

This skill removes this agent's own spawned worktree and tmux session after the
requested work is complete.

## Activation gate

Only proceed when the user's current request explicitly includes `self destruct`
or `self-destruct` for this agent. If that phrase is absent, do not use this
skill. If the instruction is ambiguous, ask before doing anything destructive.

## Rules

- Finish the requested work first.
- Commit/push or otherwise deliver anything the user expects to keep; removing
  the worktree deletes uncommitted files.
- Only delete this agent's own current worktree and current tmux session.
- Never target another session, another worktree, the default branch, or the
  user's main checkout.
- Do not treat ordinary words like cleanup, prune, delete, remove, exit, stop,
  or terminate as permission to self destruct.

## Command

Run this only as the final action:

```bash
agent-self-destruct --yes
```

If `agent-self-destruct` is not on `PATH`, use the bundled wrapper:

```bash
bash "$HOME/dotfiles/claude/skills/self-destruct/scripts/self-destruct.sh" --yes
```

The script validates that it is inside tmux, inside a git worktree, not on the
default branch, and that the current tmux session matches the worktree branch
before it delegates to `wt destroy`.
