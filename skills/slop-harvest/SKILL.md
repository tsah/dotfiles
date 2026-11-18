---
name: slop-harvest
description: Walk Tsah through everything on the dev box that waits on him, one item at a time. Sweep all clankers, order the items (stuck first, then decisions, then merges, then FYIs), present each with enough context to decide from a phone, hand each answer to a background subagent, and move straight on to the next item. Use when Tsah asks for decisions, "what needs me", "fetch me more decisions", "next", or runs /slop-harvest.
---

# slop-harvest

Tsah runs many clankers and does not remember each one. This skill turns the
whole box into a queue he can clear one item at a time, often from his phone.
You are his window into the box: you read state, explain it, relay his
answers and keep the next item ready.

## 1. Sweep

First read the unblock-sweep logs since Tsah's last harvest
(`~/.local/state/unblock-sweep/*.md`). Open the walk with one short message
on what the overnight sweeps did, then put their "Waiting on Tsah" and
"Ready for review" entries into the queue.

Build the item list from live state, never from memory or earlier messages:

```bash
clankers list                                  # every clanker: state, lastText, lastReport, workshop
clankers settled --json --messages 1           # idle sessions with the full last reply, labels, PR, needsMe
clankers needs-me --json                       # the picker's needs-me rows
```

For each candidate, read enough to explain it:
- The full last reply (`settled` rows' `lastMessages`, or `clankers result ID`).
  Look for "Waiting on you", "Decisions for you", "Your call", "say ship it".
- The PR, if there is one: `gh pr view N --repo OWNER/REPO --json title,state,isDraft,mergeStateStatus,body`.
  The body's change-risk section is the merge context. Check whether it already merged.
- For a stuck clanker: `clankers status ID`. Read `state`, `blockedMessage` and `health`.

Drop items that are already resolved: the PR merged, a later reply supersedes
the ask, or the worker is mid-turn on it. Write the list to the scratchpad so
it survives a long session.

## 2. Order

1. **Stuck:** blocked or dead workers, such as a quota hit, a startup dialog, a
   wedged process, or CI failing with nobody on it.
2. **Decisions:** design calls, approvals (AWS logins, Shape Go, spend on A/B
   runs) and Linear or settings changes that only Tsah can make.
3. **Merges:** PRs waiting for "ship it".
4. **FYIs:** finished work with nothing to decide.

Oldest first within each group. Group related items (one workstream, one PR
chain) into a single item when one answer covers them.

## 3. Present one item per message

Phone-sized. Plain words; describe the work, not ticket or PR numbers alone.
Nested bullets, no tables. Each item has:

- **Header:** `Item k of n · <group> · <workshop>`
- **What it is:** one or two lines on the problem and why the work started.
- **Where it stands:** what is proven, with the evidence named, and what is
  not proven or still open.
- **The ask:** the exact question. Show each option concretely (an example
  beats an abstract choice), then my recommendation and why.
- **Reply with:** short options, like `merge` / `skip` / `dig in` / free text.

**One decision per message.** When an item holds several decisions, the
first message gives the item's background and only decision 1. After Tsah
answers, show decision 2 alone (`Decision 2 of 4`), and so on. Never stack
several questions in one message.

If Tsah asks for more context, dig in (worktree, transcript, PR diff) and
answer before moving on. "skip" moves the item to the end. "stop" ends the walk.

## 4. Act through a background subagent

Once Tsah answers, launch one background subagent (Agent tool,
`run_in_background: true`) for the action, then show the next item at once.
Never make Tsah wait on an action.

Give the subagent:
- The clanker ID, workshop path, session name and pane.
- Tsah's decision **verbatim**, plus the message to deliver. A merge order ends
  with its own sentence `Ship it.` or `Automerge.`, and nothing after it in
  that sentence: the merge guard reads only that form.
- How to deliver it, and how to prove it arrived (below).
- To report back in one line: delivered or not, and what the worker did first.
- Not to run `update_status`. That is the parent's status.

**Merge orders are the exception:** type them yourself, in the main session,
right after Tsah answers. A subagent cannot see Tsah's answer, so it rightly
refuses to type a merge order on his behalf. It takes seconds; then show the
next item, and have a background subagent only watch for the merge.

Delivery rules:
- **Busy worker** (`working`): `printf '%s' "$msg" | clankers send ID --request-id KEY`.
  The message gets queued.
- **Idle or settled worker:** `clankers send` is currently dropped by a
  Clankerhouse hook ("this message was already delivered"). Type the message
  as one line into the pane instead. Tsah authorized this as the workaround
  until that bug is fixed:
  ```bash
  rex capture -s SESSION -b PANE6 --trim | tail -3      # prompt must be empty
  rex send-key -s SESSION -b PANE6 ctrl+u               # clear any suggestion text
  rex send -s SESSION -b PANE6 "$msg"; rex send-key -s SESSION -b PANE6 enter
  ```
  `PANE6` is the last 6 characters of the clanker's `pane` (`block:...`).
- **Prove delivery:** the message text appears as a `type=="user"` record in
  the worker's newest transcript under `~/.claude/projects/-<cwd with / as ->/`.
  A `UserPromptSubmit operation blocked` record means it was dropped. Retry by
  typing it into the pane.
- **Restart on another model:** kill the pane (`clankers mux kill --pane`),
  then `clankers resume ID` with no prompt. Wait for the input box, type
  `/model <name>`, press enter twice to confirm, then send the continue
  message. A resume keeps the session's last model, so the switch is needed.
- **Approvals Tsah must do himself** (Linear settings, `claude setup-token`, AWS
  approval on his phone): no subagent. Tell him exactly where to click or what
  to type.

## 5. Between and after items

- When a subagent finishes, put one line above the next item, such as
  `✓ #5331: merge order delivered, worker merging`. Re-queue a failure as a
  stuck item.
- At the end, or on "stop", post a summary:
  - **Decided:** each item and the answer.
  - **Still running:** subagents and workers acting on answers.
  - **Skipped or left:** what is still open.
- Run `update_status needs-input` before each message that waits on Tsah.
