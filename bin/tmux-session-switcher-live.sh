#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/bootstrap-path.sh"
. "$SCRIPT_DIR/lib/wt-compat.sh"

WORKER_SCRIPT="$SCRIPT_DIR/tmux-session-switcher-worker.py"
SERVICECTL_SCRIPT="$SCRIPT_DIR/tmux-session-switcher-servicectl.py"
SERVICE_ENABLED="${TMUX_SWITCHER_USE_SERVICE:-1}"
SERVICE_SOCKET="${TMUX_SWITCHER_SERVICE_SOCKET:-}"
WORKER_START_DELAY="${TMUX_SWITCHER_WORKER_DELAY:-0.75}"
WORKER_RELOAD_EVERY="${TMUX_SWITCHER_WORKER_RELOAD_EVERY:-8}"
WORKER_SLEEP_MS="${TMUX_SWITCHER_WORKER_SLEEP_MS:-5}"
WORKER_BATCH_SIZE="${TMUX_SWITCHER_WORKER_BATCH_SIZE:-6}"
WORKER_MAX_AGE_SECONDS="${TMUX_SWITCHER_WORKER_MAX_AGE_SECONDS:-120}"
WORKER_DISABLED="${TMUX_SWITCHER_DISABLE_WORKER:-0}"
PI_AGENT_HELPER="$SCRIPT_DIR/pi-agent-config"
PI_AGENT_LAUNCHER="$SCRIPT_DIR/spawn-pi-agent"
CLAUDE_LAUNCHER="$SCRIPT_DIR/spawn-claude-code"
REMOTE_ROWS_SCRIPT="$SCRIPT_DIR/tmux-remote-session-rows"
REMOTE_ATTACH_SCRIPT="$SCRIPT_DIR/tmux-attach-remote-session"


picker_cwd() {
    if command -v tmux >/dev/null 2>&1 && [[ -n "${TMUX_PANE:-}" ]]; then
        tmux display-message -p -t "$TMUX_PANE" '#{pane_current_path}' 2>/dev/null || pwd
        return 0
    fi

    pwd
}


now_ms() {
    date +%s%3N
}


notify() {
    local message="$1"
    if command -v tmux >/dev/null 2>&1 && [[ -n "${TMUX:-}" ]]; then
        tmux display-message "$message"
    else
        printf '%s\n' "$message"
    fi
}


copy_pr_url() {
    local row_id="$1"
    local cache_file="$2"
    local fallback_cwd="$3"
    local repo_path="$fallback_cwd"
    local branch_name=""
    local pr_url=""

    [[ -z "$row_id" ]] && return 1

    case "$row_id" in
        branch:*)
            branch_name=${row_id#branch:}
            ;;
        *)
            if [[ -n "$cache_file" && -f "$cache_file" ]]; then
                local entry
                entry=$(python3 - "$cache_file" "$row_id" <<'PY'
import json
import sys

cache_path = sys.argv[1]
row_id = sys.argv[2]

try:
    with open(cache_path, "r", encoding="utf-8") as handle:
        cache = json.load(handle)
except Exception:
    raise SystemExit(0)

item = cache.get(row_id)
if not isinstance(item, dict):
    raise SystemExit(0)

print("\t".join([str(item.get("worktree_path", "")), str(item.get("branch_name", ""))]))
PY
)
                if [[ -n "$entry" ]]; then
                    IFS=$'\t' read -r repo_path branch_name <<< "$entry"
                fi
            fi

            if [[ -z "$branch_name" && -d "$repo_path" ]]; then
                branch_name=$(git -C "$repo_path" branch --show-current 2>/dev/null || true)
            fi
            ;;
    esac

    if [[ -z "$branch_name" ]]; then
        notify "Could not determine branch for PR URL"
        return 1
    fi

    if [[ ! -d "$repo_path" ]]; then
        repo_path="$fallback_cwd"
    fi

    if ! command -v gh >/dev/null 2>&1; then
        notify "gh is not installed"
        return 1
    fi

    pr_url=$(cd "$repo_path" && gh pr view "$branch_name" --json url --jq .url 2>/dev/null || true)

    if [[ -z "$pr_url" ]]; then
        notify "No PR found for $branch_name"
        return 1
    fi

    if [[ -n "${TMUX:-}" ]] && tmux -V >/dev/null 2>&1; then
        printf '%s' "$pr_url" | tmux load-buffer -w -
    else
        printf '%s' "$pr_url" | "$SCRIPT_DIR/wl-copy"
    fi

    notify "Copied PR URL for $branch_name"
}


