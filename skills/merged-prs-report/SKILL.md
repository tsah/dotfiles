---
name: merged-prs-report
description: Weekday-morning report to Tsah of the PRs merged in Legacy-AI-Ltd/tweezr since 08:00 Europe/Amsterdam on the previous weekday, his own first, then everyone else's by author, bots last, each with a one-sentence plain description. Posted through Grokus's webhook. Use when a routine says "Run your merged-prs-report skill now", or when asked for the merged-PRs report.
---

# merged-prs-report

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
3. Publish the page: `url=$(publish-report merged-prs "Merged since <weekday> 08:00" "$tmp/report.md")`.
   This writes a self-contained, mobile-friendly page under `~/reports/merged-prs/`
   and adds it to that desk's index and to `~/reports/index.html`. Tsah opens
   them on the tailnet at `https://puffin.tail685506.ts.net/reports/`.
   `publish-report` is in `~/dotfiles/bin`; its docstring lists the
   markdown it supports. Each `##` section becomes a card.
4. Write `"$tmp/post.md"` for the webhook:
   - The first line is `[Open the full report](<url>)`.
   - Under it, a short text summary of 2–5 lines: how many merged, yours
     versus others, and the one or two changes most worth his attention.
   Post it: `python3 ~/.claude/skills/merged-prs-report/post.py "Merged since <weekday> 08:00" "$tmp/post.md"`.
   The script reads the "groky" sink from `~/.config/clankerhouse/hooks.toml`
   and prints only the HTTP status. Never print the URL or the
   Authorization header.
5. If the post fails, retry once. If it fails again, report it in your
   session, and keep the report file.

Never put secrets in the report (LINEAR_API_KEY, tokens, URLs with
credentials). Use `$tmp` as a fresh directory under your scratchpad.
