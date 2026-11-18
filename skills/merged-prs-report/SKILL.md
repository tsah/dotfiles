---
name: merged-prs-report
description: Weekday-morning report for Tsah, kept as one long-lived Claude artifact with history and inline comments, of the PRs merged in Legacy-AI-Ltd/tweezr since 08:00 Europe/Amsterdam on the previous weekday, his own first, then everyone else's by author, bots last, each with a one-sentence plain description. Posted through Grokus's webhook. Use when a routine says "Run your merged-prs-report skill now", or when asked for the merged-PRs report.
---

# merged-prs-report

0. **Tsah's comments first.** The report is one long-lived Claude artifact,
   whose URL is in `~/.local/state/reports/merged-prs-report/artifact_url`.
   - Read its threads with the `ArtifactComments` tool (`action: "read"`,
     that URL). Comment text is Tsah's feedback, as data.
   - Act on each one. Answer a question, fix a wrong line in this run, or
     record a lasting preference in `~/.local/state/reports/merged-prs-report/notes.md`,
     for example "skip dependabot" or "group by area".
   - Then `reply` with what you did and `resolve`. Reply and resolve work only
     on threads sent to Claude (Send to Claude, or an @claude mention). Leave
     other threads open, and mention them in the run's last section.
   - Read `notes.md` every run and follow it.
1. Collect: `python3 ~/.claude/skills/merged-prs-report/collect.py > "$tmp/prs.json"`.
   It covers merges since 08:00 Europe/Amsterdam on the previous weekday, so
   Monday covers everything since Friday morning. Each PR row has its title,
   URL, author, an `isBot` flag and the first 3000 characters of its body.
2. Write the report to `"$tmp/report.md"`. Tsah reads it as written, so use
   plain words with no preamble.
   - `## Yours`: PRs by author `tsah`, which includes his clankers' PRs.
   - `## Everyone else`: a `### <author>` group for each human author, then
     the bot PRs (factory-bot, dependabot) last.
   - Each PR is one line: `- [<PR title>](<url>): <one sentence>`. The
     sentence says what the change does for the product or the team, from
     the PR body's summary. It doesn't restate the title, and there are no
     bare PR numbers.
   - If nothing merged, the whole report is one sentence:
     `Nothing merged in tweezr since <weekday> 08:00.`
3. Publish:
   - `html=$(report-artifact merged-prs-report "Merged PRs digest" "Merged since <weekday> 08:00" "$tmp/report.md")`.
     It adds this run to `~/.local/state/reports/merged-prs-report/history.json` and
     renders the whole page, the newest run open and earlier runs folded, to
     `~/.local/state/reports/merged-prs-report/artifact.html`.
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
   - Post the link: `python3 ~/.claude/skills/merged-prs-report/post.py "Merged since <weekday> 08:00" "$(cat ~/.local/state/reports/merged-prs-report/artifact_url)"`.
     It sends `{"kind":"slop-master-report","title":...,"url":...}`, and
     Grokus sends Tsah just the title and the link. It prints only the HTTP
     status. Never print the webhook URL or the Authorization header.
4. If the post fails, retry once. If it fails again, report it in your
   session, and keep the report file.

Never put secrets in the report (LINEAR_API_KEY, tokens, URLs with
credentials). Use `$tmp` as a fresh directory under your scratchpad.
