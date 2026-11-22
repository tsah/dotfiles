---
name: slop-weed
description: Close out finished work on the dev box without asking Tsah first - mark done the workshops whose work merged or ended, reap done worktrees whose retro ran, and list the remaining cleanup (draft PRs nobody works on, abandoned workshops) for a veto. Part of the sow / tend / weed / harvest cycle. Use when a routine says "Run your slop-weed skill now", or when Tsah says "weed".
---

# slop-weed

`slop-sow` decides what gets built, `unblock-sweep` tends what grows,
`slop-harvest` merges. `slop-weed` clears what is finished, so it never
waits on Tsah. Tsah approved this on 2026-11-22 ("go ahead with it"):
act first, tell him after, and he vetoes what he disagrees with.

## 1. Sweep

From live state only (`clankers list`, `clankers settled --json --messages 1`,
`gh pr view`), sort each workshop that is not labelled `status=done`:
- **Finished:** its PR merged, or it was an investigation or report whose
  final reply has been relayed to Tsah or its orchestrator, and it has no
  open ask.
- **Abandoned:** no clanker, or idle for 3+ days, with no merged PR and
  no ask (often a closed or superseded draft).
- Anything else stays.

Skip, always:
- orchestrators with live children, desks (retro, prompts, test-quality,
  lint-quality, design-integrity), and the task-manager workshop;
- workshops with an open decision for Tsah, or that a memory names as evidence;
- anything working right now.

## 2. Act

- **Finished:** `clankers workshop label set status=done --workshop ID`.
  The done label triggers the retro and closes the Linear ticket (see the
  clankerhouse retirement hook), so do this only when the PR merged or no
  ticket is tied to the work.
- **Reap:** done worktrees whose retro ran, per the reap-post-retro-worktrees
  memory: `wt remove -f -D --reap --foreground PATH`. Keep any with a live
  clanker, an open decision or evidence a memory points to.
- **Abandoned and draft PRs:** do not act. List them for veto (below). Closing
  a PR or a ticket needs Tsah's yes.
- Under an orchestrator: tell the orchestrator what you marked done
  (`clankers send`), don't mark its children done when it still tracks them.

Never `rm -r` a worktree, never run `pgrep -af` or full `ps`, use
`/usr/bin/grep`, and never run `update_status` from a subagent.

## 3. Tell Tsah

One short message (and a line in the morning box report):
- **Closed:** each workshop by what it did, and why it counted as finished.
- **Reaped:** count and disk freed.
- **Veto by evening:** abandoned workshops and draft PRs I propose to close,
  each in one line. Reply `close` / `keep <name>`. Unanswered items stay as
  they are and reappear next run; they never auto-close.

Log each run to `~/.local/state/slop-weed/YYYY-MM-DD.md`.
