#!/usr/bin/env python3
"""POST the desk report link to Grokus's webhook (the "groky" sink in ~/.config/clankerhouse/hooks.toml).

Usage: post.py TITLE URL
Prints only the HTTP status. Never prints the webhook URL or the Authorization header.
"""
import json
import sys
import tomllib
import urllib.error
import urllib.request
from pathlib import Path

title, page_url = sys.argv[1], sys.argv[2]
sinks = tomllib.loads(Path.home().joinpath(".config/clankerhouse/hooks.toml").read_text())["sinks"]
sink = next(s for s in sinks if s["name"] == "groky")
body = json.dumps({"kind": "slop-master-report", "title": title, "url": page_url}).encode()
headers = {"content-type": "application/json", **sink.get("headers", {})}
req = urllib.request.Request(sink["url"], data=body, headers=headers, method="POST")
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        print(f"posted: HTTP {resp.status}")
except urllib.error.HTTPError as e:
    print(f"post failed: HTTP {e.code}")
    sys.exit(1)
