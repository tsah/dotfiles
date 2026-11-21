#!/usr/bin/env python3
"""Collect the facts for Tsah's morning box report on puffin.

  collect.py            print the facts as JSON, and stage the new state
  collect.py --commit   make the staged state current (run after the report is published)

Each finding has a stable `key`, a `level` (warn = needs Tsah, info = worth a line),
and `new` (its key was not in the last committed run). State lives in
~/.local/state/morning-box-report/state.json: {"last_run": ms, "keys": [...]}.

Secrets: never reads process command lines (no `ps -f`, `pgrep -a`, /proc/*/cmdline,
`systemctl list-units` descriptions, or `clankers status` health), so nothing here
can carry an environment secret into the report.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

STATE_DIR = Path.home() / ".local/state/morning-box-report"
STATE = STATE_DIR / "state.json"
STAGED = STATE_DIR / "state.staged.json"
SWEEP_DIR = Path.home() / ".local/state/unblock-sweep"
AMS = ZoneInfo("Europe/Amsterdam")
DISK_WARN = 85
MISSED_GRACE_S = 15 * 60
STALE_WORKER_H = 6
QUOTA = re.compile(r"usage limit|quota|rate.?limit|hit your limit|credit balance|limit reached", re.I)

if "--commit" in sys.argv:
    STAGED.replace(STATE)
    print("state committed")
    sys.exit(0)

now_ms = int(time.time() * 1000)
state = json.loads(STATE.read_text()) if STATE.exists() else {"last_run": None, "keys": []}
last_run = state["last_run"]
findings = []


def finding(key, level, text, **extra):
    findings.append({"key": key, "level": level, "text": text, **extra})


def run(args, timeout=60):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired) as e:
        return -1, f"{type(e).__name__}"


def run_json(args, timeout=60):
    rc, out = run(args, timeout)
    if rc != 0:
        return None
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return None


def ago(ms):
    if not ms:
        return "never"
    h = (now_ms - ms) / 3_600_000
    return f"{h * 60:.0f}m ago" if h < 1 else f"{h:.0f}h ago" if h < 48 else f"{h / 24:.0f}d ago"


def local(ms):
    return datetime.fromtimestamp(ms / 1000, AMS).strftime("%a %H:%M") if ms else None


# ---------- box health ----------
health = {}
cores = os.cpu_count() or 1
load1, load5, load15 = (float(x) for x in Path("/proc/loadavg").read_text().split()[:3])
health["load"] = {"1m": load1, "5m": load5, "15m": load15, "cores": cores}
if load15 > cores:
    finding("load-high", "warn", f"Load {load15:.0f} over 15 min on {cores} cores (1 min: {load1:.0f})")
elif load1 > 2 * cores:
    finding("load-spike", "info", f"Load spiking: {load1:.0f} now on {cores} cores, {load15:.0f} over 15 min")

mem = {}
for line in Path("/proc/meminfo").read_text().splitlines():
    k, v = line.split(":", 1)
    mem[k] = int(v.split()[0]) * 1024
gib = 1024 ** 3
avail_pct = 100 * mem["MemAvailable"] / mem["MemTotal"]
swap_used = mem["SwapTotal"] - mem["SwapFree"]
health["memory"] = {"total_gib": round(mem["MemTotal"] / gib), "available_gib": round(mem["MemAvailable"] / gib, 1),
                    "available_pct": round(avail_pct), "swap_used_pct": round(100 * swap_used / mem["SwapTotal"]) if mem["SwapTotal"] else 0}
if avail_pct < 10:
    finding("memory-low", "warn", f"Only {mem['MemAvailable'] / gib:.0f} GiB memory available ({avail_pct:.0f}%)")

du = shutil.disk_usage("/")
disk_pct = round(100 * du.used / (du.used + du.free))  # df's Use%, which excludes root-reserved blocks
health["disk_root"] = {"used_pct": disk_pct, "free_gib": round(du.free / gib), "size_gib": round(du.total / gib)}
rc, out = run(["df", "-h", "/"])
health["df_h"] = out.strip().splitlines()[-1] if rc == 0 else None
if disk_pct >= DISK_WARN:
    finding("disk-root", "warn", f"Disk / is {disk_pct}% full, {du.free / gib:.0f} GiB free")

rc, out = run(["docker", "system", "df", "--format", "{{json .}}"], timeout=60)
if rc == 0:
    health["docker"] = [json.loads(l) for l in out.splitlines() if l.strip()]
else:
    health["docker"] = None
    finding("docker-df", "warn", "docker system df failed (is the docker daemon up?)")

# inotify: count instances and watches from fdinfo (no command lines read).
instances = watches = 0
uid = os.getuid()
for pid in os.listdir("/proc"):
    if not pid.isdigit():
        continue
    try:
        if os.stat(f"/proc/{pid}").st_uid != uid:
            continue
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                if os.readlink(f"/proc/{pid}/fd/{fd}") == "anon_inode:inotify":
                    instances += 1
                    watches += sum(1 for l in open(f"/proc/{pid}/fdinfo/{fd}") if l.startswith("inotify wd:"))
            except OSError:
                pass
    except OSError:
        pass
max_inst = int(Path("/proc/sys/fs/inotify/max_user_instances").read_text())
max_watch = int(Path("/proc/sys/fs/inotify/max_user_watches").read_text())
health["inotify"] = {"instances": instances, "max_instances": max_inst, "watches": watches, "max_watches": max_watch}
if instances >= 0.8 * max_inst:
    finding("inotify-instances", "warn", f"inotify instances at {instances} of {max_inst}")
if watches >= 0.8 * max_watch:
    finding("inotify-watches", "warn", f"inotify watches at {watches} of {max_watch}")

services = {}
for unit in ("clankerhouse-runner-rex.service", "rex.service"):
    rc, out = run(["systemctl", "--user", "is-active", unit], timeout=15)
    services[unit] = out.strip() or "unknown"
    if services[unit] != "active":
        finding(f"service-{unit}", "warn", f"{unit} is {services[unit]}")
health["services"] = services

diag = run_json(["clankers", "diagnose", "--json"], timeout=60)
if diag is None:
    finding("clankerhouse-down", "warn", "clankerhouse daemon did not answer `clankers diagnose`")
else:
    errors = [i for i in diag.get("issues", []) if i.get("severity") == "error"]
    health["clankerhouse"] = {"healthy": diag.get("healthy"), "issues": Counter(f"{i.get('severity')}:{i.get('code')}" for i in diag.get("issues", []))}
    if not diag.get("healthy") or errors:
        finding("clankerhouse-unhealthy", "warn", "clankerhouse diagnose reports unhealthy",
                errors=[i.get("summary") for i in errors][:10])

who = run_json(["rex", "--autostart=false", "whoami", "--json"], timeout=20)
if who is None:
    finding("rex-down", "warn", "Rex server did not answer `rex whoami`")
else:
    health["rex"] = {"version": who.get("rex_version"), "started_at": who.get("started_at"), "sessions": who.get("session_count")}

# ---------- routines ----------
def cron_field(spec, lo, hi):
    vals = set()
    for part in spec.split(","):
        step = 1
        if "/" in part:
            part, s = part.split("/")
            step = int(s)
        if part == "*":
            a, b = lo, hi
        elif "-" in part:
            a, b = map(int, part.split("-"))
        else:
            a = b = int(part)
            if step > 1:
                b = hi
        vals.update(range(a, b + 1, step))
    return vals


ALIASES = {"@hourly": "0 * * * *", "@daily": "0 0 * * *", "@midnight": "0 0 * * *", "@weekly": "0 0 * * 0", "@monthly": "0 0 1 * *"}


def last_due(cron, tz, before_ms):
    """Latest minute <= before_ms matching cron in tz, searched back 8 days; None if none."""
    f = ALIASES.get(cron, cron).split()
    if len(f) != 5:
        return None
    mins, hours, doms, mons = cron_field(f[0], 0, 59), cron_field(f[1], 0, 23), cron_field(f[2], 1, 31), cron_field(f[3], 1, 12)
    dows = {d % 7 for d in cron_field(f[4], 0, 7)}
    dom_any, dow_any = f[2] == "*", f[4] == "*"
    t = datetime.fromtimestamp(before_ms // 60000 * 60, ZoneInfo(tz))
    for _ in range(8 * 24 * 60):
        dow = (t.weekday() + 1) % 7
        day_ok = (t.day in doms or dow in dows) if not (dom_any or dow_any) else (t.day in doms and dow in dows)
        if t.minute in mins and t.hour in hours and t.month in mons and day_ok:
            return int(t.timestamp() * 1000)
        t -= timedelta(minutes=1)
    return None


data = run_json(["clankers", "routine", "list", "--all", "--include-ended"])
routines = []
if data is None:
    finding("routines-unreadable", "warn", "`clankers routine list --all --include-ended` failed")
else:
    rows = data.get("routines", [])
    active_names = {r["name"] for r in rows if r["state"] == "active"}
    for r in rows:
        tz = r.get("timeZone") or "UTC"
        row = {"name": r["name"], "id": r["routineId"], "state": r["state"], "cron": r["cron"], "tz": tz,
               "lastFired": local(r.get("lastFiredAt")), "lastFiredAgo": ago(r.get("lastFiredAt")) if r.get("lastFiredAt") else None,
               "nextFire": local(r.get("nextFireAt")), "lastOutcome": r.get("lastOutcome"), "lastError": r.get("lastError"),
               "clanker": r.get("clankerId")}
        routines.append(row)
        rid = r["routineId"]
        if r["state"] != "active":
            ended_at = r.get("updatedAt") or 0
            replaced = r["name"] in active_names
            if last_run is None or ended_at > last_run:
                finding(f"routine-ended:{rid}", "info" if replaced else "warn",
                        f"Routine {r['name']} ended {ago(ended_at)} ({r.get('endedReason') or r.get('lastError') or 'no reason'})"
                        + ("; an active routine with the same name replaced it" if replaced else "; nothing replaced it"),
                        replaced=replaced)
            continue
        if r.get("lastError") or (r.get("lastOutcome") or "").startswith(("fail", "error")):
            finding(f"routine-failed:{rid}:{r.get('lastScheduledAt')}", "warn",
                    f"Routine {r['name']} last fire failed: {(r.get('lastError') or r.get('lastOutcome'))[:200]}")
        due = last_due(r["cron"], tz, now_ms - MISSED_GRACE_S * 1000)
        last_sched = r.get("lastScheduledAt") or 0
        if due and due >= (r.get("createdAt") or 0) and last_sched < due - 60_000:
            finding(f"routine-missed:{rid}:{due}", "warn",
                    f"Routine {r['name']} missed its {local(due)} fire (last fired {ago(r.get('lastFiredAt'))})")

# ---------- clankers ----------
clankers = run_json(["clankers", "list"]) or []
if isinstance(clankers, dict):
    clankers = clankers.get("clankers", [])
counts = Counter(c.get("state") for c in clankers)
clanker_rows = {"counts": dict(counts), "total": len(clankers), "blocked": [], "dead": [], "quota": [], "stale_workers": []}


def label(c):
    return c.get("session") or c.get("name")


for c in clankers:
    st = c.get("state")
    if st == "done":
        continue
    if st == "blocked":
        clanker_rows["blocked"].append({"session": label(c), "since": ago(c.get("lastEventAt"))})
    if not c.get("alive", True) or st in ("dead", "exited", "crashed"):
        clanker_rows["dead"].append({"session": label(c), "state": st, "since": ago(c.get("lastEventAt"))})
        finding(f"clanker-dead:{c['id']}", "warn", f"Clanker {label(c)} is dead ({st})")
    if QUOTA.search((c.get("lastText") or "")[-600:]):
        clanker_rows["quota"].append({"session": label(c), "since": ago(c.get("lastEventAt"))})
        finding(f"clanker-quota:{c['id']}:{c.get('generation')}", "warn", f"Clanker {label(c)} looks quota-hit")
    if c.get("parentWorkshopId") and st == "working" and c.get("lastEventAt") and now_ms - c["lastEventAt"] > STALE_WORKER_H * 3_600_000:
        clanker_rows["stale_workers"].append({"session": label(c), "since": ago(c["lastEventAt"])})
        finding(f"clanker-stale:{c['id']}:{c.get('generation')}", "warn",
                f"Worker {label(c)} says working but has been silent {ago(c['lastEventAt'])}")
if clanker_rows["blocked"]:
    finding("clankers-blocked:" + ",".join(sorted(b["session"] for b in clanker_rows["blocked"])), "warn",
            f"{len(clanker_rows['blocked'])} clanker(s) blocked: " + ", ".join(b["session"] for b in clanker_rows["blocked"]))

# ---------- overnight unblock sweep ----------
today = datetime.now(AMS).date()
sweep = {"date": today.isoformat(), "present": False}
path = SWEEP_DIR / f"{today.isoformat()}.md"
if path.exists():
    text = path.read_text()
    sweep.update(present=True, path=str(path))
    lines = text.splitlines()
    waiting, inline, inside = [], None, False
    for line in lines:
        if re.search(r"waiting on tsah", line, re.I) and re.match(r"\s*(#|\*\*)", line):
            inside = True
            rest = re.sub(r"^.*?waiting on tsah[^:]*:?\**:?", "", line, flags=re.I).strip(" *")
            inline = rest or inline
            continue
        if inside and re.match(r"\s*(#|\*\*)", line):
            inside = False
        if inside and re.match(r"\s*[-*] ", line):
            waiting.append(line.strip()[2:][:300])
    sweep["waiting_on_tsah"] = waiting
    sweep["waiting_inline"] = inline
    sweep["waiting_count"] = len(waiting) or (1 if inline else 0)
    if sweep["waiting_count"]:
        finding(f"sweep-waiting:{today}", "warn", f"Overnight sweep left {sweep['waiting_count']} item(s) waiting on Tsah")
else:
    finding(f"sweep-missing:{today}", "warn", f"No overnight unblock-sweep log for {today} ({path} missing)")
sweep["recent_logs"] = sorted(p.name for p in SWEEP_DIR.glob("*.md"))[-5:] if SWEEP_DIR.exists() else []

# ---------- needs-me ----------
needs = run_json(["clankers", "needs-me", "--json"], timeout=60)
needs_rows = {}
if needs is None:
    finding("needs-me-unreadable", "warn", "`clankers needs-me --json` failed")
else:
    by_reason = {}
    for r in needs.get("rows", []):
        if r.get("deferred") or (r.get("snoozedUntil") or 0) > now_ms:
            continue
        by_reason.setdefault(r.get("reason"), []).append({
            "name": r.get("title") or r.get("name"), "project": r.get("project"), "state": r.get("state"),
            "stage": (r.get("labels") or {}).get("stage"), "since": ago(r.get("since")),
            "excerpt": (r.get("excerpt") or "")[:240]})
    needs_rows = {"counts": needs.get("counts"), "by_reason": by_reason}

# ---------- new vs last run ----------
prev = set(state.get("keys", []))
for f in findings:
    f["new"] = f["key"] not in prev
STATE_DIR.mkdir(parents=True, exist_ok=True)
STAGED.write_text(json.dumps({"last_run": now_ms, "keys": [f["key"] for f in findings]}, indent=1))
attention = [f for f in findings if f["level"] == "warn"]
print(json.dumps({
    "host": os.uname().nodename, "run_at": datetime.fromtimestamp(now_ms / 1000, AMS).isoformat(timespec="minutes"),
    "last_run": local(last_run) if last_run else None,
    "post": bool(attention) or any(f["new"] for f in findings),
    "findings": findings, "health": health, "routines": routines, "clankers": clanker_rows,
    "unblock_sweep": sweep, "needs_me": needs_rows,
}, indent=1, default=str))
