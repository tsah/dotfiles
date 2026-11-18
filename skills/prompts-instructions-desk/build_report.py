#!/usr/bin/env python3
"""Build the prompts-instructions desk report page from the desk state.

Usage: build_report.py [STATE_DIR] [OUT_HTML]
Reads findings/*.md (front matter + body) and runs/*.md; writes one
self-contained HTML file (no external assets), by default
~/reports/prompts-instructions/index.html, served on the tailnet at
https://puffin.tail685506.ts.net/reports/prompts-instructions/. Each run has
the anchor #r-<run file name without .md>. Prints the output path.
"""
import html
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / ".local/state/tweezr-prompts-instructions")
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else Path.home() / "reports/prompts-instructions/index.html")
PR_RE = re.compile(r"https://github\.com/[\w.-]+/[\w.-]+/pull/(\d+)")


def inline(text: str) -> str:
    out = html.escape(text, quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', out)
    out = re.sub(r"(?<![\"'>])(https?://[^\s<)]+[^\s<).,;])", r'<a href="\1">\1</a>', out)
    return out


def markdown(text: str) -> str:
    """Small Markdown subset: headings, bullets, tables as text, paragraphs."""
    parts, in_list, para = [], False, []

    def flush():
        nonlocal para
        if para:
            parts.append("<p>" + inline(" ".join(para)) + "</p>")
            para = []

    def close_list():
        nonlocal in_list
        if in_list:
            parts.append("</ul>")
            in_list = False

    for raw in text.splitlines():
        line = raw.rstrip()
        heading = re.match(r"(#{1,4})\s+(.*)", line)
        bullet = re.match(r"\s*(?:[-*]|\d+\.)\s+(.*)", line)
        if heading:
            flush(); close_list()
            level = min(len(heading.group(1)) + 2, 5)
            parts.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
        elif bullet:
            flush()
            if not in_list:
                parts.append("<ul>")
                in_list = True
            parts.append("<li>" + inline(bullet.group(1)) + "</li>")
        elif not line.strip():
            flush(); close_list()
        elif in_list and raw.startswith("  "):
            parts[-1] = parts[-1][:-5] + " " + inline(line.strip()) + "</li>"
        else:
            close_list()
            para.append(line.strip())
    flush(); close_list()
    return "\n".join(parts)


def read_finding(path: Path) -> dict:
    text = path.read_text()
    meta, body = {}, text
    if text.startswith("---"):
        _, front, body = text.split("---", 2)
        for line in front.strip().splitlines():
            key, _, value = line.partition(":")
            meta[key.strip()] = value.strip()
    status = meta.get("status", "open")
    if "excluded" in meta.get("scope", ""):
        group = "excluded"
    elif status.startswith(("applied", "resolved", "rejected", "closed")):
        group = "closed"
    elif status.startswith(("proposed", "partly")):
        group = "proposed"
    else:
        group = "open"
    return {
        "slug": meta.get("finding", path.stem), "kind": meta.get("kind", ""), "status": status,
        "group": group, "first": meta.get("first_seen", ""), "last": meta.get("last_seen", ""),
        "confidence": meta.get("confidence", ""), "body": body.strip(),
        "prs": sorted({m.group(0) for m in PR_RE.finditer(text)}),
    }


def pr_links(urls) -> str:
    return " ".join(f'<a class="pr" href="{u}">PR #{PR_RE.match(u).group(1)}</a>' for u in urls)


def main() -> None:
    findings = [read_finding(p) for p in sorted((STATE / "findings").glob("*.md"))]
    order = {"proposed": 0, "open": 1, "closed": 2, "excluded": 3}
    findings.sort(key=lambda f: (order[f["group"]], f["slug"]))
    runs = sorted((STATE / "runs").glob("*.md"), reverse=True)
    counts = {g: sum(1 for f in findings if f["group"] == g) for g in order}
    labels = {"proposed": "PR or partly done", "open": "Open", "closed": "Applied / closed", "excluded": "Out of scope"}

    cards = []
    for f in findings:
        title = f["slug"].replace("-", " ")
        cards.append(f"""<details class="card {f['group']}" id="f-{f['slug']}">
<summary><span class="badge {f['group']}">{labels[f['group']]}</span>
<span class="title">{html.escape(title)}</span>
<span class="meta">{html.escape(f['kind'])} · first seen {html.escape(f['first'])} · last seen {html.escape(f['last'])}</span>
<span class="status">{inline(f['status'])}</span>
<span class="prs">{pr_links(f['prs'])}</span></summary>
<div class="body"><p class="conf"><strong>Confidence:</strong> {inline(f['confidence'])}</p>
{markdown(f['body'])}</div></details>""")

    run_index, run_blocks = [], []
    for p in runs:
        text = p.read_text()
        first = next((l.lstrip("# ").strip() for l in text.splitlines() if l.strip()), p.stem)
        prs = sorted({m.group(0) for m in PR_RE.finditer(text)})
        run_index.append(f'<li><a href="#r-{p.stem}">{html.escape(p.stem)}</a> — {inline(first)} {pr_links(prs)}</li>')
        run_blocks.append(f'<details class="card run" id="r-{p.stem}"><summary><span class="title">{html.escape(p.stem)}</span>'
                          f'<span class="meta">{inline(first)}</span></summary><div class="body">{markdown(text)}</div></details>')

    all_prs = sorted({u for f in findings for u in f["prs"]} | {m.group(0) for p in runs for m in PR_RE.finditer(p.read_text())})
    built = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Prompts and instructions desk</title>
<style>
:root{{--bg:#faf9f5;--card:#fff;--ink:#1f1e1d;--muted:#6b6a65;--line:#e6e3da;--accent:#c96442;
--open:#b7791f;--proposed:#2b6cb0;--closed:#2f855a;--excluded:#8a8880;--code:#f1efe8}}
@media (prefers-color-scheme: dark){{:root{{--bg:#1f1e1d;--card:#2a2927;--ink:#f1efe8;--muted:#a8a69e;
--line:#3b3a37;--accent:#e08a6a;--open:#ecc16b;--proposed:#7fb3ea;--closed:#7fcf9f;--excluded:#8a8880;--code:#35332f}}}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:16px/1.55 ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif}}
main{{max-width:880px;margin:0 auto;padding:24px 16px 64px}}
h1{{font:600 1.7rem/1.2 ui-serif,Georgia,serif;margin:0 0 4px}}
h2{{font:600 1.2rem/1.3 ui-serif,Georgia,serif;margin:36px 0 12px}}
h3,h4,h5{{font-size:1rem;margin:16px 0 6px}}
.sub{{color:var(--muted);margin:0 0 20px;font-size:.92rem}}
.stats{{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px}}
.stat{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px 14px}}
.stat b{{display:block;font-size:1.6rem;line-height:1.1}}
.stat span{{color:var(--muted);font-size:.85rem}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:12px;margin:10px 0;overflow:hidden}}
.card summary{{cursor:pointer;padding:14px 16px;list-style:none;display:grid;gap:4px}}
.card summary::-webkit-details-marker{{display:none}}
.card[open] summary{{border-bottom:1px solid var(--line)}}
.title{{font-weight:600;overflow-wrap:anywhere}}
.meta,.status{{color:var(--muted);font-size:.86rem;overflow-wrap:anywhere}}
.status{{color:var(--ink)}}
.badge{{justify-self:start;font-size:.72rem;font-weight:600;letter-spacing:.03em;text-transform:uppercase;
padding:2px 8px;border-radius:999px;border:1px solid currentColor}}
.badge.open{{color:var(--open)}}.badge.proposed{{color:var(--proposed)}}
.badge.closed{{color:var(--closed)}}.badge.excluded{{color:var(--excluded)}}
.body{{padding:6px 16px 16px;font-size:.94rem;overflow-wrap:anywhere}}
.body ul{{padding-left:20px}}
code{{background:var(--code);border-radius:4px;padding:1px 4px;font:.86em ui-monospace,SFMono-Regular,Menlo,monospace;overflow-wrap:anywhere}}
a{{color:var(--accent)}}
a.pr{{display:inline-block;font-size:.82rem;border:1px solid var(--line);border-radius:999px;padding:1px 8px;text-decoration:none;margin-right:4px}}
ul.index{{padding-left:20px}}ul.index li{{margin:6px 0;overflow-wrap:anywhere}}
footer{{color:var(--muted);font-size:.82rem;margin-top:40px}}
</style></head><body><main>
<p class="sub"><a href="../">All reports</a></p>
<h1>Prompts and instructions desk</h1>
<p class="sub">Deletion-first review of the root <code>AGENTS.md</code> and the top-level agent skills in
<code>AI/skills</code>. Trims go out as pull requests only. Built {built}.</p>
<div class="stats">
<div class="stat"><b>{counts['open']}</b><span>open findings</span></div>
<div class="stat"><b>{counts['proposed']}</b><span>with a PR or partly done</span></div>
<div class="stat"><b>{counts['closed']}</b><span>applied or closed</span></div>
<div class="stat"><b>{len(runs)}</b><span>runs recorded</span></div>
</div>
<h2>Findings</h2>
{''.join(cards)}
<h2>Pull requests</h2>
<p>{pr_links(all_prs) or 'None yet.'}</p>
<h2>Run history</h2>
<ul class="index">{''.join(run_index)}</ul>
{''.join(run_blocks)}
<footer>Source: <code>~/.local/state/tweezr-prompts-instructions</code> (findings and runs). Tap a card to open it.</footer>
</main></body></html>
"""
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(page)
    print(OUT)


if __name__ == "__main__":
    main()