stale_reason_for_branch() {
    local common_dir="$1"
    local base_ref="$2"
    local branch_name="$3"
    local cherry_output
    local has_plus=0
    local line

    if ! git --git-dir="$common_dir" show-ref --verify --quiet "refs/heads/$branch_name"; then
        return 1
    fi

    if git --git-dir="$common_dir" merge-base --is-ancestor "refs/heads/$branch_name" "$base_ref" >/dev/null 2>&1; then
        printf 'ancestor\n'
        return 0
    fi

    cherry_output=$(git --git-dir="$common_dir" cherry "$base_ref" "refs/heads/$branch_name" 2>/dev/null || true)
    while IFS= read -r line; do
        case "$line" in
            +*)
                has_plus=1
                break
                ;;
        esac
    done <<< "$cherry_output"

    if [[ $has_plus -eq 0 ]]; then
        printf 'patch-equivalent\n'
        return 0
    fi

    return 1
}


worktree_dirty_state() {
    local worktree_path="$1"
    local status

    if [[ ! -d "$worktree_path" ]]; then
        printf 'missing\n'
        return 0
    fi

    status=$(git -C "$worktree_path" status --porcelain 2>/dev/null || true)
    if [[ -n "$status" ]]; then
        printf 'dirty\n'
    else
        printf 'clean\n'
    fi
}


remove_worktree_preserve_branch() {
    local common_dir="$1"
    local container_root="$2"
    local worktree_path="$3"
    local branch_name="$4"

    if wt_compat_has_native_bin; then
        "$SCRIPT_DIR/wwt" -C "$container_root" remove --foreground --force --no-delete-branch "$branch_name"
        return $?
    fi

    git --git-dir="$common_dir" worktree remove "$worktree_path" --force
}


print_remote_rows() {
    if [[ -x "$REMOTE_ROWS_SCRIPT" ]]; then
        "$REMOTE_ROWS_SCRIPT"
    fi
}


destroy_from_cache() {
    local row_id="$1"
    local cache_file="$2"
    local entry
    local is_worktree
    local repo_root
    local mode
    local worktree_path
    local branch_name
    local session_name
    local stale_reason
    local common_dir
    local container_root
    local base_ref
    local live_reason
    local dirty_state
    local current_session

    [[ -z "$row_id" || -z "$cache_file" ]] && return 1

    entry=$(python3 - "$cache_file" "$row_id" <<'PY'
import json
import sys

cache_path = sys.argv[1]
row_id = sys.argv[2]

try:
    with open(cache_path, "r", encoding="utf-8") as handle:
        cache = json.load(handle)
except Exception:
    print("")
    raise SystemExit(0)

item = cache.get(row_id)
if not isinstance(item, dict):
    print("")
    raise SystemExit(0)

def f(value):
    if value is None:
        return ""
    if isinstance(value, bool):
        return "1" if value else "0"
    return str(value)

fields = [
    f(item.get("is_worktree", False)),
    f(item.get("repo_root", "")),
    f(item.get("mode", "")),
    f(item.get("worktree_path", "")),
    f(item.get("branch", "")),
    f(item.get("session_name", "")),
    f(item.get("stale_reason", "")),
]

print("\t".join(fields))
PY
)

    if [[ -z "$entry" ]]; then
        notify "No status yet for selected row"
        return 1
    fi

    IFS=$'\t' read -r is_worktree repo_root mode worktree_path branch_name session_name stale_reason <<< "$entry"

    if [[ "$is_worktree" != "1" ]]; then
        notify "Selection is not a git worktree"
        return 1
    fi

    if [[ -z "$repo_root" || -z "$worktree_path" || -z "$branch_name" ]]; then
        notify "Missing worktree metadata"
        return 1
    fi

    if ! wt_compat_resolve_context "$repo_root"; then
        notify "Could not resolve repository context"
        return 1
    fi

    common_dir="$WT_COMPAT_COMMON_DIR"
    container_root="$WT_COMPAT_CONTAINER_ROOT"
    mode="$WT_COMPAT_MODE"

    base_ref=$(wt_compat_default_base_ref "$common_dir" 2>/dev/null || true)
    if [[ -z "$base_ref" ]]; then
        notify "Could not determine default branch"
        return 1
    fi

    live_reason=$(stale_reason_for_branch "$common_dir" "$base_ref" "$branch_name" 2>/dev/null || true)
    if [[ -z "$live_reason" ]]; then
        notify "Skipped $branch_name: not stale"
        return 1
    fi

    dirty_state=$(worktree_dirty_state "$worktree_path")

    if [[ "$mode" == 'bare' ]]; then
        if ! remove_worktree_preserve_branch "$common_dir" "$container_root" "$worktree_path" "$branch_name" >/dev/null 2>&1; then
            notify "Failed deleting $branch_name"
            return 1
        fi
    else
        if ! git -C "$container_root" worktree remove "$worktree_path" --force >/dev/null 2>&1; then
            notify "Failed deleting $branch_name"
            return 1
        fi
    fi

    if command -v tmux >/dev/null 2>&1; then
        if [[ -z "$session_name" ]]; then
            session_name=$(wt_compat_session_name "$container_root" "$branch_name")
        fi

        if tmux has-session -t "$session_name" 2>/dev/null; then
            current_session=$(tmux display-message -p '#S' 2>/dev/null || true)
            if [[ -n "${TMUX:-}" && "$current_session" == "$session_name" ]]; then
                tmux switch-client -p 2>/dev/null || tmux switch-client -n 2>/dev/null || true
            fi
            tmux kill-session -t "$session_name" >/dev/null 2>&1 || true
        fi
    fi

    notify "Destroyed stale $branch_name ($dirty_state)"
    return 0
}


