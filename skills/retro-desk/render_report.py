#!/usr/bin/env python3
"""Render the retro desk's always-current report page from its state files.

Usage: render_report.py [STATE_DIR] [OUT_HTML]
  STATE_DIR defaults to ~/.local/state/tweezr-retro
  OUT_HTML  defaults to ~/reports/retro-desk/index.html (served on the tailnet)

Reads findings/*.md (front matter: finding, kind, status), runs/*.md and
cursors/*.md, plus ~/reports/retro-desk/runs.json (the per-run pages written by
publish-report). Looks up the PRs each finding's Decisions name, by number or
by hand-off branch, with read-only `gh`, and writes one self-contained,
mobile-friendly HTML page. Adapted from the test-quality desk's renderer.
"""

import html
import json
import re
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

REPO = "Legacy-AI-Ltd/tweezr"
# Proposed first: those wait on Tsah.
STATUS_ORDER = ["proposed", "open", "accepted", "rejected"]
PR_RE = re.compile(r"(?:https://github\.com/Legacy-AI-Ltd/tweezr/pull/|#)(\d{4,5})\b")


def parse_finding(path: Path) -> dict[str, str]:
    text = path.read_text()
    meta: dict[str, str] = {}
    body = text
    if text.startswith("---\n"):
        head, _, body = text[4:].partition("\n---\n")
        for line in head.splitlines():
            key, sep, value = line.partition(":")
            if sep:
                meta[key.strip()] = value.strip()
    meta["slug"] = path.stem
    meta["body"] = body
    return meta


def section(body: str, name: str) -> str:
    match = re.search(rf"^## {re.escape(name)}\s*$(.*?)(?=^## |\Z)", body, re.M | re.S)
    return match.group(1).strip() if match else ""


def inline(text: str) -> str:
    out = html.escape(text, quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"\[\[([a-z0-9-]+)\]\]", r'<a href="#f-\1">\1</a>', out)
    out = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', out)
    out = re.sub(r"(?<![\"'>=])(https?://[^\s<)]+)", r'<a href="\1">\1</a>', out)
    return out


def markdown(text: str) -> str:
    """Headings, nested bullets, paragraphs, fenced code and pipe tables."""
    lines = text.splitlines()
    out: list[str] = []
    depth_stack: list[int] = []
    i = 0

    def close_lists(to: int) -> None:
        while depth_stack and depth_stack[-1] >= to:
            depth_stack.pop()
            out.append("</li></ul>")

    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            close_lists(0)
            block = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                block.append(lines[i])
                i += 1
            out.append(f"<pre><code>{html.escape(chr(10).join(block))}</code></pre>")
        elif line.startswith("|"):
            close_lists(0)
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                if not all(re.fullmatch(r":?-+:?", c) for c in cells if c):
                    rows.append(cells)
                i += 1
            i -= 1
            head, *rest = rows or [[]]
            table = "<tr>" + "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr>"
            table += "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>" for r in rest)
            out.append(f'<div class="scroll"><table>{table}</table></div>')
        elif m := re.match(r"^(#{1,4}) (.*)", line):
            close_lists(0)
            level = min(len(m.group(1)) + 2, 6)
            out.append(f"<h{level}>{inline(m.group(2))}</h{level}>")
        elif m := re.match(r"^(\s*)(?:[-*]|\d+\.) (.*)", line):
            depth = len(m.group(1)) // 2
            if depth_stack and depth_stack[-1] == depth:
                out.append("</li><li>")
            elif depth_stack and depth_stack[-1] > depth:
                close_lists(depth + 1)
                if depth_stack and depth_stack[-1] == depth:
                    out.append("</li><li>")
                else:
                    depth_stack.append(depth)
                    out.append("<ul><li>")
            else:
                depth_stack.append(depth)
                out.append("<ul><li>")
            out.append(inline(m.group(2)))
        elif line.strip() == "":
            pass
        elif depth_stack and line.startswith(" "):
            out.append(" " + inline(line.strip()))
        else:
            close_lists(0)
            out.append(f"<p>{inline(line)}</p>")
        i += 1
    close_lists(0)
    return "\n".join(out)


