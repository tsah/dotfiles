#!/usr/bin/env python3
"""Render the design-integrity desk's report site from its state directory.

Usage: render.py [--state DIR] [--out DIR] [--refresh-prs]

Reads ~/.local/state/tweezr-design-integrity (findings/, runs/, candidates.md,
desk.json) and writes a self-contained, mobile-friendly static site:
  index.html               findings by candidate, status, linked PRs, run index
  candidates.html          candidates.md rendered
  runs/<run>.html          one page per run log
  findings/<slug>.html     one page per finding
--refresh-prs asks `gh` for the state of every PR the findings and desk.json
name (Legacy-AI-Ltd/tweezr) and caches it in desk.json["prs"].
Prints only the output directory.
"""
from __future__ import annotations

import argparse
import html
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

REPO = "Legacy-AI-Ltd/tweezr"
STATUS_ORDER = ["open", "proposed", "accepted", "rejected"]
STRENGTH_ORDER = ["Strong", "Worth exploring", "Speculative", ""]

CSS = """
:root{--bg:#faf9f5;--panel:#fff;--ink:#1f1e1d;--muted:#6b6a65;--line:#e6e3da;--accent:#c96442;
--open:#2f6fb3;--proposed:#9a6b00;--accepted:#2e7d4f;--rejected:#8a8a8a;--chip:#f0eee6;--code:#f3f1ea}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){--bg:#1f1e1d;--panel:#2a2927;--ink:#ecebe6;
--muted:#a3a19a;--line:#3a3936;--accent:#e08a6b;--open:#6aa3e0;--proposed:#d9a93a;--accepted:#62b585;
--rejected:#8f8d87;--chip:#34332f;--code:#33322e}}
:root[data-theme=dark]{--bg:#1f1e1d;--panel:#2a2927;--ink:#ecebe6;--muted:#a3a19a;--line:#3a3936;--accent:#e08a6b;
--open:#6aa3e0;--proposed:#d9a93a;--accepted:#62b585;--rejected:#8f8d87;--chip:#34332f;--code:#33322e}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.55 ui-sans-serif,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:920px;margin:0 auto;padding:20px 16px 64px}
header.top{display:flex;flex-wrap:wrap;gap:8px 16px;align-items:baseline;justify-content:space-between;margin-bottom:8px}
h1{font:600 1.6rem/1.2 ui-serif,Georgia,serif;margin:0}h2{font:600 1.2rem/1.3 ui-serif,Georgia,serif;margin:28px 0 10px}
h3{font-size:1rem;margin:18px 0 6px}a{color:var(--accent)}nav a{margin-right:14px;font-size:.92rem}
.muted{color:var(--muted)}.small{font-size:.86rem}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px;margin:16px 0}
.stat{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:12px}
.stat b{display:block;font-size:1.5rem;line-height:1.1}.stat span{color:var(--muted);font-size:.85rem}
.card{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:14px 16px;margin:10px 0}
.card h3{margin:0 0 4px}.card p{margin:6px 0}
.chip{display:inline-block;font-size:.76rem;padding:1px 8px;border-radius:999px;background:var(--chip);margin:2px 4px 2px 0;white-space:nowrap}
.st-open{color:var(--open)}.st-proposed{color:var(--proposed)}.st-accepted{color:var(--accepted)}.st-rejected{color:var(--rejected)}
.dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:currentColor;margin-right:5px;vertical-align:middle}
.filters{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0}
.filters button{font:inherit;font-size:.85rem;border:1px solid var(--line);background:var(--panel);color:var(--ink);border-radius:999px;padding:4px 12px;cursor:pointer}
.filters button[aria-pressed=true]{background:var(--ink);color:var(--bg);border-color:var(--ink)}
details.group{background:var(--panel);border:1px solid var(--line);border-radius:12px;margin:10px 0;padding:0 14px}
details.group>summary{cursor:pointer;padding:12px 0;font-weight:600;list-style-position:outside}
details.group .card{border:0;border-top:1px solid var(--line);border-radius:0;margin:0;padding:12px 0}
ul.runs{list-style:none;padding:0;margin:0}ul.runs li{padding:8px 0;border-bottom:1px solid var(--line)}
.prose{overflow-wrap:anywhere}.prose ul{padding-left:22px}.prose li{margin:3px 0}
code{font:0.86em ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--code);padding:1px 4px;border-radius:4px;overflow-wrap:anywhere}
pre{background:var(--code);padding:10px;border-radius:8px;overflow-x:auto}pre code{background:none;padding:0}
.theme{font:inherit;font-size:.8rem;border:1px solid var(--line);background:var(--panel);color:var(--muted);border-radius:999px;padding:2px 10px;cursor:pointer}
footer{margin-top:40px;color:var(--muted);font-size:.8rem}
"""

