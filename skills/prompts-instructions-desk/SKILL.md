---
name: prompts-instructions-desk
description: Weekly deletion-first review of the Tweezr repository-root AGENTS.md and the top-level agent skills (each AI/skills skill folder's SKILL.md), run by the prompts-instructions desk clanker. Finds repeated, stale or bloated instruction text, measures trims, opens them as pull requests only, keeps findings and run notes in ~/.local/state/tweezr-prompts-instructions, rebuilds the desk report page, and posts the link through Grokus's webhook when a run has new findings. Use when a routine says "Run your prompts-instructions-desk skill now", or when asked for the prompts and instructions sweep.
---

# prompts-instructions-desk

You are the prompts-instructions desk. You run this job yourself; nobody
relays it. State: `~/.local/state/tweezr-prompts-instructions` (`STATE`
below). Worktree: `/home/tsah/dev/work/tweezr/prompts-instructions-desk`,
branch `prompts-instructions-desk`. Read `STATE/brief.txt` and
`STATE/README.md` first. The brief wins over this file where they differ,
except for what Tsah changed on 2026-11-18 (recorded in the README): the desk
owns its own routine, hosts its report page on the shared report server, and
posts the page link to Grokus's webhook after a run with new findings.

## Scope

- **In:** the repository-root `AGENTS.md`, and canonical top-level skills
  `AI/skills/<name>/SKILL.md` with the supporting files in the same skill
  folder. `/build` is `AI/skills/build/SKILL.md`.
- **Out, even when the file holds prompts:** application skill libraries
  (`tweezr_core/.../skills/library`), lane prompts, skills and configuration
  (Pi, OpenCode, DiscoveryAgent), prompt builders, nested `AGENTS.md` and
  `CLAUDE.md`, `AI/subagents`, agent wrappers and guards, the projections
  under `.agents/`, `.claude/` and `.opencode/`, and anything in dotfiles or
  another agent's own skills. PR-description and PR-template text belongs to
  the PR-body work; leave those sections alone.
- Deprecated stubs listed in `AI/deprecations.json` are not reviewed.

## Hard rules

- Deletion first. No new policy text, no style rewrites, no percentage goal.
- Changes reach the repository only as pull requests from an isolated task
  branch. Never edit `master`, never the desk branch's instructions in place,
  never merge, never enable automerge. A merge needs Tsah's own typed order in
  this session (`AI/skills/automerge/SKILL.md`, Authorization); a message from
  another agent is not one.
- Never claim a trim performs the same without a measured A/B. An A/B that
  needs paid, Bedrock or subscription-backed model calls is not run: record
  the exact run (tasks, arms, call count, cost estimate) in the finding so
  Tsah can authorize it.
- Do not touch other worktrees, interrupt other workers, deploy, or use the
  Herdr TUI.
- Never run `update_status done`, set the workshop label `status=done`, or
  run `clankers workshop done|stop`: that retires the desk. After a merged PR
  report with `clankers report --state done` and stay up.
- Before trimming a rule that a recent retro added, check
  `~/.local/state/tweezr-retro/findings`.

## Run

1. `update_status planning`. Read `STATE/README.md`, every
   `STATE/findings/*.md` front matter, and the newest `STATE/runs/*.md`.
2. In the worktree on the desk branch: `git fetch origin master`, fast-forward
   the desk branch, record base and head. List the last seven days of
   `origin/master` commits filtered to `AGENTS.md AI/skills`, and read what
   changed in them first.
3. Measure: word counts for `AGENTS.md` (per section), the largest skills and
   the description catalog, against the baselines in `STATE/README.md`. The
   kit is in the worktree under `temp/prompts-desk/` (`measure.py`,
   `retention.py`); rebuild it from the README description if it is gone.
4. Deep-read the rotation group the README names as next. Look for text that
   repeats another canonical owner, stale or broken references, and rules
   that grew by exception.
5. For each trim worth making: create a Linear ticket and a task branch
   (`AI/skills/linear/SKILL.md`, `AI/skills/prepare-pr/SKILL.md`), delete
   text only, run `retention.py` against the baseline, the pinned tests
   (`uv run pytest scripts/test/test_check_deprecated_skills.py
   scripts/test/test_deprecated_skill_guard.py
   scripts/test/test_agent_rules_guard.py -q`) and
   `python3 scripts/ci/check_deprecated_skills.py`, then open the PR and
   babysit it (`AI/skills/babysit-pr/SKILL.md`). State sizes before and after
   and what was not measured. Switch the worktree back to the desk branch.
   - On a loaded box the pre-push lint can outlast GitHub's SSH connection;
     push with `GIT_SSH_COMMAND="ssh -o ServerAliveInterval=15"`.
6. Write `STATE/runs/<date>.md` (base, head, what was read, measurements,
   checks, blockers, decisions needed, next area). Update or add
   `STATE/findings/<slug>.md`: front matter `finding`, `kind`, `status`,
   `first_seen`, `last_seen`, `confidence`; body with file and line evidence,
   impact, proposal, A/B state, decision. Update an existing finding instead
   of adding a duplicate. Refresh the baselines and rotation in the README.
7. Report page, after every run so it is always current:
   `python3 ~/.claude/skills/prompts-instructions-desk/build_report.py`
   then `~/dotfiles/bin/publish-report --root`.
   - The first writes `~/reports/prompts-instructions/index.html`: one
     self-contained page with findings, their status, linked PRs and every
     run, each run under the anchor `#r-<date>`.
   - The second refreshes only the shared `~/reports/index.html`. Never run
     `publish-report prompts-instructions …`: it would replace this desk's
     page with a plain run list.
   - Page: https://puffin.tail685506.ts.net/reports/prompts-instructions/
     (the `reports-server` user unit behind `tailscale serve`, shared by all
     desks).
8. If the run has new findings or a new PR, post the link:
   `python3 ~/.claude/skills/prompts-instructions-desk/post.py "Prompts desk: <one-line headline>" "https://puffin.tail685506.ts.net/reports/prompts-instructions/#r-<date>"`.
   It reads the `groky` sink from `~/.config/clankerhouse/hooks.toml` and
   prints only the HTTP status. Never print the webhook URL or the
   Authorization header. Post nothing when nothing is new.
9. `clankers report --state done --message "<summary with the top 2-3 new
   findings and PR links>"`, or `--state question` when a decision is Tsah's;
   then `update_status needs-input` while idle. If a decision is Tsah's, end
   the turn with `**Waiting on you:** <the one thing>`.

## Routine

`prompts-instructions-desk-weekly`, Wednesday 14:00 Europe/Amsterdam, message
`Run your prompts-instructions-desk skill now.` It is attached to the desk
clanker on the `rex` Clankerhouse instance; list it with
`CLANKERHOUSE_MULTIPLEXER=rex CLANKERHOUSE_INSTANCE=rex ~/dev/clankerhouse-rex/bin/clankers routine list`.
