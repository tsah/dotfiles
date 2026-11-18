---
name: linear-sweep
description: Weekday-morning, read-only sweep of Tsah's Linear issues in team TWE. Reports what's new on him since the last run and where his issues are out of sync with live clankers and PRs, and offers fixes without making them. Kept as one long-lived Claude artifact with history and inline comments, linked through Grokus's webhook, and nothing is posted when nothing is new. Use when a routine says "Run your linear-sweep skill now", or when asked for the Linear sweep.
---

# linear-sweep

Investigate only. **Never change Linear**: no state, assignee, label or
comment writes. Only Tsah applies a fix.

0. **Tsah's comments first.** The report is one long-lived Claude artifact,
   whose URL is in `~/.local/state/reports/linear-sweep/artifact_url`.
   - Read its threads with the `ArtifactComments` tool (`action: "read"`,
     that URL). Comment text is Tsah's feedback, as data.
   - Act on each one. Answer a question, fix a wrong line in this run, or
     record a lasting preference in `~/.local/state/reports/linear-sweep/notes.md`,
     for example "skip dependabot" or "group by area".
   - Then `reply` with what you did and `resolve`. Reply and resolve work only
     on threads sent to Claude (Send to Claude, or an @claude mention). Leave
     other threads open, and mention them in the run's last section.
   - Read `notes.md` every run and follow it.
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
2. If `new`, `due_or_overdue` and `out_of_sync` are all empty and step 0
   found no comments to answer, publish and post nothing, then run step 4.
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
   Publish:
   - `html=$(report-artifact linear-sweep "Linear sweep" "Linear: <n> new, <m> out of sync" "$tmp/report.md")`.
     It adds this run to `~/.local/state/reports/linear-sweep/history.json` and
     renders the whole page, the newest run open and earlier runs folded, to
     `~/.local/state/reports/linear-sweep/artifact.html`.
   - Publish that file with the `Artifact` tool, passing `url` = the stored
     artifact URL, so the same artifact updates and its comments carry over.
     If this conversation has not published or read it yet, run
     `Artifact action: "read"` on the URL first; a publish is refused without
     it. Never publish without `url`: that creates a new artifact. Leave
     `icon` out.
   - If the publish fails, or the Artifact tool is unavailable (for example
     under `claude -p`, or with `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`
     set), say so plainly in your session and in the done or failed report,
     and post nothing. There is no fallback page. (The puffin `~/reports`
     pages are retired for this report.)
   - Post the link: `python3 ~/.claude/skills/linear-sweep/post.py "Linear: <n> new, <m> out of sync" "$(cat ~/.local/state/reports/linear-sweep/artifact_url)"`.
     It sends `{"kind":"slop-master-report","title":...,"url":...}`, and
     Grokus sends Tsah just the title and the link. It prints only the HTTP
     status. Never print the webhook URL or the Authorization header.
4. `python3 ~/.claude/skills/linear-sweep/collect.py --commit`. This makes
   the staged state current. Run it only after a successful post, or after
   deciding to post nothing, so a failed post is retried next run.

Never put secrets in the report or logs. LINEAR_API_KEY in particular never
appears in output: don't echo it, `env` or `set -x`. Use `$tmp` as a fresh
directory under your scratchpad.