THEME_JS = """
(function(){var k='di-theme';try{var t=localStorage.getItem(k);if(t)document.documentElement.dataset.theme=t}catch(e){}
document.addEventListener('click',function(e){var b=e.target.closest('.theme');if(!b)return;var r=document.documentElement;
var n=r.dataset.theme==='dark'?'light':(r.dataset.theme==='light'?'dark':(matchMedia('(prefers-color-scheme: dark)').matches?'light':'dark'));
r.dataset.theme=n;try{localStorage.setItem(k,n)}catch(e){}});})();
"""

FILTER_JS = """
(function(){var f={status:'all',scope:'design'};function apply(){document.querySelectorAll('[data-finding]').forEach(function(c){
var ok=(f.status==='all'||c.dataset.status===f.status)&&(f.scope==='all'||c.dataset.scope===f.scope);c.hidden=!ok});
document.querySelectorAll('details.group').forEach(function(g){var n=g.querySelectorAll('[data-finding]:not([hidden])').length;
g.hidden=n===0;var s=g.querySelector('.count');if(s)s.textContent=n})}
document.querySelectorAll('.filters button').forEach(function(b){b.addEventListener('click',function(){var k=b.dataset.k;f[k]=b.dataset.v;
document.querySelectorAll('.filters button[data-k='+k+']').forEach(function(x){x.setAttribute('aria-pressed',x===b)});apply()})});apply()})();
"""


def esc(s: str) -> str:
    return html.escape(s, quote=True)


def inline(text: str) -> str:
    parts = re.split(r"(`[^`]+`)", text)
    out = []
    for p in parts:
        if p.startswith("`") and p.endswith("`") and len(p) > 1:
            out.append(f"<code>{esc(p[1:-1])}</code>")
            continue
        p = esc(p)
        p = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', p)
        p = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", p)
        p = re.sub(r"(?<![\w/#])#(\d{4,5})\b", rf'<a href="https://github.com/{REPO}/pull/\1">#\1</a>', p)
        out.append(p)
    return "".join(out)


def md(text: str) -> str:
    """Small Markdown subset: headings, nested bullets, paragraphs, fenced code, inline code/bold/links."""
    lines = text.splitlines()
    out: list[str] = []
    stack: list[int] = []
    para: list[str] = []
    in_code = False

    def flush_para():
        if para:
            out.append(f"<p>{inline(' '.join(para))}</p>")
            para.clear()

    def close_lists(to: int = -1):
        while stack and stack[-1] > to:
            stack.pop()
            out.append("</li></ul>")

    for raw in lines:
        if raw.strip().startswith("```"):
            flush_para()
            close_lists()
            out.append("</code></pre>" if in_code else "<pre><code>")
            in_code = not in_code
            continue
        if in_code:
            out.append(esc(raw) + "\n")
            continue
        m = re.match(r"^(\s*)(?:[-*]|\d+\.)\s+(.*)$", raw)
        h = re.match(r"^(#{1,4})\s+(.*)$", raw)
        if h:
            flush_para()
            close_lists()
            lvl = min(len(h.group(1)) + 1, 4)
            out.append(f"<h{lvl}>{inline(h.group(2))}</h{lvl}>")
        elif m:
            flush_para()
            ind = len(m.group(1).expandtabs(2))
            if not stack or ind > stack[-1]:
                out.append("<ul><li>")
                stack.append(ind)
            else:
                close_lists(ind)
                if stack and stack[-1] < ind:
                    out.append("<ul><li>")
                    stack.append(ind)
                else:
                    out.append("</li><li>")
            out.append(inline(m.group(2)))
        elif not raw.strip():
            flush_para()
        elif stack:
            out.append(" " + inline(raw.strip()))
        else:
            para.append(raw.strip())
    flush_para()
    close_lists()
    if in_code:
        out.append("</code></pre>")
    return "\n".join(out)


