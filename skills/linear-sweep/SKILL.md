---
name: linear-sweep
description: Weekday-morning, read-only sweep of Tsah's Linear issues in team TWE. Reports what's new on him since the last run and where his issues are out of sync with live clankers and PRs, and offers fixes without making them. Posted through Grokus's webhook, and nothing is posted when nothing is new. Use when a routine says "Run your linear-sweep skill now", or when asked for the Linear sweep.
---

# linear-sweep

Investigate only. **Never change Linear**: no state, assignee, label or
comment writes. Only Tsah applies a fix.

1. Collect: `python3 ~/.claude/skills/linear-sweep/collect.py > "$tmp/facts.json"`.
   - **How it works:** it reads Linear through the repo's `./task/agent/linear`
     (`$LINEAR_CLI` overrides the path), plus `clankers list` and `gh`. It
     prints JSON and stages the next state. The state lives in
     `~/.local/state/linear-sweep/state.json` and holds the last run time and
     a snapshot of his open issues' states. The first run starts from
     2026-11-18 07:40 CET.
   - **`new`:** TWE notifications made by others since the last run:
     assignments, comments that mention him or are on his issues, and status
     changes.
   - **`due_or_overdue`:** his open issues due today or earlier.
   - **`out_of_sync`:** each item names the problem, matched by the TWE id in a
     clanker's name, session or worktree, or in a PR's title or branch:
     - `in_progress_without_live_clanker_or_open_pr`
     - `work_on_not_started_issue` (Triage, Backlog, Todo or Next)
     - `pr_merged_issue_not_done` (an issue in In Review or In Product Review
       after a merge is correct: Tsah's model is that only a merged PR puts
       an issue in review)
     - `closed_issue_with_open_work`
     - `unknown_twe_id`
2. If `new`, `due_or_overdue` and `out_of_sync` are all empty, post nothing,
   then run step 4.
3. Otherwise write `"$tmp/report.md"`. Tsah reads it as written, so use
   plain words with no preamble. Every issue is a markdown link with its
   plain title as the label: `[<title>](<url>)`. Don't use bare ids.
   - `## New for you`: one line each on who did what, with a short
     comment quote where it helps. Due or overdue items come first, with
     their dates.
   - `## Out of sync`: grouped by problem. Each line has the issue, what is
     wrong, and the fix offered, such as "move to In Review",
     "close the clanker" or "check whether this is still being worked on".
     Make no fixes yourself.
   - Publish the page: `url=$(publish-report linear-sweep "Linear: <n> new, <m> out of sync" "$tmp/report.md")`.
     This writes a self-contained, mobile-friendly page under `~/reports/linear-sweep/`
     and adds it to that desk's index and to `~/reports/index.html`. They're
     on the tailnet at `https://puffin.tail685506.ts.net/reports/`.
     `publish-report` is in `~/dotfiles/bin`. Each `##` section becomes a card.
   - Write `"$tmp/post.md"`:
     - The first line is `[Open the full report](<url>)`.
     - Under it, a short summary of 2–5 lines: counts, and the items most
       worth acting on today, such as anything due or overdue.
   - Post it: `python3 ~/.claude/skills/linear-sweep/post.py "Linear: <n> new, <m> out of sync" "$tmp/post.md"`.
     It prints only the HTTP status. Never print the webhook URL or the
     Authorization header.
4. `python3 ~/.claude/skills/linear-sweep/collect.py --commit`. This makes
   the staged state current. Run it only after a successful post, or after
   deciding to post nothing, so a failed post is retried next run.

Never put secrets in the report or logs. LINEAR_API_KEY in particular never
appears in output: don't echo it, `env` or `set -x`. Use `$tmp` as a fresh
directory under your scratchpad.
