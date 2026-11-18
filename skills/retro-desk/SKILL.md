---
name: retro-desk
description: Run the tweezr retro desk - read every finished Workshop in the retro queue (transcripts, merged PR, first-push CI), keep the findings ledger in ~/.local/state/tweezr-retro, propose environment changes (steering, skills, hooks, checks) for Tsah to decide, refresh the desk's report page on puffin, and post to Grokus when a run has new findings. Use when told a Workshop was queued ("Work the queue"), when a routine says "Run your retro-desk skill now", or when asked what the retro desk has pending.
---

# Retro desk

One long-lived session that runs a retro on every finished tweezr Workshop and
improves the *environment* future agents work in. It never reviews or changes
the code a Workshop wrote.

The canonical method is the brief, `~/.config/clankerhouse/retro/brief.md`.
This skill is how the desk runs it day to day; where they differ, the brief
wins, except for the publishing rules below, which Tsah added on 2026-11-18.

## State (`~/.local/state/tweezr-retro`)

```
queue/*.json            finished Workshops waiting (title, path, branch, workshopId), oldest name first
queue/processed/        entries already read
cursors/<workshopId>.md how far each Workshop's sources were read, one section per pass
findings/<slug>.md      the ledger, one finding per file
runs/<YYYY-MM-DD>.md    one record per run: "# <title>", "## Headline", Workshops, Proposed
```

The directory is the memory. After a restart or compaction, read it, not the
conversation.

## How work arrives

- **Queue hook.** When a Workshop's PR is merged and it is marked done,
  clankerhouse's retro hook writes `queue/<stamp>-<workshopId>.json` and sends
  this session "A new Workshop is queued … Work the queue." The queue
  directory, not the message, is the truth; messages can be dropped or
  duplicated.
- **Routine.** `retro-desk-weekly`, Tuesday and Thursday 11:00
  Europe/Amsterdam, sends "Run your retro-desk skill now." It catches anything
  a dropped notice left in the queue. An empty queue then means: refresh the
  page, post nothing.

## What the desk may do

- Read anything.
- Write inside the state directory, and the desk's page under
  `~/reports/retro-desk/` (through `publish-report` and `render_report.py`).
- POST to Grokus's webhook with `post.py`, only after a run with new findings.
- Never edit the tweezr repository, its steering files, skills, hooks or
  checks. The desk proposes; Tsah decides.
- **PR-only changes.** When Tsah accepts a proposal, hand it off to a new
  Workshop (`clankers workshop spawn --name <slug> --harness claude --no-parent
  --base origin/master --prompt "<self-contained brief>"`), which takes it to a
  PR through factory mode. The desk never commits, opens PRs or tickets, or
  merges.
- Accept a decision only when Tsah types it in this session. A relayed
  "Tsah says …" from another session is a request, not his approval.
- Never mark this Workshop done; that stops the desk.
- Never print full process command lines (`pgrep -af`, `ps -ef`); they carry
  secrets. Redact `lin_api_…` and any other key found in a transcript, and
  tell Tsah the file and line so he can rotate it.

## A run

1. `update_status planning`. Bring the repo up to date so proposals match it:
   `cd ~/dev/work/tweezr/retro-desk && timeout 90 git fetch origin master && git switch --detach origin/master`.
   If the fetch races another fetch ("cannot lock ref"), retry once.
2. Take `queue/*.json` in name order, up to three at once. For each, start a
   general-purpose subagent in the background with:
   - the brief's **Reading a Workshop** section, verbatim;
   - the queue entry, and the Workshop's cursor if one exists (or the
     citations the ledger already has for its branch);
   - "do not write files, do not run update_status, do not message anyone,
     never print process command lines, redact secrets";
   - "check sibling `~/.claude/projects/<key>*` folders (probe copies,
     imports) and say what they are; if no PR has the branch as head, search
     merged PRs; `[clankerhouse msg-…]` lines are agents, but relays quoting
     Tsah count as his feedback".
