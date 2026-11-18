#!/usr/bin/env python3
"""Print the PRs merged in Legacy-AI-Ltd/tweezr since 08:00 Europe/Amsterdam on the previous weekday."""
import json
import subprocess
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

AMS = ZoneInfo("Europe/Amsterdam")
REPO = "Legacy-AI-Ltd/tweezr"

now = datetime.now(AMS)
day = now.date() - timedelta(days=1)
while day.weekday() >= 5:  # Sat/Sun -> back to Friday
    day -= timedelta(days=1)
since = datetime.combine(day, time(8, 0), AMS)
since_utc = since.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

out = subprocess.run(
    ["gh", "pr", "list", "-R", REPO, "--state", "merged", "--limit", "500",
     "--search", f"merged:>={since_utc}",
     "--json", "number,title,url,author,body,mergedAt"],
    check=True, capture_output=True, text=True,
).stdout
def is_bot(a):
    login = a["login"]
    return a.get("is_bot", False) or login.startswith("app/") or login.endswith("[bot]") or "dependabot" in login or "factory-bot" in login


prs = []
for pr in json.loads(out):
    a = pr["author"]
    prs.append({
        "title": pr["title"], "url": pr["url"], "mergedAt": pr["mergedAt"],
        "author": a["login"], "isBot": is_bot(a),
        "body": (pr["body"] or "")[:3000],
    })
prs.sort(key=lambda p: p["mergedAt"])
print(json.dumps({"since": since.isoformat(), "count": len(prs), "prs": prs}, indent=1))
