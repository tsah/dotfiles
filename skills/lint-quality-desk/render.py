#!/usr/bin/env python3
"""Render the lint-quality desk's state into one self-contained Claude artifact page.

Usage: render.py OUT_FILE [--state DIR] [--no-gh]

Reads findings/*.md and runs/*.md from the desk state directory and writes one
HTML file (no <html>/<head>/<body>: the Artifact tool wraps it) holding the
findings by status, the desk's PRs with live state, and every run log, newest
first. The desk republishes this file to the same artifact URL each run, so the
history lives inside the one artifact. Live PR state comes from `gh pr view`
(read-only); --no-gh skips it.
"""

import argparse
import html
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = "Legacy-AI-Ltd/tweezr"
STATUS_ORDER = ["proposed", "accepted", "open", "rejected"]
STATUS_LABEL = {
    "proposed": "Approved, PR open",
    "accepted": "Accepted",
    "open": "Waiting on a decision",
    "rejected": "Rejected",
}
# The desk's own PRs are written as full URLs; a bare "#1234" is evidence (a past fix), not a link.
PR_RE = re.compile(r"https://github\.com/Legacy-AI-Ltd/tweezr/pull/(\d+)")


def parse_finding(path: Path) -> dict:
    text = path.read_text()
    match = re.match(r"---\n(.*?)\n---\n(.*)", text, re.S)
    if not match:
        raise SystemExit(f"{path}: no front matter")
    meta: dict[str, str] = {}
    for line in match.group(1).splitlines():
        key, _, value = line.partition(":")
        meta[key.strip()] = value.strip()
    for key in ("finding", "kind", "status"):
        if key not in meta:
            raise SystemExit(f"{path}: front matter lacks {key}")
    if meta["status"] not in STATUS_ORDER:
        raise SystemExit(f"{path}: unknown status {meta['status']!r}")
    body = match.group(2)
    prs = sorted({int(n) for n in PR_RE.findall(body)})
    return {"slug": path.stem, **meta, "body": body, "prs": prs}