build_unified_rows() {
    local cache_file="$1"
    local candidates_file="$2"
    local write_candidates_flag="${3:-1}"
    local current_cwd="${4:-$PWD}"

    python3 - "$cache_file" "$candidates_file" "$write_candidates_flag" "$current_cwd" "$PI_AGENT_HELPER" <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys

cache_file = sys.argv[1]
candidates_file = sys.argv[2]
write_candidates_enabled = len(sys.argv) > 3 and sys.argv[3] == "1"
current_cwd = sys.argv[4]
agent_helper = sys.argv[5]

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
RESET = "\033[0m"
COLORS = {
    "tmux": "\033[34m",
    "opencode": "\033[35m",
    "dir": "\033[36m",
    "branch": "\033[33m",
    "pi": "\033[32m",
    "claude": "\033[33m",
    "muted": "\033[90m",
    "done": "\033[32m",
    "generating": "\033[33m",
    "waiting question": "\033[34m",
    "tool running": "\033[35m",
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


def run_json(cmd):
    try:
        result = subprocess.run(cmd, check=False, capture_output=True, text=True)
    except OSError:
        return None
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def strip_ansi(text):
    return ANSI_RE.sub("", text)


def colorize(text, key):
    color = COLORS.get(key)
    if not color:
        return text
    return f"{color}{text}{RESET}"


def detect_session_markers():
    out = {}
    for raw in run_lines(["tmux", "list-panes", "-a", "-F", "#{session_name}\t#{window_name}\t#{pane_current_command}\t#{pane_title}"]):
        parts = raw.split("\t")
        if len(parts) < 4:
            continue

        session_name, window_name, pane_cmd, pane_title = parts[:4]
        markers = out.setdefault(session_name, set())

        window_name_lc = window_name.strip().lower()
        pane_cmd_lc = pane_cmd.strip().lower()
        pane_title_lc = pane_title.strip().lower()

        if pane_cmd_lc == "pi" or window_name_lc in {"pi", "pi-agent"} or window_name_lc.startswith("p:") or pane_title.startswith("π"):
            markers.add("pi")

        if pane_cmd_lc == "claude" or window_name_lc == "claude" or "claude code" in pane_title_lc:
            markers.add("claude")

    return out


def marker_text_for_session(session_name, session_markers):
    if not session_name:
        return ""

    markers = session_markers.get(session_name, set())
    marker_text = []
    if "pi" in markers:
        marker_text.append("π")
    if "claude" in markers:
        marker_text.append("C")
    return " ".join(marker_text)


def marker_suffix_for_session(session_name, session_markers):
    return marker_text_for_session(session_name, session_markers).replace(" ", "")


def decorate_icon(base_icon, color_key, session_name, session_markers):
    return f"{colorize(base_icon, color_key)}{marker_suffix_for_session(session_name, session_markers)}"


def has_agent_marker(session_name, session_markers):
    return bool(session_markers.get(session_name, set()) & {"pi", "claude"})


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


def shorten_path(text):
    return text.replace("~/dev/work/", "w/")


def trunc(text, width):
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    if width <= 3:
        return text[:width]
    return text[: width - 3] + "..."


def expand_path(path):
    if not path:
        return ""
    return os.path.realpath(os.path.expanduser(path))


def load_cache(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
            if isinstance(data, dict):
                return data
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        pass
    return {}


def write_candidates(path, candidates):
    if not path:
        return

    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)

    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        for row_id, row_type, row_path, row_session in candidates:
            handle.write("\t".join([row_id, row_type, row_path, row_session]) + "\n")
    os.replace(tmp, path)


def load_pi_agents(helper_path, cwd):
    if not shutil.which("pi"):
        return []
    if not helper_path or not os.path.isfile(helper_path) or not os.access(helper_path, os.X_OK):
        return []

    payload = run_json([helper_path, "--agent-format", "pi", "--cwd", cwd, "--list", "--format", "json"])
    if not isinstance(payload, list):
        return []

    agents = []
    for item in payload:
        if not isinstance(item, dict):
            continue

        agent_format = str(item.get("format", "")).strip().lower()
        if not agent_format:
            file_path = str(item.get("file", ""))
            if "/.claude/" in file_path or "/claude/" in file_path:
                agent_format = "claude"
            else:
                agent_format = "pi"

        if agent_format != "pi":
            continue

        name = str(item.get("name", "")).strip()
        if not name:
            continue

        agents.append(
            {
                "name": name,
                "source": str(item.get("source", "")).strip(),
                "description": str(item.get("description", "")).strip(),
            }
        )

    agents.sort(key=lambda row: (row["source"] != "project", row["name"]))
    return agents


def git_common_dir(cwd):
    try:
        result = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--git-common-dir"],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        return ""

    if result.returncode != 0:
        return ""

    common_dir = result.stdout.strip()
    if not common_dir:
        return ""
    if not os.path.isabs(common_dir):
        common_dir = os.path.join(cwd, common_dir)
    return os.path.realpath(common_dir)


def git_branches(cwd):
    common_dir = git_common_dir(cwd)
    if not common_dir:
        return []

    branches = set()
    for ref in run_lines(["git", "--git-dir", common_dir, "branch", "-a", "--format=%(refname:short)"]):
        branch = ref.strip()
        if branch.startswith("origin/"):
            branch = branch.removeprefix("origin/")
        if branch in {"", "HEAD", "origin"}:
            continue
        branches.add(branch)

    return sorted(branches)


cache = load_cache(cache_file)

filter_re = re.compile(r"(\barchived-|_.*__(persistent|temp)| [0-9]+$)")
tmux_rows = []
for raw in run_lines(["sesh", "list", "-t", "--icons"]):
    if filter_re.search(strip_ansi(raw)):
        continue
    tmux_rows.append(raw)

zoxide_rows = run_lines(["sesh", "list", "-z", "--icons"])
branch_rows = git_branches(current_cwd)

opencode_rows = []
if shutil.which("opencode-status"):
    for raw in run_lines(["opencode-status", "--tsv"]):
        parts = raw.split("\t")
        if len(parts) < 7:
            continue
        directory, status, title, age, session, pane, pid = parts[:7]
        if not session:
            continue
        if directory.endswith("(deleted)"):
            continue
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

    deduped = {}
    for row in opencode_rows:
        deduped[row["session"]] = row
    opencode_rows = list(deduped.values())

session_meta = {}
last_seen = {}
for raw in run_lines(["tmux", "list-sessions", "-F", "#{session_name}\t#{session_last_attached}\t#{session_path}"]):
    parts = raw.split("\t")
    if len(parts) < 3:
        continue

    name = parts[0]
    ts = parts[1]
    session_path = parts[2]
    session_meta[name] = session_path

    try:
        last_seen[name] = int(ts)
    except ValueError:
        last_seen[name] = 0

session_markers = detect_session_markers()

term_width = shutil.get_terminal_size((140, 20)).columns
prefix_w = 2
meta_w = 18
sep = 10
age_w = 4
status_w = 14
remaining = max(24, term_width - prefix_w - meta_w - age_w - status_w - sep)
name_w = max(18, int(remaining * 0.42))
title_w = max(8, remaining - name_w)

entries = []
candidates = []

opencode_hides_tmux = set()
opencode_dirs = set()
for row in opencode_rows:
    if row["session"] and not has_agent_marker(row["session"], session_markers):
        opencode_hides_tmux.add(row["session"])
    normalized = normalize_opencode_directory_label(row["directory"])
    opencode_dirs.add(normalized)
    base = basename_label(normalized)
    if base:
        opencode_hides_tmux.add(base)


def meta_flags(row_id, row_type, row_session):
    cached = cache.get(row_id)
    if isinstance(cached, dict):
        if cached.get("is_worktree"):
            flags = ["wt"]

            reason = cached.get("stale_reason") or ""
            if reason == "ancestor":
                flags.append("merged")
            elif reason == "patch-equivalent":
                flags.append("squash")

            dirty_state = cached.get("dirty_state") or ""
            if dirty_state == "dirty":
                flags.append("dirty")
            elif dirty_state == "missing":
                flags.append("missing")

            return "/".join(flags)

        return ""

    if row_type == "opencode":
        return "checking"

    if row_type == "tmux" and row_session and "@" in row_session:
        return "checking"

    return ""


def maybe_add_candidate(row_id, row_type, row_path, row_session):
    if row_type == "opencode" and row_path:
        candidates.append((row_id, row_type, row_path, row_session))
        return

    if row_type == "tmux" and row_session and "@" in row_session and row_path:
        candidates.append((row_id, row_type, row_path, row_session))
        return


for raw in tmux_rows:
    label = parse_sesh_label(raw)
    if label in opencode_hides_tmux:
        continue

    row_id = f"tmux:{label}"
    row_path = session_meta.get(label, "")
    row_session = label

    flags = meta_flags(row_id, "tmux", row_session)
    maybe_add_candidate(row_id, "tmux", row_path, row_session)

    icon = decorate_icon("", "tmux", label, session_markers)
    name = trunc(shorten_path(label), name_w)
    status = ""
    title = ""
    age = ""

    entries.append(
        {
            "display": (
                f"{icon}  {name:<{name_w}}  "
                f"{flags:<{meta_w}}  "
                f"{status:<{status_w}}  {title:<{title_w}}  {age:>{age_w}}"
            ),
            "type": "sesh",
            "arg1": raw,
            "arg2": "tmux",
            "row_id": row_id,
            "row_path": row_path,
            "row_session": row_session,
            "sort_group": 1,
            "sort_ts": last_seen.get(label, 0),
            "sort_name": label,
        }
    )

for row in opencode_rows:
    session = row["session"] or ""
    if has_agent_marker(session, session_markers):
        continue

    directory_label = normalize_opencode_directory_label(row["directory"])
    row_id = f"opencode:{session}"
    row_path = directory_label
    row_session = session

    flags = meta_flags(row_id, "opencode", row_session)
    maybe_add_candidate(row_id, "opencode", row_path, row_session)

    icon = decorate_icon("󱚟", "opencode", session, session_markers)
    name = trunc(shorten_path(row["directory"]), name_w)
    status_text = trunc(row["status"], status_w)
    title = trunc(row["title"], title_w)
    age = trunc(row["age"], age_w)

    entries.append(
        {
            "display": (
                f"{icon}  {name:<{name_w}}  "
                f"{flags:<{meta_w}}  "
                f"{colorize(f'{status_text:<{status_w}}', row['status'])}  "
                f"{colorize(f'{title:<{title_w}}', 'muted')}  "
                f"{colorize(f'{age:>{age_w}}', 'muted')}"
            ),
            "type": "opencode",
            "arg1": session,
            "arg2": row["pane"],
            "row_id": row_id,
            "row_path": row_path,
            "row_session": row_session,
            "sort_group": 1,
            "sort_ts": last_seen.get(session, 0),
            "sort_name": row["directory"],
        }
    )

for raw in zoxide_rows:
    label = parse_sesh_label(raw)
    if normalize_opencode_directory_label(label) in opencode_dirs:
        continue

    row_id = f"zoxide:{label}"
    row_path = label
    row_session = ""

    flags = meta_flags(row_id, "zoxide", row_session)
    maybe_add_candidate(row_id, "zoxide", row_path, row_session)

    icon = colorize("", "dir")
    name = trunc(shorten_path(label), name_w)
    status = ""
    title = ""
    age = ""

    entries.append(
        {
            "display": (
                f"{icon}  {name:<{name_w}}  "
                f"{flags:<{meta_w}}  "
                f"{status:<{status_w}}  {title:<{title_w}}  {age:>{age_w}}"
            ),
            "type": "sesh",
            "arg1": raw,
            "arg2": "zoxide",
            "row_id": row_id,
            "row_path": row_path,
            "row_session": row_session,
            "sort_group": 2,
            "sort_ts": 0,
            "sort_name": label,
        }
    )

for branch in branch_rows:
    row_id = f"branch:{branch}"
    row_path = current_cwd
    row_session = ""

    icon = colorize("", "branch")
    name = trunc(branch, name_w)
    flags = "branch"
    status = ""
    title = ""
    age = ""

    entries.append(
        {
            "display": (
                f"{icon}  {name:<{name_w}}  "
                f"{flags:<{meta_w}}  "
                f"{status:<{status_w}}  {title:<{title_w}}  {age:>{age_w}}"
            ),
            "type": "branch",
            "arg1": branch,
            "arg2": current_cwd,
            "row_id": row_id,
            "row_path": row_path,
            "row_session": row_session,
            "sort_group": 3,
            "sort_ts": 0,
            "sort_name": branch,
        }
    )

entries.sort(key=lambda e: (e["sort_group"], -e["sort_ts"], e["sort_name"]))

deduped_candidates = {}
for row_id, row_type, row_path, row_session in candidates:
    deduped_candidates[row_id] = (row_id, row_type, row_path, row_session)

if write_candidates_enabled:
    write_candidates(candidates_file, list(deduped_candidates.values()))

for e in entries:
    print(
        "\t".join(
            [
                e["display"],
                e["type"],
                e["arg1"],
                e["arg2"],
                e["row_id"],
                e["row_path"],
                e["row_session"],
            ]
        )
    )
PY
}


if [[ "${1:-}" == "--rows" ]]; then
    build_unified_rows "${2:-}" "${3:-}" "${4:-1}" "${5:-$(picker_cwd)}"
    print_remote_rows
    exit 0
fi

if [[ "${1:-}" == "--destroy" ]]; then
    destroy_from_cache "${2:-}" "${3:-}"
    exit 0
fi

if [[ "${1:-}" == "--copy-pr-url" ]]; then
    copy_pr_url "${2:-}" "${3:-}" "${4:-$(picker_cwd)}"
    exit $?
fi

if [[ "${1:-}" == "--destroy-confirm-action" ]]; then
    if [[ -n "${TMUX:-}" ]]; then
        if ! tmux confirm-before -p "Destroy selected worktree?" "run-shell true" >/dev/null 2>&1; then
            exit 0
        fi
    else
        printf 'Destroy selected worktree? [y/N] ' > /dev/tty
        read -r response < /dev/tty
        case "$response" in
            [yY]|[yY][eE][sS]) ;;
            *) exit 0 ;;
        esac
    fi

    if destroy_from_cache "${2:-}" "${3:-}" >/dev/null 2>&1; then
        printf 'exclude\n'
    else
        printf 'change-header(Failed to destroy selected row)\n'
    fi
    exit 0