BRANCH_RE = re.compile(r"branch `?([A-Za-z0-9][\w./-]+?)`?(?=[,;.)\s]|$)")
# Hand-offs are recorded as "Workshop <name> (...)"; the Workshop name is its branch.
WORKSHOP_RE = re.compile(r"Workshop `?([a-z0-9][\w./-]+?)`?(?=[,;.)\s]|$)")


def handoff_branches(body: str) -> set[str]:
    decisions = section(body, "Decisions")
    return set(BRANCH_RE.findall(decisions)) | set(WORKSHOP_RE.findall(decisions))


def branch_prs(branches: set[str]) -> dict[str, str]:
    """Hand-off branch -> PR number, for Decisions that name a branch, not a PR."""
    found: dict[str, str] = {}
    for branch in sorted(branches):
        result = subprocess.run(
            ["gh", "pr", "list", "-R", REPO, "--head", branch, "--state", "all", "--json", "number", "--limit", "1"],
            capture_output=True, text=True, check=False,
        )
        if result.returncode == 0 and (rows := json.loads(result.stdout)):
            found[branch] = str(rows[0]["number"])
    return found


def linked_numbers(body: str, by_branch: dict[str, str]) -> set[str]:
    decisions = section(body, "Decisions")
    nums = set(PR_RE.findall(decisions))
    nums |= {by_branch[b] for b in handoff_branches(body) if b in by_branch}
    return nums