def pr_states(numbers: set[int]) -> dict[int, dict]:
    states = {}
    for number in sorted(numbers):
        out = subprocess.run(
            ["gh", "pr", "view", str(number), "-R", REPO, "--json", "number,title,state,isDraft,url,mergedAt"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        states[number] = json.loads(out)
    return states


# --- a small Markdown subset: headings, nested lists, paragraphs, code, bold, links ---

def inline(text: str, slugs: set[str]) -> str:
    parts = re.split(r"(`[^`]+`)", text)
    out = []
    for part in parts:
        if part.startswith("`") and part.endswith("`") and len(part) > 1:
            out.append(f"<code>{html.escape(part[1:-1])}</code>")
            continue
        s = html.escape(part, quote=False)
        s = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', s)
        s = re.sub(r"(?<![\"'>])(https?://[^\s<)]+)", r'<a href="\1">\1</a>', s)
        s = re.sub(
            r"\[\[([a-z0-9-]+)\]\]",
            lambda m: f'<a href="#{m.group(1)}">{m.group(1)}</a>' if m.group(1) in slugs else m.group(1),
            s,
        )
        s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
        out.append(s)
    return "".join(out)


def markdown(text: str, slugs: set[str], heading_shift: int = 0) -> str:
    out: list[str] = []
    stack: list[tuple[int, str]] = []  # (indent, tag)
    para: list[str] = []
    in_code = False

    def flush_para() -> None:
        if para:
            out.append(f"<p>{inline(' '.join(para), slugs)}</p>")
            para.clear()

    def close_lists(indent: int = -1) -> None:
        while stack and stack[-1][0] > indent:
            out.append(f"</li></{stack.pop()[1]}>")

    for raw in text.splitlines():
        if raw.strip().startswith("```"):
            flush_para()
            close_lists()
            out.append("</code></pre>" if in_code else "<pre><code>")
            in_code = not in_code
            continue
        if in_code:
            out.append(html.escape(raw))
            continue
        heading = re.match(r"(#{1,6})\s+(.*)", raw)
        item = re.match(r"(\s*)([-*]|\d+\.)\s+(.*)", raw)
        if heading:
            flush_para()
            close_lists()
            level = min(6, len(heading.group(1)) + heading_shift)
            out.append(f"<h{level}>{inline(heading.group(2), slugs)}</h{level}>")
        elif item:
            flush_para()
            indent = len(item.group(1))
            tag = "ol" if item.group(2)[0].isdigit() else "ul"
            if stack and stack[-1][0] == indent:
                out.append("</li><li>")
            elif stack and stack[-1][0] > indent:
                close_lists(indent)
                out.append("</li><li>")
            else:
                out.append(f"<{tag}><li>")
                stack.append((indent, tag))
            out.append(inline(item.group(3), slugs))
        elif not raw.strip():
            flush_para()
            close_lists()
        elif stack:
            out.append(" " + inline(raw.strip(), slugs))
        else:
            para.append(raw.strip())
    flush_para()
    close_lists()
    if in_code:
        out.append("</code></pre>")
    return "\n".join(out)



CSS = """
/* Layout: one reading column; summary tiles, then findings grouped by status, then PRs and run history. */
:root{--bg:#f5f7f8;--surface:#ffffff;--text:#16212b;--muted:#5b6873;--line:#dde3e8;--accent:#1d6f8f;
--ok:#2c7a4b;--warn:#9a6400;--info:#2557a7;--bad:#a23a3a;--chip:#e9eef2;--code:#eef2f5;
--sans:"IBM Plex Sans",ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;
--mono:"IBM Plex Mono",ui-monospace,SFMono-Regular,Menlo,monospace}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#11171c;--surface:#192229;--text:#e4eaef;
--muted:#93a1ad;--line:#2a3640;--accent:#5fb3d3;--ok:#6cc08f;--warn:#e0b050;--info:#86a9ec;--bad:#e59393;
--chip:#22303a;--code:#1f2a33;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#11171c;--surface:#192229;--text:#e4eaef;--muted:#93a1ad;--line:#2a3640;
--accent:#5fb3d3;--ok:#6cc08f;--warn:#e0b050;--info:#86a9ec;--bad:#e59393;--chip:#22303a;--code:#1f2a33;color-scheme:dark}
*{box-sizing:border-box}
body{background:var(--bg);color:var(--text);font:15px/1.55 var(--sans);overflow-wrap:anywhere;
padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px))}
main{max-width:860px;margin:0 auto;padding-block:28px 64px}
h1{font:600 1.65rem/1.2 var(--sans);margin:0 0 4px;text-wrap:balance}
.sub{color:var(--muted);font-size:.9rem;margin:0}
nav.top{display:flex;gap:16px;flex-wrap:wrap;margin-top:14px;font-size:.9rem}
a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}
a:focus-visible,summary:focus-visible{outline:2px solid var(--accent);outline-offset:2px;border-radius:6px}
h2{font:600 1.1rem/1.3 var(--sans);margin:36px 0 12px;padding-bottom:6px;border-bottom:1px solid var(--line);text-wrap:balance}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px;margin-top:22px}
.stat{background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:12px 14px}
.stat b{display:block;font:600 1.5rem/1.1 var(--mono);font-variant-numeric:tabular-nums}
.stat span{color:var(--muted);font-size:.8rem}
.group{display:grid;gap:10px}
.card{background:var(--surface);border:1px solid var(--line);border-radius:10px;min-width:0}
.card>summary{list-style:none;cursor:pointer;padding:14px 16px}.card>summary::-webkit-details-marker{display:none}
.card>summary .slug{font:600 .92rem/1.4 var(--mono)}.card>summary p{margin:6px 0 0;color:var(--muted);font-size:.92rem}
.card[open]>summary{border-bottom:1px solid var(--line)}
.body{padding:4px 16px 14px;font-size:.93rem;min-width:0}.body h3,.body h4{font-size:.98rem;margin:18px 0 6px}
.body ul,.body ol{padding-left:20px}.body li{margin:3px 0}
.chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px}
.chip{display:inline-block;font:500 .74rem/1.6 var(--sans);padding:1px 9px;border-radius:999px;background:var(--chip);color:var(--muted);white-space:nowrap}
.chip.proposed,.chip.ready{color:var(--info)}.chip.accepted,.chip.merged{color:var(--ok)}
.chip.open{color:var(--warn)}.chip.rejected,.chip.closed{color:var(--bad)}
code{font:.85em var(--mono);background:var(--code);padding:1px 5px;border-radius:4px}
pre{background:var(--code);padding:12px;border-radius:8px;overflow-x:auto}pre code{padding:0;background:none}
.list{list-style:none;padding:0;margin:0;display:grid;gap:8px}
.list li{background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:10px 14px;min-width:0}
.muted{color:var(--muted)}footer{margin-top:40px;color:var(--muted);font-size:.8rem}
@media (prefers-reduced-motion:reduce){*{scroll-behavior:auto}}
"""


def pr_chip(number: int, states: dict[int, dict]) -> str:
    info = states.get(number)
    url = f"https://github.com/{REPO}/pull/{number}"
    if info is None:
        return f'<a class="chip" href="{url}">#{number}</a>'
    if info["state"] == "MERGED":
        kind, label = "merged", "merged"
    elif info["state"] == "CLOSED":
        kind, label = "closed", "closed"
    elif info["isDraft"]:
        kind, label = "draft", "draft"
    else:
        kind, label = "ready", "open"
    return f'<a class="chip {kind}" href="{url}" title="{html.escape(info["title"])}">#{number} · {label}</a>'


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("out_file", type=Path)
    parser.add_argument("--state", type=Path, default=Path.home() / ".local/state/tweezr-lint-quality")
    parser.add_argument("--no-gh", action="store_true")
    args = parser.parse_args()

    findings = [parse_finding(p) for p in sorted((args.state / "findings").glob("*.md"))]
    runs = sorted((args.state / "runs").glob("*.md"), reverse=True)
    slugs = {f["slug"] for f in findings}
    all_prs = {n for f in findings for n in f["prs"]}
    states = {} if args.no_gh else pr_states(all_prs)
    generated = datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M %Z")

    counts = {s: sum(f["status"] == s for f in findings) for s in STATUS_ORDER}
    stats = "".join(
        f'<div class="stat"><b>{counts[s]}</b><span>{STATUS_LABEL[s]}</span></div>' for s in STATUS_ORDER
    )
    stats += f'<div class="stat"><b>{len(runs)}</b><span>Sweeps run</span></div>'

    sections = []
    for status in STATUS_ORDER:
        group = [f for f in findings if f["status"] == status]
        if not group:
            continue
        cards = []
        for f in group:
            chips = [f'<span class="chip {f["status"]}">{f["status"]}</span>', f'<span class="chip">{f["kind"]}</span>']
            chips += [pr_chip(n, states) for n in f["prs"]]
            cards.append(
                f'<details class="card" id="{f["slug"]}"><summary><span class="slug">{f["slug"]}</span>'
                f'<p>{inline(f["finding"], slugs)}</p><div class="chips">{"".join(chips)}</div></summary>'
                f'<div class="body">{markdown(f["body"], slugs, heading_shift=1)}</div></details>'
            )
        sections.append(
            f'<h2 id="s-{status}">{STATUS_LABEL[status]} ({len(group)})</h2><div class="group">{"".join(cards)}</div>'
        )

    pr_rows = []
    for number in sorted(all_prs, reverse=True):
        owners = ", ".join(f'<a href="#{f["slug"]}">{f["slug"]}</a>' for f in findings if number in f["prs"])
        title = html.escape(states[number]["title"]) if number in states else ""
        pr_rows.append(f'<li>{pr_chip(number, states)} {title}<br><span class="muted">{owners}</span></li>')

    run_cards = []
    for index, run in enumerate(runs):
        text = run.read_text()
        first = text.splitlines()[0].lstrip("# ").strip() if text else run.stem
        rest = "\n".join(text.splitlines()[1:])
        opened = " open" if index == 0 else ""
        run_cards.append(
            f'<details class="card" id="run-{run.stem}"{opened}><summary><span class="slug">{run.stem}</span>'
            f"<p>{html.escape(first)}</p></summary>"
            f'<div class="body">{markdown(rest, slugs, heading_shift=1)}</div></details>'
        )

    latest = runs[0].stem if runs else "none"
    page = f"""<title>Lint Quality Desk</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>{CSS}</style>
<main>
<header><h1>Lint-quality desk</h1>
<p class="sub">Lint that catches real bugs with less noise and load · {len(findings)} findings · last sweep {latest}</p>
<nav class="top"><a href="#s-proposed">Approved</a><a href="#s-open">Waiting on you</a><a href="#prs">PRs</a><a href="#runs">Run history</a></nav></header>
<div class="stats">{stats}</div>
{"".join(sections)}
<h2 id="prs">Pull requests ({len(all_prs)})</h2><ul class="list">{"".join(pr_rows) or "<li>None yet</li>"}</ul>
<h2 id="runs">Run history ({len(runs)})</h2><div class="group">{"".join(run_cards) or "<p>No runs yet.</p>"}</div>
<footer>Updated {generated} from ~/.local/state/tweezr-lint-quality on puffin. Comment on any finding and the desk reads it at the start of its next run.</footer>
</main>
"""
    args.out_file.parent.mkdir(parents=True, exist_ok=True)
    args.out_file.write_text(page)
    print(f"wrote {args.out_file} ({len(findings)} findings, {len(runs)} runs, {len(all_prs)} PRs)")


if __name__ == "__main__":
    sys.exit(main())