def parse_finding(path: Path) -> dict:
    text = path.read_text()
    meta: dict[str, str] = {}
    body = text
    if text.startswith("---"):
        _, fm, body = text.split("---", 2)
        for line in fm.strip().splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                meta[k.strip()] = v.strip()
    sections: dict[str, str] = {}
    cur = None
    for line in body.splitlines():
        if line.startswith("## "):
            cur = line[3:].strip()
            sections[cur] = ""
        elif cur:
            sections[cur] += line + "\n"
    occ = sections.get("Occurrences", "")
    return {
        "slug": path.stem,
        "finding": meta.get("finding", ""),
        "kind": meta.get("kind", ""),
        "status": meta.get("status", "open"),
        "scope": meta.get("scope", "design"),
        "candidate": meta.get("candidate", "") or "uncategorised",
        "strength": meta.get("strength", ""),
        "occurrences": len(re.findall(r"^- ", occ, re.M)),
        "decisions": sections.get("Decisions", "").strip(),
        # Linked PRs are the ones named under Decisions (desk and implementation PRs);
        # PR numbers in Occurrences are evidence history, not links.
        "prs": sorted(set(re.findall(r"(?<![\w/])#(\d{4,5})\b", sections.get("Decisions", "")))),
        "text": body,
        "mtime": path.stat().st_mtime,
    }