def pr_states(numbers: set[str]) -> dict[str, dict[str, str]]:
    states: dict[str, dict[str, str]] = {}
    for number in sorted(numbers):
        result = subprocess.run(
            ["gh", "pr", "view", number, "-R", REPO, "--json", "number,title,state,isDraft,url,mergedAt"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)
            state = data["state"].lower()
            if state == "open" and data["isDraft"]:
                state = "draft"
            states[number] = {"state": state, "title": data["title"], "url": data["url"]}
    return states


def run_summary(path: Path) -> dict[str, str]:
    text = path.read_text()
    title_match = re.search(r"^# (.*)", text, re.M)
    heading = re.search(r"^## (Headline[^\n]*)", text, re.M)
    headline = section(text, heading.group(1)) if heading else ""
    return {
        "date": path.stem,
        "title": title_match.group(1) if title_match else path.stem,
        "headline": headline,
        "body": text,
    }


CSS = """
/* Layout: one reading column; summary strip, then findings grouped by status, then run history. */
:root {
  --bg: #f6f7f5; --surface: #ffffff; --fg: #1c2321; --muted: #5d6965; --line: #dfe4e1;
  --accent: #23756b; --open: #b45309; --proposed: #6d4fc2; --accepted: #15803d; --rejected: #6b7280;
  --draft: #6b7280; --merged: #6d4fc2; --closed: #b91c1c; --code-bg: #eef1ef;
  --font-body: "IBM Plex Sans", system-ui, sans-serif; --font-head: "Space Grotesk", system-ui, sans-serif;
  --font-mono: "IBM Plex Mono", ui-monospace, monospace;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg: #121715; --surface: #1a201e; --fg: #e3e8e5; --muted: #98a59f; --line: #2b3431;
  --accent: #5cc2b3; --open: #f59e0b; --proposed: #a78bfa; --accepted: #4ade80; --rejected: #9ca3af;
  --draft: #9ca3af; --merged: #a78bfa; --closed: #f87171; --code-bg: #232b28; color-scheme: dark; } }
:root[data-theme="dark"] {
  --bg: #121715; --surface: #1a201e; --fg: #e3e8e5; --muted: #98a59f; --line: #2b3431;
  --accent: #5cc2b3; --open: #f59e0b; --proposed: #a78bfa; --accepted: #4ade80; --rejected: #9ca3af;
  --draft: #9ca3af; --merged: #a78bfa; --closed: #f87171; --code-bg: #232b28; color-scheme: dark; }
body { background: var(--bg); color: var(--fg); font: 15px/1.55 var(--font-body); }
.wrap { max-width: 860px; margin: 0 auto; padding-block: 28px 56px;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px));
  display: grid; gap: 28px; }
h1, h2, h3 { font-family: var(--font-head); text-wrap: balance; margin: 0; line-height: 1.2; }
h1 { font-size: 1.75rem; } h2 { font-size: 1.2rem; margin-bottom: 10px; }
h3, h4, h5, h6 { font-size: 0.95rem; margin: 14px 0 4px; }
a { color: var(--accent); } a:focus-visible, summary:focus-visible, button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
code { font-family: var(--font-mono); font-size: 0.85em; background: var(--code-bg); padding: 1px 4px; border-radius: 4px; overflow-wrap: anywhere; }
pre { background: var(--code-bg); padding: 10px; border-radius: 6px; overflow-x: auto; }
pre code { padding: 0; }
.meta { color: var(--muted); font-size: 0.875rem; }
.strip { display: flex; flex-wrap: wrap; gap: 8px; }
.chip { font: 600 0.75rem/1 var(--font-body); letter-spacing: 0.04em; text-transform: uppercase;
  padding: 6px 10px; border-radius: 999px; border: 1px solid currentColor; background: transparent; cursor: pointer; color: var(--muted); }
.chip[aria-pressed="true"] { color: var(--fg); background: var(--surface); }
.chip .n { font-variant-numeric: tabular-nums; margin-left: 4px; }
.s-open { color: var(--open); } .s-proposed { color: var(--proposed); } .s-accepted { color: var(--accepted); } .s-rejected { color: var(--rejected); }
.pr-draft { color: var(--draft); } .pr-merged { color: var(--merged); } .pr-closed { color: var(--closed); } .pr-open { color: var(--accepted); }
.list { display: grid; gap: 10px; }
details.card { background: var(--surface); border: 1px solid var(--line); border-radius: 8px; }
details.card > summary { list-style: none; cursor: pointer; padding: 12px 14px; display: grid; gap: 6px; }
details.card > summary::-webkit-details-marker { display: none; }
details.card[open] > summary { border-bottom: 1px solid var(--line); }
.card-body { padding: 4px 14px 14px; min-width: 0; overflow-wrap: anywhere; }
.row { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; }
.tag { font: 600 0.7rem/1 var(--font-body); letter-spacing: 0.05em; text-transform: uppercase; padding: 4px 7px; border-radius: 4px; border: 1px solid currentColor; }
.slug { font-family: var(--font-mono); font-size: 0.78rem; color: var(--muted); }
.claim { font-size: 0.95rem; }
ul { padding-left: 20px; margin: 4px 0; } li { margin: 2px 0; }
.scroll { overflow-x: auto; } table { border-collapse: collapse; font-size: 0.82rem; font-variant-numeric: tabular-nums; }
th, td { border-bottom: 1px solid var(--line); padding: 4px 8px; text-align: left; vertical-align: top; }
.runs summary .claim { font-family: var(--font-head); font-weight: 600; }
@media (prefers-reduced-motion: no-preference) { details.card > summary { transition: background 0.15s; } }
"""

SCRIPT = """
const chips = document.querySelectorAll('.chip[data-status]');
function apply(status) {
  chips.forEach(c => c.setAttribute('aria-pressed', String(c.dataset.status === status)));
  document.querySelectorAll('[data-finding]').forEach(el => { el.hidden = status !== 'all' && el.dataset.finding !== status; });
  try { localStorage.setItem('retro-filter', status); } catch (e) {}
}
chips.forEach(c => c.addEventListener('click', () => apply(c.dataset.status)));
let saved = 'all'; try { saved = localStorage.getItem('retro-filter') || 'all'; } catch (e) {}
apply(saved);
if (location.hash) { const t = document.querySelector(location.hash); if (t && t.tagName === 'DETAILS') t.open = true; }
"""


def render(state: Path) -> str:
    findings = [parse_finding(p) for p in sorted((state / "findings").glob("*.md"))]
    runs = [run_summary(p) for p in sorted((state / "runs").glob("*.md"), reverse=True)]
    by_branch = branch_prs({b for f in findings for b in handoff_branches(f["body"])})
    prs = pr_states({n for f in findings for n in linked_numbers(f["body"], by_branch)})
    workshops = len(list((state / "cursors").glob("*.md")))
    pages_file = Path.home() / "reports" / "retro-desk" / "runs.json"
    pages = json.loads(pages_file.read_text()) if pages_file.exists() else []
    counts = {s: sum(f.get("status") == s for f in findings) for s in STATUS_ORDER}
    findings.sort(key=lambda f: (STATUS_ORDER.index(f.get("status", "open")) if f.get("status") in STATUS_ORDER else 9, f["slug"]))
    now = datetime.now(UTC).strftime("%Y-%m-%d %H:%M UTC")
    last_run = runs[0]["date"] if runs else "none"

    chips = [f'<button class="chip" data-status="all" aria-pressed="true">All<span class="n">{len(findings)}</span></button>']
    chips += [f'<button class="chip s-{s}" data-status="{s}" aria-pressed="false">{s}<span class="n">{counts[s]}</span></button>' for s in STATUS_ORDER]

    cards = []
    for f in findings:
        status = f.get("status", "open")
        # Only PRs the desk's own decisions name; PRs cited as evidence stay in the text.
        linked = sorted({n for n in linked_numbers(f["body"], by_branch) if n in prs}, key=int)
        pr_tags = "".join(
            f'<a class="tag pr-{prs[n]["state"]}" href="{prs[n]["url"]}" title="{html.escape(prs[n]["title"])}">#{n} {prs[n]["state"]}</a>'
            for n in linked
        )
        parts = "".join(
            f"<h3>{name}</h3>{markdown(section(f['body'], name))}" for name in ("Proposal", "Decisions", "Occurrences") if section(f["body"], name)
        )
        cards.append(
            f'<details class="card" id="f-{f["slug"]}" data-finding="{status}"><summary>'
            f'<div class="row"><span class="tag s-{status}">{status}</span><span class="tag" style="color:var(--muted)">{html.escape(f.get("kind", ""))}</span>{pr_tags}</div>'
            f'<div class="claim">{inline(f.get("finding", f["slug"]))}</div><div class="slug">{f["slug"]}</div>'
            f'</summary><div class="card-body">{parts}</div></details>'
        )

    run_cards = []
    for r in runs:
        run_cards.append(
            f'<details class="card" id="run-{r["date"]}"><summary><div class="claim">{inline(r["title"])}</div>'
            f'<div class="meta">{markdown(r["headline"]) if r["headline"] else ""}</div></summary>'
            f'<div class="card-body">{markdown(r["body"].split(chr(10), 1)[1] if chr(10) in r["body"] else "")}</div></details>'
        )
    index = " · ".join(f'<a href="#run-{r["date"]}">{r["date"]}</a>' for r in runs)
    page_links = "".join(
        f'<li><a href="runs/{html.escape(p["file"])}">{html.escape(p["title"])}</a> <span class="meta">{html.escape(p["when"])}</span></li>'
        for p in reversed(pages)
    )

    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Retro Desk</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;600&family=Space+Grotesk:wght@600&display=swap">
<style>{CSS}</style></head><body>
<div class="wrap">
<header style="display:grid;gap:6px">
  <div class="meta"><a href="../">All reports</a></div>
  <h1>Retro Desk</h1>
  <div class="meta">Lessons from finished tweezr Workshops · {workshops} Workshops read · last run {last_run} · page built {now}</div>
  {f'<div class="meta">Latest run: <a href="runs/{html.escape(pages[-1]["file"])}">{html.escape(pages[-1]["title"])}</a> · <a href="#h-runs">all runs</a></div>' if pages else ''}
  <div class="meta">Findings about the environment agents work in. Proposals change only through a hand-off Tsah approves; nothing merges without him.</div>
</header>
<section aria-labelledby="h-findings">
  <h2 id="h-findings">Findings</h2>
  <div class="strip" role="group" aria-label="Filter by status">{''.join(chips)}</div>
  <div class="list" style="margin-top:12px">{''.join(cards)}</div>
</section>
<section class="runs" aria-labelledby="h-runs">
  <h2 id="h-runs">Runs</h2>
  <div class="meta" style="margin-bottom:10px">{index}</div>
  {f'<ul style="margin-bottom:10px">{page_links}</ul>' if page_links else ''}
  <div class="list">{''.join(run_cards)}</div>
</section>
</div>
<script>{SCRIPT}</script></body></html>
"""


def main() -> None:
    state = Path(sys.argv[1]).expanduser() if len(sys.argv) > 1 else Path.home() / ".local/state/tweezr-retro"
    out = Path(sys.argv[2]).expanduser() if len(sys.argv) > 2 else Path.home() / "reports" / "retro-desk" / "index.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render(state))
    print(out)


if __name__ == "__main__":
    main()