fi

if [[ "${1:-}" == "--profile" ]]; then
    PROFILE_DIR=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/tmux-session-switcher-profile.XXXXXX")
    PROFILE_CACHE="$PROFILE_DIR/cache.json"
    PROFILE_CANDIDATES="$PROFILE_DIR/candidates.tsv"
    PROFILE_ROWS="$PROFILE_DIR/rows.tsv"

    printf '{}\n' > "$PROFILE_CACHE"
    : > "$PROFILE_CANDIDATES"

    PROFILE_CWD=$(picker_cwd)

    START_MS=$(now_ms)
    build_unified_rows "$PROFILE_CACHE" "$PROFILE_CANDIDATES" 1 "$PROFILE_CWD" > "$PROFILE_ROWS"
    COLD_MS=$(( $(now_ms) - START_MS ))

    CANDIDATE_COUNT=$(wc -l < "$PROFILE_CANDIDATES")

    WORKER_FULL_MS=-1
    WORKER_CACHED_MS=-1
    if command -v python3 >/dev/null 2>&1 && [[ -f "$WORKER_SCRIPT" ]]; then
        START_MS=$(now_ms)
        python3 "$WORKER_SCRIPT" \
            --candidates "$PROFILE_CANDIDATES" \
            --cache "$PROFILE_CACHE" \
            --batch-size "$WORKER_BATCH_SIZE" \
            --max-age-seconds 0 \
            --reload-every 1000 >/dev/null 2>&1 || true
        WORKER_FULL_MS=$(( $(now_ms) - START_MS ))

        START_MS=$(now_ms)
        python3 "$WORKER_SCRIPT" \
            --candidates "$PROFILE_CANDIDATES" \
            --cache "$PROFILE_CACHE" \
            --batch-size "$WORKER_BATCH_SIZE" \
            --max-age-seconds "$WORKER_MAX_AGE_SECONDS" \
            --reload-every 1000 >/dev/null 2>&1 || true
        WORKER_CACHED_MS=$(( $(now_ms) - START_MS ))
    fi

    SERVICE_ENQUEUE_MS=-1
    SERVICE_QUEUE_SIZE=-1
    if command -v python3 >/dev/null 2>&1 && [[ -f "$SERVICECTL_SCRIPT" ]]; then
        PROFILE_SOCKET="$PROFILE_DIR/service.sock"

        START_MS=$(now_ms)
        python3 "$SERVICECTL_SCRIPT" \
            --socket "$PROFILE_SOCKET" \
            --cache "$PROFILE_CACHE" \
            --batch-size "$WORKER_BATCH_SIZE" \
            --sleep-ms "$WORKER_SLEEP_MS" \
            --max-age-seconds "$WORKER_MAX_AGE_SECONDS" \
            --quiet \
            enqueue \
            --candidates "$PROFILE_CANDIDATES" \
            --ttl-seconds 30 >/dev/null 2>&1 || true
        SERVICE_ENQUEUE_MS=$(( $(now_ms) - START_MS ))

        SERVICE_STATS=$(python3 "$SERVICECTL_SCRIPT" --socket "$PROFILE_SOCKET" --json stats 2>/dev/null || true)
        if [[ -n "$SERVICE_STATS" ]]; then
            SERVICE_QUEUE_SIZE=$(python3 - "$SERVICE_STATS" <<'PY'
import json
import sys

try:
    data = json.loads(sys.argv[1])
except Exception:
    print(-1)
    raise SystemExit(0)

print(int(data.get("queue_size", -1)))
PY
)
        fi

        python3 "$SERVICECTL_SCRIPT" --socket "$PROFILE_SOCKET" --quiet stop >/dev/null 2>&1 || true
    fi

    START_MS=$(now_ms)
    build_unified_rows "$PROFILE_CACHE" "$PROFILE_CANDIDATES" 1 "$PROFILE_CWD" > /dev/null
    WARM_MS=$(( $(now_ms) - START_MS ))

    printf 'tmux-session-switcher-live profile\n'
    printf 'cold_rows_ms=%s\n' "$COLD_MS"
    printf 'warm_rows_ms=%s\n' "$WARM_MS"
    printf 'worker_full_ms=%s\n' "$WORKER_FULL_MS"
    printf 'worker_cached_ms=%s\n' "$WORKER_CACHED_MS"
    printf 'service_enqueue_ms=%s\n' "$SERVICE_ENQUEUE_MS"
    printf 'service_queue_size=%s\n' "$SERVICE_QUEUE_SIZE"
    printf 'candidate_count=%s\n' "$CANDIDATE_COUNT"

    rm -rf "$PROFILE_DIR"
    exit 0
