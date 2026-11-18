#!/usr/bin/env python3
"""Render the test-quality desk's report page from its state files.

Usage: render_report.py [STATE_DIR] [REPORTS_ROOT]
  STATE_DIR    defaults to ~/.local/state/tweezr-test-quality
  REPORTS_ROOT defaults to ~/reports (the shared report server's root)

Reads findings/*.md (front matter: finding, kind, status) and runs/*.md, looks
up every PR the findings' Decisions name with read-only `gh pr view`, and writes:
  REPORTS_ROOT/test-quality/index.html          current findings + sweep history
  REPORTS_ROOT/test-quality/runs/<date>.html    one page per sweep log
  REPORTS_ROOT/index.html                       every desk (same rule as publish-report)
Pages are self-contained (Google Fonts only). They are served on the tailnet at
https://puffin.tail685506.ts.net/reports/ by the `reports-server` user unit
that ~/dotfiles/bin/publish-report documents. Prints the desk page URL.
"""

import html
import json
import re
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

REPO = "Legacy-AI-Ltd/tweezr"
DESK = "test-quality"
BASE_URL = "https://puffin.tail685506.ts.net/reports"
STATUS_ORDER = ["open", "proposed", "accepted", "rejected"]
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
  try { localStorage.setItem('tq-filter', status); } catch (e) {}
}
chips.forEach(c => c.addEventListener('click', () => apply(c.dataset.status)));
let saved = 'all'; try { saved = localStorage.getItem('tq-filter') || 'all'; } catch (e) {}
apply(saved);
if (location.hash) { const t = document.querySelector(location.hash); if (t && t.tagName === 'DETAILS') t.open = true; }
"""


def render(state: Path) -> str:
    findings = [parse_finding(p) for p in sorted((state / "findings").glob("*.md"))]
    runs = [run_summary(p) for p in sorted((state / "runs").glob("*.md"), reverse=True)]
    prs = pr_states({n for f in findings for n in PR_RE.findall(section(f["body"], "Decisions"))})
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
        linked = sorted({n for n in PR_RE.findall(section(f["body"], "Decisions")) if n in prs}, key=int)
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
            f'<div class="meta"><a href="runs/{r["date"]}.html">Open as a page</a></div>'
            f'<div class="meta">{markdown(r["headline"]) if r["headline"] else ""}</div></summary>'
            f'<div class="card-body">{markdown(r["body"].split(chr(10), 1)[1] if chr(10) in r["body"] else "")}</div></details>'
        )
    index = " · ".join(f'<a href="#run-{r["date"]}">{r["date"]}</a>' for r in runs)

    return document("Test-Quality Desk", f"""<div class="wrap">
<header style="display:grid;gap:6px">
  <h1>Test-Quality Desk</h1>
  <div class="meta">Tweezr CI and test-suite findings · last sweep {last_run} · page built {now}</div>
  <div class="meta">Better tests, less CI and machine load. Changes ship only as draft PRs Tsah approved; nothing merges without him.</div>
</header>
<section aria-labelledby="h-findings">
  <h2 id="h-findings">Findings</h2>
  <div class="strip" role="group" aria-label="Filter by status">{''.join(chips)}</div>
  <div class="list" style="margin-top:12px">{''.join(cards)}</div>
</section>
<section class="runs" aria-labelledby="h-runs">
  <h2 id="h-runs">Sweeps</h2>
  <div class="meta" style="margin-bottom:10px">{index}</div>
  <div class="list">{''.join(run_cards)}</div>
</section>
</div>
<script>{SCRIPT}</script>""")


def document(title: str, body: str) -> str:
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>{html.escape(title)}</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;600&family=Space+Grotesk:wght@600&display=swap">
<style>*{{box-sizing:border-box}} body{{margin:0}} [hidden]{{display:none!important}} {CSS}</style>
</head><body>{body}</body></html>
"""


def run_page(run: dict[str, str]) -> str:
    rest = run["body"].split("\n", 1)[1] if "\n" in run["body"] else ""
    return document(
        f"Test-quality sweep {run['date']}",
        f'''<div class="wrap"><header style="display:grid;gap:6px">
<div class="meta"><a href="../../">All reports</a> · <a href="../">Test-Quality Desk</a></div>
<h1>{inline(run["title"])}</h1></header><section class="card-body" style="padding:0">{markdown(rest)}</section></div>''',
    )


def rebuild_root_index(root: Path) -> None:
    """Same listing rule as ~/dotfiles/bin/publish-report: every desk directory with an index.html."""
    desks = sorted(d for d in root.iterdir() if (d / "index.html").exists())
    items = "".join(f'<li><a href="{d.name}/">{html.escape(d.name)}</a></li>' for d in desks)
    (root / "index.html").write_text(document(
        "Reports",
        f'''<div class="wrap"><header style="display:grid;gap:6px"><div class="meta">puffin</div><h1>Reports</h1>
<div class="meta">{len(desks)} desks</div></header><ul>{items}</ul></div>''',
    ))


def main() -> None:
    state = Path(sys.argv[1]).expanduser() if len(sys.argv) > 1 else Path.home() / ".local/state/tweezr-test-quality"
    root = Path(sys.argv[2]).expanduser() if len(sys.argv) > 2 else Path.home() / "reports"
    desk_dir = root / DESK
    (desk_dir / "runs").mkdir(parents=True, exist_ok=True)
    for path in (state / "runs").glob("*.md"):
        (desk_dir / "runs" / f"{path.stem}.html").write_text(run_page(run_summary(path)))
    (desk_dir / "index.html").write_text(render(state))
    rebuild_root_index(root)
    print(f"{BASE_URL}/{DESK}/")


if __name__ == "__main__":
    main()
