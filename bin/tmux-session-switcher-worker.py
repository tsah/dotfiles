#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import time
from typing import Dict, List, Optional


def run(cmd: List[str]) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, check=False, capture_output=True, text=True)
    except OSError:
        return subprocess.CompletedProcess(cmd, 127, "", "")


def run_text(cmd: List[str]) -> str:
    result = run(cmd)
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def run_ok(cmd: List[str]) -> bool:
    return run(cmd).returncode == 0


def load_candidates(path: str) -> List[Dict[str, str]]:
    items: List[Dict[str, str]] = []
    seen = set()

    try:
        with open(path, "r", encoding="utf-8") as handle:
            for raw in handle:
                line = raw.rstrip("\n")
                if not line:
                    continue

                parts = line.split("\t")
                if len(parts) < 4:
                    continue

                row_id, row_type, row_path, row_session = parts[:4]
                if row_id in seen:
                    continue

                seen.add(row_id)
                items.append(
                    {
                        "row_id": row_id,
                        "row_type": row_type,
                        "row_path": row_path,
                        "row_session": row_session,
                    }
                )
    except FileNotFoundError:
        return []

    return items


def load_cache(path: str) -> Dict[str, Dict[str, object]]:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
            if isinstance(data, dict):
                return data
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        pass
    return {}


def write_cache(path: str, data: Dict[str, Dict[str, object]]) -> None:
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)

    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(data, handle, separators=(",", ":"), sort_keys=True)
    os.replace(tmp, path)


def is_fresh_match(
    item: Dict[str, str],
    cached: Dict[str, object],
    now_ts: int,
    max_age_seconds: int,
) -> bool:
    if max_age_seconds <= 0:
        return False

    checked_at = cached.get("checked_at")
    if not isinstance(checked_at, int):
        return False

    if now_ts - checked_at > max_age_seconds:
        return False

    source_path = cached.get("source_path")
    source_session = cached.get("source_session")
    if not isinstance(source_path, str) or not isinstance(source_session, str):
        return False

    return source_path == item.get("row_path", "") and source_session == item.get(
        "row_session", ""
    )


def trigger_reload(port: int, reload_command: str) -> None:
    if not port or not reload_command:
        return

    run(
        [
            "curl",
            "-s",
            "-XPOST",
            f"localhost:{port}",
            "-d",
            f"reload({reload_command})",
        ]
    )


def expand_path(path: str) -> str:
    if not path:
        return ""
    return os.path.realpath(os.path.expanduser(path))


def resolve_context(path: str) -> Optional[Dict[str, str]]:
    resolved = expand_path(path)
    if not resolved or not os.path.isdir(resolved):
        return None

    inside = run_text(["git", "-C", resolved, "rev-parse", "--is-inside-work-tree"])
    if inside != "true":
        return None

    worktree_root = run_text(["git", "-C", resolved, "rev-parse", "--show-toplevel"])
    common_dir = run_text(["git", "-C", resolved, "rev-parse", "--git-common-dir"])
    if not worktree_root or not common_dir:
        return None

    if not os.path.isabs(common_dir):
        common_dir = os.path.join(worktree_root, common_dir)

    worktree_root = os.path.realpath(worktree_root)
    common_dir = os.path.realpath(common_dir)
    container_root = os.path.dirname(common_dir)

    is_bare = run_text(
        ["git", f"--git-dir={common_dir}", "rev-parse", "--is-bare-repository"]
    )
    mode = "bare" if is_bare == "true" else "legacy"

    branch = run_text(["git", "-C", worktree_root, "branch", "--show-current"])
    if not branch:
        return None

    return {
        "worktree_root": worktree_root,
        "common_dir": common_dir,
        "container_root": container_root,
        "mode": mode,
        "branch": branch,
    }


def default_base_ref(common_dir: str) -> str:
    head_ref = run_text(
        [
            "git",
            f"--git-dir={common_dir}",
            "symbolic-ref",
            "-q",
            "--short",
            "refs/remotes/origin/HEAD",
        ]
    )
    if head_ref:
        return head_ref

    candidates = [
        "refs/remotes/origin/main",
        "refs/remotes/origin/master",
        "refs/heads/main",
        "refs/heads/master",
    ]
    for candidate in candidates:
        if run_ok(
            [
                "git",
                f"--git-dir={common_dir}",
                "show-ref",
                "--verify",
                "--quiet",
                candidate,
            ]
        ):
            if candidate.startswith("refs/remotes/"):
                return candidate[len("refs/remotes/") :]
            if candidate.startswith("refs/heads/"):
                return candidate[len("refs/heads/") :]

    return ""