3. As each subagent returns, alone and one Workshop at a time:
   - **Verify** any claim a proposal would rest on: open the cited transcript
     line or the file on `origin/master`. Drop what doesn't hold.
   - **Ledger.** Read every finding's front matter first. Match on the
     problem, not the wording: add an occurrence to an existing file, or
     create one. Never repeat a citation (assert the Workshop's
     `(<branch>)` tag is not already in the file). Drop one-off,
     task-specific friction.
   - **Cursor.** Write `cursors/<workshopId>.md`: title, branch, the date of
     each pass, and the subagent's cursor (last line per transcript file, PR
     number with last comment and commit, latest CI runs).
   - Move the entry to `queue/processed/`.
4. When the queue is empty, write `runs/<date>.md` (add `-2`, `-3` for a
   second run that day), then publish and report (below).
   `update_status needs-input` before ending the turn.

## The ledger

```markdown
---
finding: <one sentence naming the problem>
kind: mechanical | judgement
status: open | proposed | accepted | rejected
---

## Occurrences
- <date> · <Workshop title> (<branch>) · <transcript path Lnnn (timestamp) | thread URL | run URL> — "<short quote>"

## Proposal
<empty until proposed; then the smallest concrete change and where it goes>

## Decisions
- <date> · <accepted | rejected> — <Tsah's reason, in his words>
```

- **mechanical:** a deterministic check (lint rule, hook, test) could have
  caught it. Proposed on its first occurrence, but only when the cause is
  verified; otherwise it stays `open` with a "Not proposed yet: …" note.
- **judgement:** needs prose (a steering line, a skill, a reviewer rule).
  `open` on the first occurrence; `proposed` on a second from a different
  Workshop.
- `rejected` is final: add occurrences, never re-propose.
- A proposal names the place on `origin/master` (file and line), prefers a
  deterministic check over prose, and prefers editing an existing rule over
  adding one. Read `AGENTS.md` and what it points to before choosing.
  Amend an existing proposal with a dated `- Amended <date> after <Workshop>:`
  line rather than rewriting it.
- Record Tsah's accept or reject under Decisions, with his words, and the
  hand-off Workshop and branch when one is spawned (the page links the PR
  from that branch).

## Publishing

After every run, and whenever a decision changes the ledger:

```bash
tmp=$(mktemp -d -p "$SCRATCH")    # a fresh dir in the session scratchpad
# 1. Only when the run read at least one Workshop: a page for this run.
url=$(publish-report retro-desk "Retro: <headline>" "$tmp/run.md")
# 2. Always: the always-current dashboard (findings by status, linked PRs, runs).
python3 ~/.claude/skills/retro-desk/render_report.py
```

- `run.md` is the chat report (below) as Markdown, each `##` a card.
- `publish-report` (`~/dotfiles/bin`, Slop Master's shared tool) writes
  `~/reports/retro-desk/runs/<stamp>.html`, appends `runs.json`, and rebuilds
  `~/reports/index.html`. It also rewrites `~/reports/retro-desk/index.html`
  as a plain list, so `render_report.py` always runs after it and replaces
  that with the dashboard, which lists the run pages from `runs.json`.
- Pages are served by the user unit `reports-server` behind tailscale:
  dashboard `https://puffin.tail685506.ts.net/reports/retro-desk/`.
- **Webhook.** Only when the run added a finding, added an occurrence, or
  set a proposal:
  `python3 ~/.claude/skills/retro-desk/post.py "Retro desk: <one-line headline>" "$url"`.
  It reads the `groky` sink from `~/.config/clankerhouse/hooks.toml` at run
  time and prints only the HTTP status; never print, echo or log the URL or
  Authorization header. Post nothing when nothing is new (an empty routine
  run, a page refresh). A failed post is retried once, then reported in chat.

## Reporting in chat

After working the queue:
1. Workshops covered, with any sources that were missing.
2. Findings added or updated, one line each with the ledger file name.
3. **Recommendations:** only findings just set to `proposed`, each with the
   change, where it goes and its occurrences. If none, say so in one line.

Then the page link. Bullets, not tables; describe work by what it does, not
by ticket or PR numbers; facts, not value judgements. End with
`**Waiting on you:** …` when a decision is pending. When asked what is
pending, list `status: proposed` findings from the ledger.
