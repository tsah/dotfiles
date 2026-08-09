---
name: handoff
description: >-
  Create a visible clanker in a new durable Worktrunk workshop. Use only when
  the user explicitly asks to hand off/delegate into a separate worktree or
  workshop. Tmux visibility alone does not imply a workshop handoff.
---

# Workshop handoff

A handoff creates a **workshop** (durable worktree plus canonical/lazy tmux
session container) and its initial **clanker** (one visible harness session).
Pi, Claude, OpenCode, and Codex are harnesses, not agents. Harness-native
in-process subagents are not clankers.

Do not use a handoff for an existing clanker (use `clanker-coordination`), native
in-process delegation, or a shell/test pane in the current workshop. The words
**tmux**, **window**, **pane**, **visible**, and **separate** alone do not request
worktree isolation; ask when intent is ambiguous.

## Launch

Prefer the harness-neutral public command:

```bash
clankers workshop spawn --name feature-x --harness pi --prompt '<self-contained prompt>'
```

This asks Worktrunk to create branch/worktree `feature-x`, records it as a
workshop, lazily ensures its canonical tmux session and stable `main` window,
then creates the initial named-by-harness clanker window. The prompt defaults to
`Ready for instructions.` when omitted.

Harness launchers remain convenient adapters:

```bash
workshop-pi <branch> '<prompt>'
env -u ANTHROPIC_API_KEY workshop-claude <branch> '<prompt>'
workshop-opencode <branch> '<prompt>'
workshop-codex <branch> '<prompt>'
```

Normal handoffs link to the caller's workshop. Use `--no-parent` only for an
explicitly standalone handoff, and `--parent WORKSHOP_ID` only for a requested
recorded parent. `--base`, `--wait`, and harness-profile options may be supplied
when needed.

To add a clanker without creating another worktree:

```bash
clankers spawn --workshop feature-x --name reviewer --harness claude --prompt '<prompt>'
```

`--workshop` resolves a unique durable workshop ID, branch, canonical path, or
worktree basename in the current repository. `--name` is the tmux window label;
it is never identity. The returned `clankerId` is the stable orchestration ID.

Report the workshop path/branch/session, harness/window, and returned ID. A
failed or timed-out wait leaves the workshop and clanker available. Never drive
a clanker through tmux terminal input or pane capture.
