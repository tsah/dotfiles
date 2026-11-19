#!/usr/bin/env python3
"""Collect the facts for Tsah's Linear sweep (team TWE). Read-only on Linear.

  collect.py            print the facts as JSON, and stage the new state
  collect.py --commit   make the staged state current (run after the report is posted or skipped)

State lives in ~/.local/state/linear-sweep/state.json: {"last_run": ISO-UTC, "snapshot": {...}}.
The Linear CLI is $LINEAR_CLI, default the task-manager worktree's ./task/agent/linear.
Never print or log LINEAR_API_KEY.
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

STATE_DIR = Path.home() / ".local/state/linear-sweep"
STATE = STATE_DIR / "state.json"
STAGED = STATE_DIR / "state.staged.json"
FIRST_RUN = "2026-11-18T06:40:00Z"  # 07:40 CET, Grokus's last run
LINEAR = os.environ.get("LINEAR_CLI", str(Path.home() / "dev/work/tweezr/task-manager/task/agent/linear"))
REPO = "Legacy-AI-Ltd/tweezr"
TWE = re.compile(r"\btwe-(\d+)\b", re.I)
NOT_STARTED = {"triage", "backlog", "unstarted"}  # Triage, Backlog, Next, Todo
CLOSED = {"completed", "canceled"}
REVIEW = {"In Review", "In Product Review"}  # Tsah's model: a merged PR puts the issue in review

if "--commit" in sys.argv:
    STAGED.replace(STATE)
    print("state committed")
    sys.exit(0)


def gql(query, **variables):
    args = [LINEAR, "api", query, "--variables-json", json.dumps(variables)]
    out = subprocess.run(args, check=True, capture_output=True, text=True).stdout
    data = json.loads(out)
    if data.get("errors"):
        sys.exit(f"Linear error: {data['errors']}")
    return data["data"]


def run_json(args):
    return json.loads(subprocess.run(args, check=True, capture_output=True, text=True).stdout)


state = json.loads(STATE.read_text()) if STATE.exists() else {"last_run": FIRST_RUN, "snapshot": {}}
since = state["last_run"]
run_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
today = datetime.now(ZoneInfo("Europe/Amsterdam")).date().isoformat()
ISSUE = "identifier title url dueDate state { name type } assignee { displayName }"

viewer = gql("{ viewer { id displayName } }")["viewer"]

# (a) What's new: notifications since the last run, plus due today or overdue.
notes, after = [], None
while True:
    page = gql(
        """query($t: DateTimeOrDuration!, $after: String) { notifications(first: 100, after: $after, filter: {createdAt: {gt: $t}}) {
             pageInfo { hasNextPage endCursor }
             nodes { type createdAt actor { displayName }
               ... on IssueNotification { issue { %s team { key } } comment { body user { displayName } } } } } }""" % ISSUE,
        t=since, after=after,
    )["notifications"]
    notes += page["nodes"]
    if not page["pageInfo"]["hasNextPage"]:
        break
    after = page["pageInfo"]["endCursor"]
new = []
for n in notes:
    issue = n.get("issue")
    if not issue or issue["team"]["key"] != "TWE":
        continue
    actor = (n.get("actor") or {}).get("displayName")
    if actor == viewer["displayName"]:
        continue  # his own changes are not news
    comment = n.get("comment")
    new.append({
        "type": n["type"], "at": n["createdAt"], "actor": actor,
        "issue": {k: issue[k] for k in ("identifier", "title", "url")}, "state": issue["state"]["name"],
        "comment": (comment["body"][:400] if comment else None),
    })

mine = gql(
    """query { viewer { assignedIssues(first: 250, filter: {team: {key: {eq: "TWE"}}, state: {type: {nin: ["completed", "canceled"]}}}) {
         nodes { %s } } } }""" % ISSUE
)["viewer"]["assignedIssues"]["nodes"]
due = [i for i in mine if i["dueDate"] and i["dueDate"] <= today]

# (b) Sync: his open issues against live clankers and PRs.
clankers = run_json(["clankers", "list"])
clankers = clankers if isinstance(clankers, list) else clankers.get("clankers", [])
work = {}  # TWE id -> list of {"kind", "label", "live"/"state", "url"}


def add(ids, entry):
    for num in ids:
        work.setdefault(f"TWE-{num}", []).append(entry)


for c in clankers:
    ws = c.get("workshop") or {}
    text = " ".join(str(x) for x in (c.get("name"), c.get("session"), c.get("worktreePath"), ws.get("branch"), ws.get("path")) if x)
    live = bool(c.get("alive")) and c.get("state") != "done"
    ids = set(TWE.findall(text))
    worktree = c.get("worktreePath") or ws.get("path")
    if not ids and worktree:
        # Workshops named without the ticket id: build and factory runs keep temp/build/TWE-<n>/.
        ids = {m.group(1) for p in Path(worktree, "temp/build").glob("TWE-*") if (m := re.match(r"TWE-(\d+)$", p.name, re.I))}
    add(ids, {"kind": "clanker", "label": c.get("session") or c.get("name"), "live": live})

open_prs = run_json(["gh", "pr", "list", "-R", REPO, "--state", "open", "--author", "tsah", "--limit", "300", "--json", "title,url,headRefName"])
for p in open_prs:
    add(set(TWE.findall(p["title"] + " " + p["headRefName"])), {"kind": "pr", "state": "open", "label": p["title"], "url": p["url"]})
merged_since = (datetime.now(timezone.utc) - timedelta(days=14)).strftime("%Y-%m-%d")
merged_prs = run_json(["gh", "pr", "list", "-R", REPO, "--state", "merged", "--author", "tsah", "--limit", "300",
                       "--search", f"merged:>={merged_since}", "--json", "title,url,headRefName,mergedAt"])
for p in merged_prs:
    add(set(TWE.findall(p["title"] + " " + p["headRefName"])), {"kind": "pr", "state": "merged", "label": p["title"], "url": p["url"]})

numbers = sorted({int(k.split("-")[1]) for k in work} | {int(i["identifier"].split("-")[1]) for i in mine})
issues = {}
for i in range(0, len(numbers), 100):
    for node in gql(
        """query($n: [Float!]) { issues(first: 100, filter: {team: {key: {eq: "TWE"}}, number: {in: $n}}) { nodes { %s } } }""" % ISSUE,
        n=numbers[i:i + 100],
    )["issues"]["nodes"]:
        issues[node["identifier"]] = node


def brief(i):
    return {k: i[k] for k in ("identifier", "title", "url")} | {"state": i["state"]["name"], "assignee": (i["assignee"] or {}).get("displayName")}


out_of_sync = []
for i in mine:
    entries = work.get(i["identifier"], [])
    active = [e for e in entries if e.get("live") or e.get("state") == "open"]
    if i["state"]["name"] == "In Progress" and not active:
        out_of_sync.append({"problem": "in_progress_without_live_clanker_or_open_pr", "issue": brief(i)})
for tid, entries in sorted(work.items()):
    issue = issues.get(tid)
    if issue is None:
        out_of_sync.append({"problem": "unknown_twe_id", "id": tid, "work": entries})
        continue
    active = [e for e in entries if e.get("live") or e.get("state") == "open"]
    merged = [e for e in entries if e.get("state") == "merged"]
    kind = issue["state"]["type"]
    if active and kind in NOT_STARTED:
        out_of_sync.append({"problem": "work_on_not_started_issue", "issue": brief(issue), "work": active})
    if active and kind in CLOSED:
        out_of_sync.append({"problem": "closed_issue_with_open_work", "issue": brief(issue), "work": active})
    if merged and not active and kind not in CLOSED and issue["state"]["name"] not in REVIEW:
        out_of_sync.append({"problem": "pr_merged_issue_not_done", "issue": brief(issue), "work": merged})

snapshot = {i["identifier"]: i["state"]["name"] for i in mine}
STATE_DIR.mkdir(parents=True, exist_ok=True)
STAGED.write_text(json.dumps({"last_run": run_at, "snapshot": snapshot}, indent=1))
print(json.dumps({
    "since": since, "run_at": run_at, "new": new, "due_or_overdue": [brief(i) | {"dueDate": i["dueDate"]} for i in due],
    "out_of_sync": out_of_sync,
    "previous_snapshot_changes": {k: [state["snapshot"].get(k), v] for k, v in snapshot.items() if state["snapshot"] and state["snapshot"].get(k) != v},
}, indent=1))