def page(title: str, body: str, depth: int, extra_js: str = "") -> str:
    up = "../" * depth
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{esc(title)}</title>
<style>{CSS}</style></head><body><main>
<header class="top"><h1>{esc(title)}</h1><button class="theme" type="button">Theme</button></header>
<nav><a href="{up}index.html">Findings</a><a href="{up}candidates.html">Candidates</a><a href="{up}index.html#runs">Runs</a></nav>
{body}
<footer>Design Integrity Desk · rendered {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}</footer>
</main><script>{THEME_JS}{extra_js}</script></body></html>"""


def refresh_prs(numbers: set[str], desk: dict) -> None:
    cache = desk.setdefault("prs", {})
    for n in sorted(numbers):
        try:
            r = subprocess.run(["gh", "pr", "view", n, "-R", REPO, "--json", "number,title,state,isDraft,url"],
                               capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            continue
        if r.returncode == 0:
            d = json.loads(r.stdout)
            cache[n] = {"title": d["title"], "state": "DRAFT" if d["isDraft"] and d["state"] == "OPEN" else d["state"], "url": d["url"]}


def pr_chip(n: str, prs: dict) -> str:
    p = prs.get(n)
    url = p["url"] if p else f"https://github.com/{REPO}/pull/{n}"
    label = f"#{n} {p['state'].lower()}" if p else f"#{n}"
    title = esc(p["title"]) if p else ""
    return f'<a class="chip" href="{url}" title="{title}">{esc(label)}</a>'


def run_title(path: Path) -> tuple[str, str]:
    first = ""
    summary = ""
    for line in path.read_text().splitlines():
        if not first and line.startswith("# "):
            first = line[2:].strip()
        elif re.match(r"^- \*\*Status:\*\*", line):
            summary = re.sub(r"^- \*\*Status:\*\*\s*", "", line)
            break
    return first or path.stem, summary


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", default=str(Path.home() / ".local/state/tweezr-design-integrity"))
    ap.add_argument("--out", default=None)
    ap.add_argument("--refresh-prs", action="store_true")
    a = ap.parse_args()
    state = Path(a.state)
    desk_path = state / "desk.json"
    desk = json.loads(desk_path.read_text())
    out = Path(a.out or desk.get("report", {}).get("dir") or state / "site")
    (out / "runs").mkdir(parents=True, exist_ok=True)
    (out / "findings").mkdir(parents=True, exist_ok=True)

    findings = sorted((parse_finding(p) for p in (state / "findings").glob("*.md")), key=lambda f: f["slug"])
    if a.refresh_prs:
        nums = {n for f in findings for n in f["prs"]} | set(map(str, desk.get("trackedPrs", [])))
        refresh_prs(nums, desk)
        desk_path.write_text(json.dumps(desk, indent=2) + "\n")
    prs = desk.get("prs", {})

    for f in findings:
        chips = "".join(pr_chip(n, prs) for n in f["prs"])
        body = (f'<p><span class="chip st-{esc(f["status"])}"><span class="dot"></span>{esc(f["status"])}</span>'
                f'<span class="chip">{esc(f["scope"])}</span><span class="chip">{esc(f["strength"] or "—")}</span>'
                f'<span class="chip">{esc(f["kind"])}</span><span class="chip">candidate: {esc(f["candidate"])}</span>{chips}</p>'
                f'<p>{inline(f["finding"])}</p><div class="prose">{md(f["text"])}</div>')
        (out / "findings" / f"{f['slug']}.html").write_text(page(f["slug"], body, 1))

    runs = sorted((p for p in (state / "runs").glob("*.md")), key=lambda p: p.stem, reverse=True)
    run_rows = []
    for r in runs:
        t, s = run_title(r)
        (out / "runs" / f"{r.stem}.html").write_text(page(t, f'<div class="prose">{md(r.read_text())}</div>', 1))
        run_rows.append(f'<li><a href="runs/{r.stem}.html">{esc(r.stem)}</a> <span class="muted small">{inline(s or t)}</span></li>')

    cand = state / "candidates.md"
    if cand.exists():
        (out / "candidates.html").write_text(page("Deepening candidates", f'<div class="prose">{md(cand.read_text())}</div>', 0))

    counts = {s: sum(f["status"] == s for f in findings) for s in STATUS_ORDER}
    design = [f for f in findings if f["scope"] == "design"]
    last = desk.get("lastRun", {})
    stats = "".join(f'<div class="stat"><b>{v}</b><span>{esc(k)}</span></div>' for k, v in [
        ("findings", len(findings)), ("design", len(design)), ("open", counts["open"]),
        ("accepted", counts["accepted"]), ("last run", last.get("date", "—")), ("new last run", last.get("newFindings", 0))])

    groups: dict[str, list[dict]] = {}
    for f in findings:
        groups.setdefault(f["candidate"], []).append(f)

    def gkey(item):
        fs = item[1]
        best = min(STRENGTH_ORDER.index(f["strength"]) if f["strength"] in STRENGTH_ORDER else 3 for f in fs)
        return (best, -len(fs), item[0])

    gh = []
    for i, (name, fs) in enumerate(sorted(groups.items(), key=gkey)):
        cards = []
        for f in sorted(fs, key=lambda f: (STATUS_ORDER.index(f["status"]) if f["status"] in STATUS_ORDER else 9, f["slug"])):
            chips = "".join(pr_chip(n, prs) for n in f["prs"])
            dec = f["decisions"].splitlines()[-1] if f["decisions"] else ""
            cards.append(
                f'<div class="card" data-finding data-status="{esc(f["status"])}" data-scope="{esc(f["scope"])}">'
                f'<h3><a href="findings/{esc(f["slug"])}.html">{esc(f["slug"])}</a></h3>'
                f'<div><span class="chip st-{esc(f["status"])}"><span class="dot"></span>{esc(f["status"])}</span>'
                f'<span class="chip">{esc(f["strength"] or "—")}</span><span class="chip">{esc(f["scope"])}</span>'
                f'<span class="chip">{f["occurrences"]} occurrence lines</span>{chips}</div>'
                f'<p>{inline(f["finding"])}</p>'
                + (f'<p class="small muted">Latest decision: {inline(dec.lstrip("- "))}</p>' if dec else "")
                + "</div>")
        gh.append(f'<details class="group"{" open" if i < 3 else ""}><summary>{esc(name)} <span class="muted small">(<span class="count">{len(fs)}</span>)</span></summary>{"".join(cards)}</details>')

    btn = lambda k, v, lab, on: f'<button type="button" data-k="{k}" data-v="{v}" aria-pressed="{str(on).lower()}">{lab}</button>'
    filters = ('<div class="filters">' + btn("scope", "design", "Design", True) + btn("scope", "all", "All scopes", False)
               + btn("scope", "bug", "Bugs", False) + "</div><div class=\"filters\">" + btn("status", "all", "Any status", True)
               + "".join(btn("status", s, s.capitalize(), False) for s in STATUS_ORDER) + "</div>")
    tracked = "".join(pr_chip(str(n), prs) for n in desk.get("trackedPrs", []))
    body = (f'<p class="muted">Deep modules, locality and seams in Tweezr — not a bug list. Last run '
            f'{esc(last.get("date", "—"))} on <code>{esc(last.get("base", "—"))}</code>: {esc(last.get("kind", ""))}.</p>'
            f'<div class="stats">{stats}</div>'
            + (f'<h2>Desk PRs</h2><p>{tracked}</p>' if tracked else "")
            + f'<h2>Findings by candidate</h2>{filters}{"".join(gh)}'
            f'<h2 id="runs">Runs</h2><ul class="runs">{"".join(run_rows)}</ul>')
    (out / "index.html").write_text(page("Design Integrity Desk", body, 0, FILTER_JS))
    if out.parent == REPORTS_ROOT:
        rebuild_root_index()
    print(out)


REPORTS_ROOT = Path.home() / "reports"


def rebuild_root_index() -> None:
    """Refresh ~/reports/index.html (the list of every desk) with the shared publish-report tool."""
    subprocess.run([str(Path.home() / "dotfiles/bin/publish-report"), "--root"], check=True, stdout=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
