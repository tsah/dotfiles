---
name: slop-sow
description: Walk Tsah through all work on the dev box that is waiting to be created - shapes waiting for Shape Go, shaping questions, explainers written before a shape, framing tickets, and proposed follow-up workshops nobody has spawned yet - one item at a time, from his phone. The counterpart of slop-harvest, which handles finished work. Use when Tsah says "sow", "what's waiting to be created", "shapes", or runs /slop-sow.
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

## 5. End

On an empty queue or `stop`, post a summary: planted (go), sent back,
parked or dropped, skipped. Run `update_status needs-input` before each
message that waits on Tsah.
