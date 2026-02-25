#!/bin/bash

set -euo pipefail

FILTER='(_.*__(persistent|temp)| [0-9]+$)'

build_unified_rows() {
    python3 - <<'PY'
import os
import re
import shutil
import subprocess

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
RESET = "\033[0m"
COLORS = {
    "tmux": "\033[34m",
    "opencode": "\033[35m",
    "dir": "\033[36m",
    "muted": "\033[90m",
    "done": "\033[32m",
    "generating": "\033[33m",
    "waiting question": "\033[34m",
    "waiting permission": "\033[35m",
    "tool running": "\033[33m",
    "starting": "\033[34m",
    "unknown": "\033[90m",
}


def run_lines(cmd):
    try:
        result = subprocess.run(cmd, check=False, capture_output=True, text=True)
    except OSError:
        return []
    if result.returncode != 0:
        return []
    return [line for line in result.stdout.splitlines() if line]


def strip_ansi(text):
    return ANSI_RE.sub("", text)


def colorize(text, key):
    color = COLORS.get(key)
    if not color:
        return text
    return f"{color}{text}{RESET}"


def session_last_attached():
    out = {}
    for raw in run_lines(["tmux", "list-sessions", "-F", "#{session_name}\t#{session_last_attached}"]):
        parts = raw.split("\t", 1)
        if len(parts) != 2:
            continue
        name, ts = parts
        try:
            out[name] = int(ts)
        except ValueError:
            out[name] = 0
    return out


def parse_sesh_label(raw):
    plain = strip_ansi(raw).strip()
    parts = plain.split(maxsplit=1)
    if len(parts) == 2:
        return parts[1]
    return plain


def normalize_opencode_directory_label(text):
    text = text.strip()
    text = re.sub(r" \([0-9]+\)$", "", text)
    return text


def basename_label(text):
    label = text.rstrip("/")
    if "/" in label:
        return label.split("/")[-1]
    return label


def trunc(text, width):
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    if width <= 3:
        return text[:width]
    return text[: width - 3] + "..."


filter_re = re.compile(r"(_.*__(persistent|temp)| [0-9]+$)")
tmux_rows = []
for raw in run_lines(["sesh", "list", "-t", "--icons"]):
    if filter_re.search(strip_ansi(raw)):
        continue
    tmux_rows.append(raw)

zoxide_rows = run_lines(["sesh", "list", "-z", "--icons"])

opencode_rows = []
if shutil.which("opencode-status"):
    for raw in run_lines(["opencode-status", "--tsv"]):
        parts = raw.split("\t")
        if len(parts) < 7:
            continue
        directory, status, title, age, session, pane, pid = parts[:7]
        opencode_rows.append(
            {
                "directory": directory,
                "status": status,
                "title": title,
                "age": age,
                "session": session,
                "pane": pane,
                "pid": pid,
            }
        )

last_seen = session_last_attached()

term_width = shutil.get_terminal_size((120, 20)).columns
prefix_w = 2
sep = 8
age_w = 4
status_w = 14
remaining = max(20, term_width - prefix_w - age_w - status_w - sep)
name_w = max(18, int(remaining * 0.42))
title_w = max(8, remaining - name_w)

entries = []

opencode_hides_tmux = set()
opencode_dirs = set()
for row in opencode_rows:
    if row["session"]:
        opencode_hides_tmux.add(row["session"])
    normalized = normalize_opencode_directory_label(row["directory"])
    opencode_dirs.add(normalized)
    base = basename_label(normalized)
    if base:
        opencode_hides_tmux.add(base)

for raw in tmux_rows:
    label = parse_sesh_label(raw)
    if label in opencode_hides_tmux:
        continue

    icon = colorize("", "tmux")
    name = trunc(label, name_w)
    status = ""
    title = ""
    age = ""
    entries.append(
        {
            "display": f"{icon}  {name:<{name_w}}  {status:<{status_w}}  {title:<{title_w}}  {age:>{age_w}}",
            "type": "sesh",
            "arg1": raw,
            "arg2": "tmux",
            "sort_group": 1,
            "sort_ts": last_seen.get(label, 0),
            "sort_name": label,
        }
    )

for row in opencode_rows:
    session = row["session"] or ""
    icon = colorize("󱚟", "opencode")
    name = trunc(row["directory"], name_w)
    status_text = trunc(row["status"], status_w)
    title = trunc(row["title"], title_w)
    age = trunc(row["age"], age_w)

    entries.append(
        {
            "display": (
                f"{icon}  {name:<{name_w}}  "
                f"{colorize(f'{status_text:<{status_w}}', row['status'])}  "
                f"{colorize(f'{title:<{title_w}}', 'muted')}  "
                f"{colorize(f'{age:>{age_w}}', 'muted')}"
            ),
            "type": "opencode",
            "arg1": session,
            "arg2": row["pane"],
            "sort_group": 0,
            "sort_ts": last_seen.get(session, 0),
            "sort_name": row["directory"],
        }
    )

for raw in zoxide_rows:
    label = parse_sesh_label(raw)
    if normalize_opencode_directory_label(label) in opencode_dirs:
        continue

    icon = colorize("", "dir")
    name = trunc(label, name_w)
    status = ""
    title = ""
    age = ""
    entries.append(
        {
            "display": f"{icon}  {name:<{name_w}}  {status:<{status_w}}  {title:<{title_w}}  {age:>{age_w}}",
            "type": "sesh",
            "arg1": raw,
            "arg2": "zoxide",
            "sort_group": 2,
            "sort_ts": 0,
            "sort_name": label,
        }
    )

entries.sort(key=lambda e: (e["sort_group"], -e["sort_ts"], e["sort_name"]))

for e in entries:
    print("\t".join([e["display"], e["type"], e["arg1"], e["arg2"]]))
PY
}

PICKER_STATUS=0

if command -v fzf-tmux >/dev/null 2>&1 && [[ -n "${TMUX:-}" ]]; then
    set +e
    SELECTED=$(build_unified_rows | fzf-tmux -p 95%,80% \
        --ansi \
        --no-sort \
        --delimiter=$'\t' \
        --with-nth=1 \
        --color='header:5,prompt:4,info:8,border:8' \
        --header 'Enter: open selection')
    PICKER_STATUS=$?
    set -e
else
    set +e
    SELECTED=$(build_unified_rows | fzf \
        --ansi \
        --no-sort \
        --delimiter=$'\t' \
        --with-nth=1 \
        --color='header:5,prompt:4,info:8,border:8' \
        --header 'Enter: open selection')
    PICKER_STATUS=$?
    set -e
fi

if [[ $PICKER_STATUS -ne 0 || -z "${SELECTED:-}" ]]; then
    exit 0
fi

IFS=$'\t' read -r _display TYPE ARG1 ARG2 <<< "$SELECTED"

if [[ "$TYPE" == "opencode" ]]; then
    opencode-attach-target "$ARG1" "$ARG2"
    exit 0
fi

if [[ "$TYPE" == "sesh" ]]; then
    sesh connect "$ARG1"
fi
