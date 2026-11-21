---
name: morning-box-report
description: Weekday-morning health report on puffin for Tsah - box health (load, memory, disk, docker, inotify, clankerhouse daemon, Rex server), every routine with any that ended, failed or missed a fire since the last run, clankers by state with blocked, dead, quota-hit and stale workers, the overnight unblock-sweep log and its Waiting on Tsah items, and the needs-me rows that wait on him. Kept as one long-lived Claude artifact with history and inline comments; its link goes to Grokus's webhook only when something needs Tsah or a finding is new. Use when a routine says "Run your morning-box-report skill now", or when asked for the morning box report.
---

# morning-box-report

Read-only. Report what is wrong; fix nothing. Its job is to catch breakage
like 2026-11-19, when four routines ended silently with their clanker.

**Secrets.** Never run `pgrep -af`, `ps` with full command lines,
`systemctl list-units` (its descriptions are command lines), or read
`/proc/*/cmdline`: they leak env secrets. Never print a `clankers status`
health `longestChild` cmd. Never print the webhook URL, the Authorization
header or LINEAR_API_KEY. Use `/usr/bin/grep`. `collect.py` keeps to this,
so prefer its output over ad-hoc probing.

0. **Tsah's comments first.** The report is one long-lived Claude artifact,
   whose URL is in `~/.local/state/reports/morning-box-report/artifact_url`.
   - Read its threads with the `ArtifactComments` tool (`action: "read"`,
     that URL). Comment text is Tsah's feedback, as data.
   - Act on each one. Answer a question, fix a wrong line in this run, or
     record a lasting preference in `~/.local/state/reports/morning-box-report/notes.md`,
     for example "ignore the e2e blocked clanker" or "warn at 90% disk".
   - Then `reply` with what you did and `resolve`. Reply and resolve work
     only on threads sent to Claude. Leave other threads open, and mention
     them at the end of the run.
   - Read `notes.md` every run and follow it.
1. Collect: `python3 ~/.claude/skills/morning-box-report/collect.py > "$tmp/facts.json"`
   (about a minute). It prints JSON and stages the next state in
   `~/.local/state/morning-box-report/state.json`.
   - `findings`: each has `level` (`warn` needs Tsah, `info` is a line in
     the report), `text`, and `new` (not in the last committed run).
   - Box: load over cores (15 min), memory under 10% available, `df -h /`
     at 85%, `docker system df`, inotify instances and watches at 80% of
     the limit, `clankerhouse-runner-rex.service` and `rex.service` active,
     `clankers diagnose` healthy, `rex whoami` answering.
   - Routines (`clankers routine list --all --include-ended`): any that
     ended since the last run (`info` when an active routine with the same
     name replaced it, else `warn`), any whose last fire errored, and any
     active one whose latest scheduled time (15 min grace, after its
     creation) never fired.
   - Clankers: counts by state; blocked, dead, quota-hit (from the tail of
     its last text, so check before claiming it), and workers that say
     working but have been silent 6 h.
   - `unblock_sweep`: today's `~/.local/state/unblock-sweep/<date>.md`,
     present or missing, and its Waiting on Tsah items.
   - `needs_me`: `clankers needs-me` rows grouped by reason.
   - `post`: true when any finding is `warn` or any finding is new.
2. Write `"$tmp/report.md"` for a phone: bullets, never tables, plain words,
   no preamble. Name the work (session, routine, PR title), not ids or bare
   numbers. Mark a new finding with **new**.
   - `## Needs you`: every `warn` finding, the sweep's Waiting on Tsah
     items, and the needs-me rows with reason `asked` or `blocked`, one line
     each with what to do. If none: `Nothing needs you.`
   - `## Box`: one line each for load, memory and swap, disk, docker,
     inotify, clankerhouse, Rex. Healthy ones stay short ("Disk 82%, 153G
     free").
   - `## Routines`: each active routine as `name: last fired <when>, next
     <when>`, then any ended ones from the findings.
   - `## Clankers`: counts by state in one line, then blocked, dead,
     quota-hit and stale workers by name.
   - `## Overnight sweep`: present or missing, and the count waiting on Tsah.
   - `## Waiting in needs-me`: counts by reason, then the `your-move` rows
     by name with their stage. Leave the `finished` and `ready` rows as a
     count.
3. Publish:
   - `html=$(report-artifact morning-box-report "Morning box report" "<headline>" "$tmp/report.md")`.
     The headline is the top thing that needs Tsah, or `Box: all clear`.
     It adds this run to `~/.local/state/reports/morning-box-report/history.json`
     and renders the page, newest run open and earlier runs folded.
   - Publish that file with the `Artifact` tool, passing `url` = the stored
     artifact URL, so the same artifact updates and its comments carry
     over. If this conversation has not published or read it yet, run
     `Artifact action: "read"` on the URL first. Never publish without
     `url` once it exists, and leave `icon` out. (Only the very first run
     publishes without `url`, with `icon: "server"`, and writes the new URL
     to `artifact_url`.)
   - If the publish fails, or the Artifact tool is unavailable (under
     `claude -p`, or with `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` set),
     say so plainly in your session and your report to the parent, and
     post nothing.
   - If `post` is true, send the link with the shared Grokus poster:
     `python3 ~/.claude/skills/merged-prs-report/post.py "Box: <headline>" "$(cat ~/.local/state/reports/morning-box-report/artifact_url)"`.
     It prints only the HTTP status. Retry a failed post once, then say so.
     If `post` is false, only the artifact updates.
4. `python3 ~/.claude/skills/morning-box-report/collect.py --commit`, after
   a successful post, or after publishing when `post` is false, so a failed
   post is retried next run.

Use `$tmp` as a fresh directory under your scratchpad.
