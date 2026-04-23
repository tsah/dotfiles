#!/usr/bin/env python3

import argparse
import json
import os
import socket
import subprocess
import time
from collections import deque
from typing import Deque, Dict, List, Optional, Tuple


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


class StatusService:
    def __init__(
        self,
        socket_path: str,
        cache_path: str,
        batch_size: int,
        sleep_ms: int,
        max_age_seconds: int,
    ) -> None:
        self.socket_path = socket_path
        self.cache_path = cache_path
        self.batch_size = max(1, batch_size)
        self.sleep_ms = max(0, sleep_ms)
        self.max_age_seconds = max(0, max_age_seconds)

        self.cache: Dict[str, Dict[str, object]] = load_cache(cache_path)
        self.queue: Deque[Dict[str, str]] = deque()
        self.queued_keys = set()
        self.sinks: Dict[Tuple[int, str], float] = {}

        self.start_ts = time.time()
        self.running = True
        self.processed_total = 0
        self.changed_total = 0
        self.skipped_fresh_total = 0

    def enqueue(self, candidates: List[Dict[str, str]]) -> int:
        added = 0
        for item in candidates:
            row_id = item.get("row_id", "")
            row_type = item.get("row_type", "")
            row_path = item.get("row_path", "")
            row_session = item.get("row_session", "")

            if not isinstance(row_id, str) or not row_id:
                continue
            if not isinstance(row_type, str):
                continue
            if not isinstance(row_path, str):
                continue
            if not isinstance(row_session, str):
                continue

            queue_key = f"{row_id}\t{row_path}\t{row_session}"
            if queue_key in self.queued_keys:
                continue

            candidate = {
                "row_id": row_id,
                "row_type": row_type,
                "row_path": row_path,
                "row_session": row_session,
                "_queue_key": queue_key,
            }
            self.queue.append(candidate)
            self.queued_keys.add(queue_key)
            added += 1

        return added

    def add_sink(self, listen_port: int, reload_command: str, ttl_seconds: int) -> None:
        if listen_port <= 0 or not reload_command:
            return

        ttl = max(5, ttl_seconds)
        self.sinks[(listen_port, reload_command)] = time.time() + ttl

    def _prune_sinks(self) -> None:
        now_ts = time.time()
        self.sinks = {
            key: expires_at
            for key, expires_at in self.sinks.items()
            if expires_at > now_ts
        }

    def _notify_sinks(self) -> None:
        self._prune_sinks()
        for (listen_port, reload_command), _expires_at in list(self.sinks.items()):
            trigger_reload(listen_port, reload_command)

    def process_batch(self) -> int:
        if not self.queue:
            return 0

        changed = 0
        processed = 0
        now_ts = int(time.time())

        while self.queue and processed < self.batch_size:
            item = self.queue.popleft()
            queue_key = item.get("_queue_key", "")
            if queue_key:
                self.queued_keys.discard(queue_key)

            row_id = item.get("row_id", "")
            if not row_id:
                continue

            existing = self.cache.get(row_id)
            if isinstance(existing, dict) and is_fresh_match(
                item, existing, now_ts, self.max_age_seconds
            ):
                self.skipped_fresh_total += 1
                processed += 1
                continue

            self.cache[row_id] = enrich_candidate(item)
            changed += 1
            processed += 1

            if self.sleep_ms > 0:
                time.sleep(self.sleep_ms / 1000.0)

        if changed > 0:
            write_cache(self.cache_path, self.cache)
            self._notify_sinks()

        self.processed_total += processed
        self.changed_total += changed
        return processed

    def stats_payload(self) -> Dict[str, object]:
        self._prune_sinks()
        return {
            "ok": True,
            "pid": os.getpid(),
            "uptime_seconds": int(time.time() - self.start_ts),
            "queue_size": len(self.queue),
            "cache_entries": len(self.cache),
            "sink_count": len(self.sinks),
            "processed_total": self.processed_total,
            "changed_total": self.changed_total,
            "skipped_fresh_total": self.skipped_fresh_total,
            "cache_path": self.cache_path,
            "socket_path": self.socket_path,
        }

    def handle_command(self, payload: Dict[str, object]) -> Dict[str, object]:
        command = payload.get("command")
        if command == "ping":
            return {"ok": True, "pid": os.getpid()}

        if command == "stats":
            return self.stats_payload()

        if command == "shutdown":
            self.running = False
            return {"ok": True}

        if command == "enqueue":
            candidates = payload.get("candidates")
            if not isinstance(candidates, list):
                candidates = []

            added = self.enqueue(candidates)

            listen_port_raw = payload.get("listen_port", 0)
            reload_command = payload.get("reload_command", "")
            ttl_raw = payload.get("ttl_seconds", 45)

            try:
                listen_port = int(listen_port_raw)
            except (TypeError, ValueError):
                listen_port = 0
            try:
                ttl_seconds = int(ttl_raw)
            except (TypeError, ValueError):
                ttl_seconds = 45

            if isinstance(reload_command, str) and reload_command:
                self.add_sink(listen_port, reload_command, ttl_seconds)

            return {
                "ok": True,
                "added": added,
                "queue_size": len(self.queue),
                "sink_count": len(self.sinks),
            }

        return {"ok": False, "error": "unknown command"}