fi


SELF="$(realpath "$0")"
REFRESH_PORT=$(shuf -i 10000-60000 -n 1)
PICKER_CWD=$(picker_cwd)

STATE_DIR=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/tmux-session-switcher-live.XXXXXX")
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-session-switcher-live"
CACHE_FILE="$CACHE_ROOT/status.json"
CANDIDATES_FILE="$STATE_DIR/candidates.tsv"
ROWS_FILE="$STATE_DIR/rows.tsv"

mkdir -p "$CACHE_ROOT"
if [[ ! -f "$CACHE_FILE" ]]; then
    printf '{}\n' > "$CACHE_FILE"
fi
: > "$CANDIDATES_FILE"

{
    build_unified_rows "$CACHE_FILE" "$CANDIDATES_FILE" 1 "$PICKER_CWD"
    print_remote_rows
} > "$ROWS_FILE"

SELF_Q=$(printf '%q' "$SELF")
CACHE_Q=$(printf '%q' "$CACHE_FILE")
CANDIDATES_Q=$(printf '%q' "$CANDIDATES_FILE")
PICKER_CWD_Q=$(printf '%q' "$PICKER_CWD")
ROWS_CMD="$SELF_Q --rows $CACHE_Q $CANDIDATES_Q 0 $PICKER_CWD_Q"

