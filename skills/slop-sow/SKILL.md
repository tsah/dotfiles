---
name: slop-sow
description: Walk Tsah through all work on the dev box that is waiting to be created - shapes waiting for Shape Go, shaping questions, explainers written before a shape, framing tickets, and proposed follow-up workshops nobody has spawned yet, and Linear tickets assigned to him with no workshop - one item at a time, from his phone. The counterpart of slop-harvest, which handles finished work. Use when Tsah says "sow", "what's waiting to be created", "shapes", or runs /slop-sow.
---

# slop-sow

`slop-harvest` gathers finished work (merges, stuck workers, access calls).
`slop-sow` plants new work: everything that waits for Tsah to decide
*whether and how it gets built*. He decides what goes in the ground; the
workers grow it.

## 1. Sweep

Build the list from live state, never from memory:

```bash
clankers list                                  # state, lastText, parentWorkshopId, workshop
clankers settled --json --messages 1           # full last replies
```

An item is waiting to be created when a worker's last reply asks for:
- **Shape Go** on a shaped ticket (the shape in the ticket, or a
  `temp/shape*.md` draft).
- **Shaping answers:** open questions in a draft shape.
- **A reaction to an explainer** written before shaping (an artifact or page
  that explains a problem, then proposes options).
- **Frame Go** on a framing ticket.
- **A spawn:** a proposed follow-up workshop, ticket or investigation that
  nobody has started ("worth a separate ticket", "I'd open a follow-up").
- **Park or drop** on a finished exploration that recommends future work.
- **A finished investigation whose recommendation nobody acted on**, even
  when it never asked Tsah anything (often a child that reported to an
  orchestrator that then went idle).

Work under a live orchestrator goes through it: one item per workstream,
built from the orchestrator's state and checked against its workers, and
Tsah's answers go to the orchestrator, which passes them down. Go to a
worker directly only when its orchestrator is dead or stalled.

Also, **Linear tickets on Tsah with no workshop yet**: his open TWE issues
(assigned to him, not completed or canceled) that no clanker works on.
- List them read-only through `./task/agent/linear api` with
  `viewer { assignedIssues(filter: {team: {key: {eq: "TWE"}}, state: {type: {nin: ["completed","canceled"]}}}) }`.
- An issue has a workshop when its TWE id appears in a live clanker's
  session, name, worktree path or branch, or in a `temp/build/TWE-<n>/`
  folder in its worktree (the same match as `linear-sweep`'s `collect.py`),
  or in an open PR's title or branch.
- Don't change Linear while sweeping.

Also read the orchestrators' ledgers and last replies: they often hold a
queue of shapes for their workstream. For each shape, read the ticket
description (`./task/agent/linear`) or the draft file, so you can explain it.

Drop anything already built, merged, cancelled, or superseded by a later
reply. Write the list to the scratchpad.

## 2. Order

1. **Unblocking:** shapes or answers that another running build waits on.
2. **Workstreams:** shapes under one orchestrator together, in the order
   they would build.
3. **Standalone shapes and explainers**, oldest first.
4. **Spawn, park or drop** proposals.
5. **Linear tickets with no workshop:** In Progress first, then Todo/Next,
   then Backlog and Triage; by priority, then oldest.

## 3. Present one item per message

Phone-sized, plain words, nested bullets, no tables. Name the work, not bare
ticket numbers.

- **Header:** `Seed k of n · <kind> · <workshop>`
- **The problem:** what is wrong today, with one concrete example.
- **Wider context:** the parent orchestrator, sibling shapes and their state,
  and what this builds after or unblocks.
- **The shape:** what would be built, its size (tier), and the measured
  evidence for it. What was considered and left out, and why.
- **The ask:** one question. Recommendation and why.
- **Reply with:** `go` / `back to shaping` / `park` / `drop` / free text.

One decision per message. When a draft has several open questions, walk them
as `Question 1 of 4` and so on, then ask for Shape Go last.

Keep the walk moving: once an answer settles an item, act on it and show the
next item in the same reply. `skip` means no decision now: show the next item
without asking again.

## 4. Act

Relay each answer to the worker verbatim, through a background subagent
under the delivery rules in `slop-harvest` §4. The subagent never runs
`update_status`.
- **go:** the worker records Shape Go on the ticket and builds now, or when
  its dependency lands if the shape says so.
- **back to shaping:** relay Tsah's comments; the worker reshapes.
- **park:** the worker notes it on the ticket and marks its workshop done
  (`clankers workshop label set status=done --workshop ID`).
- **drop:** the same, and the ticket is cancelled.
- **spawn:** start the workshop with the `handoff` skill, under the parent
  orchestrator when there is one.
- **For a Linear ticket with no workshop,** the replies are `shape` (a
  workshop that shapes it), `build` (factory mode, when the ticket is
  already clear), `unassign`, `cancel` or `skip`. Spawn with `handoff`.
  Tsah's reply is the order for any Linear change it names.

## 5. End

On an empty queue or `stop`, post a summary: planted (go), sent back,
parked or dropped, skipped. Run `update_status needs-input` before each
message that waits on Tsah.