def read_request(conn: socket.socket) -> Optional[Dict[str, object]]:
    data = b""
    while True:
        chunk = conn.recv(65536)
        if not chunk:
            break
        data += chunk

    if not data:
        return None

    try:
        payload = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None

    if not isinstance(payload, dict):
        return None

    return payload


def send_response(conn: socket.socket, payload: Dict[str, object]) -> None:
    body = json.dumps(payload, separators=(",", ":"))
    conn.sendall(body.encode("utf-8"))


def serve(service: StatusService) -> int:
    socket_dir = os.path.dirname(service.socket_path)
    if socket_dir:
        os.makedirs(socket_dir, exist_ok=True)

    if os.path.exists(service.socket_path):
        try:
            os.remove(service.socket_path)
        except OSError:
            return 1

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        server.bind(service.socket_path)
        os.chmod(service.socket_path, 0o600)
        server.listen(16)
        server.settimeout(0.2)

        while service.running:
            try:
                conn, _addr = server.accept()
            except socket.timeout:
                conn = None
            except OSError:
                conn = None

            if conn is not None:
                try:
                    payload = read_request(conn)
                    if payload is None:
                        send_response(conn, {"ok": False, "error": "invalid request"})
                    else:
                        response = service.handle_command(payload)
                        send_response(conn, response)
                except OSError:
                    pass
                finally:
                    try:
                        conn.close()
                    except OSError:
                        pass

            service.process_batch()

    finally:
        try:
            server.close()
        except OSError:
            pass

        try:
            if os.path.exists(service.socket_path):
                os.remove(service.socket_path)
        except OSError:
            pass

    return 0


def default_socket_path() -> str:
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    return os.path.join(runtime_dir, f"tmux-session-switcher-live-{os.getuid()}.sock")


def default_cache_path() -> str:
    cache_root = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
    return os.path.join(cache_root, "tmux-session-switcher-live", "status.json")


def main() -> int:
    parser = argparse.ArgumentParser(description="tmux session switcher status service")
    parser.add_argument("--socket", default=default_socket_path())
    parser.add_argument("--cache", default=default_cache_path())
    parser.add_argument("--batch-size", type=int, default=6)
    parser.add_argument("--sleep-ms", type=int, default=5)
    parser.add_argument("--max-age-seconds", type=int, default=120)
    args = parser.parse_args()

    service = StatusService(
        socket_path=args.socket,
        cache_path=args.cache,
        batch_size=args.batch_size,
        sleep_ms=args.sleep_ms,
        max_age_seconds=args.max_age_seconds,
    )
    return serve(service)


if __name__ == "__main__":
    raise SystemExit(main())