cleanup() {
    kill "$REFRESHER_PID" 2>/dev/null || true
    kill "$WORKER_PID" 2>/dev/null || true
    rm -rf "$STATE_DIR"
}
trap cleanup EXIT

(while sleep 10; do
    curl -s -XPOST "localhost:$REFRESH_PORT" -d "reload($ROWS_CMD)" 2>/dev/null || break
done) >/dev/null 2>&1 &
REFRESHER_PID=$!

ENQUEUE_PID=""
WORKER_PID=""

if [[ "$WORKER_DISABLED" != "1" ]]; then
    if [[ "$SERVICE_ENABLED" == "1" ]] && command -v python3 >/dev/null 2>&1 && [[ -f "$SERVICECTL_SCRIPT" ]]; then
        SERVICE_SOCKET_ARGS=()
        if [[ -n "$SERVICE_SOCKET" ]]; then
            SERVICE_SOCKET_ARGS=(--socket "$SERVICE_SOCKET")
        fi

        SERVICE_QUEUE_FILE="$CACHE_ROOT/enqueue.$$.$RANDOM.tsv"
        if cp "$CANDIDATES_FILE" "$SERVICE_QUEUE_FILE" 2>/dev/null; then
            :
        else
            SERVICE_QUEUE_FILE=""
        fi

        if [[ -n "$SERVICE_QUEUE_FILE" ]]; then
            (
                python3 "$SERVICECTL_SCRIPT" \
                    "${SERVICE_SOCKET_ARGS[@]}" \
                    --cache "$CACHE_FILE" \
                    --batch-size "$WORKER_BATCH_SIZE" \
                    --sleep-ms "$WORKER_SLEEP_MS" \
                    --max-age-seconds "$WORKER_MAX_AGE_SECONDS" \
                    --quiet \
                    enqueue \
                    --candidates "$SERVICE_QUEUE_FILE" \
                    --listen-port "$REFRESH_PORT" \
                    --reload-command "$ROWS_CMD" \
                    --ttl-seconds 45 >/dev/null 2>&1
                rm -f "$SERVICE_QUEUE_FILE"
            ) &
            ENQUEUE_PID=$!
        fi
    elif command -v python3 >/dev/null 2>&1 && [[ -f "$WORKER_SCRIPT" ]]; then
        (
            sleep "$WORKER_START_DELAY"
            python3 "$WORKER_SCRIPT" \
                --candidates "$CANDIDATES_FILE" \
                --cache "$CACHE_FILE" \
                --listen-port "$REFRESH_PORT" \
                --reload-command "$ROWS_CMD" \
                --reload-every "$WORKER_RELOAD_EVERY" \
                --sleep-ms "$WORKER_SLEEP_MS" \
                --batch-size "$WORKER_BATCH_SIZE" \
                --max-age-seconds "$WORKER_MAX_AGE_SECONDS" >/dev/null 2>&1
        ) &
        WORKER_PID=$!
    fi