def stale_reason(common_dir: str, base_ref: str, branch: str) -> str:
    if not run_ok(
        [
            "git",
            f"--git-dir={common_dir}",
            "show-ref",
            "--verify",
            "--quiet",
            f"refs/heads/{branch}",
        ]
    ):
        return ""

    if run_ok(
        [
            "git",
            f"--git-dir={common_dir}",
            "merge-base",
            "--is-ancestor",
            f"refs/heads/{branch}",
            base_ref,
        ]
    ):
        return "ancestor"

    cherry = run(
        ["git", f"--git-dir={common_dir}", "cherry", base_ref, f"refs/heads/{branch}"]
    )
    if cherry.returncode != 0:
        return ""

    has_plus = any(line.startswith("+") for line in cherry.stdout.splitlines())
    if not has_plus:
        return "patch-equivalent"

    return ""


def dirty_state(worktree_root: str) -> str:
    if not os.path.isdir(worktree_root):
        return "missing"

    status = run(["git", "-C", worktree_root, "status", "--porcelain"])
    if status.returncode != 0:
        return "missing"
    if status.stdout.strip():
        return "dirty"
    return "clean"


def sanitize_branch(branch: str) -> str:
    return branch.replace("/", "-").replace("\\", "-").replace("@", "-")


def enrich_candidate(item: Dict[str, str]) -> Dict[str, object]:
    row_path = expand_path(item.get("row_path", ""))
    row_session = item.get("row_session", "")
    source_path = item.get("row_path", "")
    source_session = item.get("row_session", "")

    context = resolve_context(row_path)
    if not context:
        return {
            "is_worktree": False,
            "checked_at": int(time.time()),
            "dirty_state": "",
            "stale_reason": "",
            "session_name": row_session,
            "session_open": bool(
                row_session and run_ok(["tmux", "has-session", "-t", row_session])
            ),
            "source_path": source_path,
            "source_session": source_session,
        }

    base_ref = default_base_ref(context["common_dir"])
    if not base_ref:
        return {
            "is_worktree": True,
            "repo_root": context["container_root"],
            "common_dir": context["common_dir"],
            "mode": context["mode"],
            "worktree_path": context["worktree_root"],
            "branch": context["branch"],
            "base_ref": "",
            "dirty_state": dirty_state(context["worktree_root"]),
            "stale_reason": "",
            "session_name": row_session,
            "session_open": bool(
                row_session and run_ok(["tmux", "has-session", "-t", row_session])
            ),
            "checked_at": int(time.time()),
            "source_path": source_path,
            "source_session": source_session,
        }

    default_branch = (
        base_ref[len("origin/") :] if base_ref.startswith("origin/") else base_ref
    )
    is_default = False
    if (
        context["mode"] == "legacy"
        and context["worktree_root"] == context["container_root"]
    ):
        is_default = True
    if context["mode"] == "bare" and context["branch"] == default_branch:
        is_default = True

    expected_session = f"{os.path.basename(context['container_root'])}@{sanitize_branch(context['branch'])}"
    session_name = row_session or expected_session

    status_reason = ""
    if not is_default:
        status_reason = stale_reason(context["common_dir"], base_ref, context["branch"])

    return {
        "is_worktree": True,
        "repo_root": context["container_root"],
        "common_dir": context["common_dir"],
        "mode": context["mode"],
        "worktree_path": context["worktree_root"],
        "branch": context["branch"],
        "base_ref": base_ref,
        "default_branch": default_branch,
        "is_default": is_default,
        "dirty_state": dirty_state(context["worktree_root"]),
        "stale_reason": status_reason,
        "session_name": session_name,
        "session_open": bool(
            session_name and run_ok(["tmux", "has-session", "-t", session_name])
        ),
        "checked_at": int(time.time()),
        "source_path": source_path,
        "source_session": source_session,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="tmux session switcher background status worker"
    )
    parser.add_argument("--candidates", required=True)
    parser.add_argument("--cache", required=True)
    parser.add_argument("--listen-port", type=int, default=0)
    parser.add_argument("--reload-command", default="")
    parser.add_argument("--reload-every", type=int, default=1)
    parser.add_argument("--sleep-ms", type=int, default=0)
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument("--max-age-seconds", type=int, default=90)
    args = parser.parse_args()

    candidates = load_candidates(args.candidates)
    if not candidates:
        return 0

    cache = load_cache(args.cache)
    changed = 0
    pending = 0
    now_ts = int(time.time())
    batch_size = max(1, args.batch_size)
    reload_every = max(1, args.reload_every)

    for item in candidates:
        row_id = item["row_id"]

        existing = cache.get(row_id)
        if isinstance(existing, dict) and is_fresh_match(
            item, existing, now_ts, args.max_age_seconds
        ):
            continue

        cache[row_id] = enrich_candidate(item)
        changed += 1
        pending += 1

        if pending >= batch_size:
            write_cache(args.cache, cache)
            if args.listen_port and args.reload_command and changed % reload_every == 0:
                trigger_reload(args.listen_port, args.reload_command)
            pending = 0

        if args.sleep_ms > 0:
            time.sleep(args.sleep_ms / 1000.0)

    if pending > 0:
        write_cache(args.cache, cache)

    if changed > 0 and args.listen_port and args.reload_command:
        trigger_reload(args.listen_port, args.reload_command)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