fi

PICKER_STATUS=0

if command -v fzf-tmux >/dev/null 2>&1 && [[ -n "${TMUX:-}" ]]; then
    set +e
    SELECTED=$(fzf-tmux -p 95%,80% \
        --listen "$REFRESH_PORT" \
        --ansi \
        --no-sort \
        --delimiter=$'\t' \
        --with-nth=1 \
        --bind "ctrl-d:transform($SELF_Q --destroy-confirm-action {5} $CACHE_Q)" \
        --bind "ctrl-y:execute-silent($SELF_Q --copy-pr-url {5} $CACHE_Q $PICKER_CWD_Q)" \
        --bind 'alt-k:abort' \
        --color='header:5,prompt:4,info:8,border:8' \
        --header 'Enter: open | Ctrl-Y: copy PR URL | Ctrl-D: destroy stale wt+session | remote rows open over SSH | flags: wt[/merged|squash][/dirty|missing], checking' < "$ROWS_FILE")
    PICKER_STATUS=$?
    set -e
else
    set +e
    SELECTED=$(fzf \
        --listen "$REFRESH_PORT" \
        --ansi \
        --no-sort \
        --delimiter=$'\t' \
        --with-nth=1 \
        --bind "ctrl-d:transform($SELF_Q --destroy-confirm-action {5} $CACHE_Q)" \
        --bind "ctrl-y:execute-silent($SELF_Q --copy-pr-url {5} $CACHE_Q $PICKER_CWD_Q)" \
        --bind 'alt-k:abort' \
        --color='header:5,prompt:4,info:8,border:8' \
        --header 'Enter: open | Ctrl-Y: copy PR URL | Ctrl-D: destroy stale wt+session | remote rows open over SSH | flags: wt[/merged|squash][/dirty|missing], checking' < "$ROWS_FILE")
    PICKER_STATUS=$?
    set -e
fi

if [[ $PICKER_STATUS -ne 0 || -z "${SELECTED:-}" ]]; then
    exit 0
fi

IFS=$'\t' read -r _display TYPE ARG1 ARG2 _row_id _row_path _row_session <<< "$SELECTED"

if [[ "$TYPE" == "opencode" ]]; then
    opencode-attach-target "$ARG1" "$ARG2"
    exit 0
fi

if [[ "$TYPE" == "remote_tmux" ]]; then
    "$REMOTE_ATTACH_SCRIPT" "$ARG1" "$ARG2"
    exit 0
fi

if [[ "$TYPE" == "sesh" ]]; then
    sesh connect "$ARG1"
    exit 0
fi

if [[ "$TYPE" == "branch" ]]; then
    cd "$ARG2" || exit 1
    "$SCRIPT_DIR/wt" spawn "$ARG1"
fi
