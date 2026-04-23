#!/usr/bin/env python3

import argparse
import json
import os
import socket
import subprocess
import sys
import time
from typing import Dict, List, Optional


def default_socket_path() -> str:
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    return os.path.join(runtime_dir, f"tmux-session-switcher-live-{os.getuid()}.sock")


def default_cache_path() -> str:
    cache_root = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
    return os.path.join(cache_root, "tmux-session-switcher-live", "status.json")


def default_service_script() -> str:
    here = os.path.dirname(os.path.realpath(__file__))
    return os.path.join(here, "tmux-session-switcher-service.py")


def request(
    socket_path: str, payload: Dict[str, object], timeout: float = 0.6
) -> Dict[str, object]:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    try:
        client.connect(socket_path)
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        client.sendall(body)
        client.shutdown(socket.SHUT_WR)

        chunks = []
        while True:
            chunk = client.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    finally:
        client.close()

    raw = b"".join(chunks)
    if not raw:
        return {"ok": False, "error": "empty response"}

    try:
        decoded = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return {"ok": False, "error": "invalid response"}

    if not isinstance(decoded, dict):
        return {"ok": False, "error": "unexpected response type"}

    return decoded


def is_service_alive(socket_path: str) -> bool:
    try:
        response = request(socket_path, {"command": "ping"}, timeout=0.25)
        return bool(response.get("ok"))
    except OSError:
        return False


def start_service(args: argparse.Namespace) -> bool:
    if is_service_alive(args.socket):
        return True

    parent = os.path.dirname(args.cache)
    if parent:
        os.makedirs(parent, exist_ok=True)
    if not os.path.exists(args.cache):
        with open(args.cache, "w", encoding="utf-8") as handle:
            handle.write("{}\n")

    command = [
        sys.executable,
        args.service_script,
        "--socket",
        args.socket,
        "--cache",
        args.cache,
        "--batch-size",
        str(max(1, args.batch_size)),
        "--sleep-ms",
        str(max(0, args.sleep_ms)),
        "--max-age-seconds",
        str(max(0, args.max_age_seconds)),
    ]

    subprocess.Popen(
        command,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 2.0
    while time.time() < deadline:
        if is_service_alive(args.socket):
            return True
        time.sleep(0.05)

    return False


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


def print_response(response: Dict[str, object], json_output: bool) -> None:
    if json_output:
        print(json.dumps(response, sort_keys=True))
        return

    if response.get("ok"):
        if "error" in response:
            print(response["error"])
        elif "queue_size" in response:
            print(f"ok queue={response.get('queue_size', 0)}")
        elif "cache_entries" in response:
            print(
                f"ok queue={response.get('queue_size', 0)} cache={response.get('cache_entries', 0)} "
                f"sinks={response.get('sink_count', 0)}"
            )
        else:
            print("ok")
    else:
        print(response.get("error", "request failed"))


def cmd_start(args: argparse.Namespace) -> int:
    if not os.path.isfile(args.service_script):
        print("service script not found", file=sys.stderr)
        return 1

    if start_service(args):
        if args.json:
            print(json.dumps({"ok": True, "socket": args.socket, "cache": args.cache}))
        elif not args.quiet:
            print("service started")
        return 0

    if args.json:
        print(json.dumps({"ok": False, "error": "failed to start service"}))
    elif not args.quiet:
        print("failed to start service", file=sys.stderr)
    return 1


def cmd_enqueue(args: argparse.Namespace) -> int:
    if args.start and not start_service(args):
        if args.json:
            print(json.dumps({"ok": False, "error": "service unavailable"}))
        elif not args.quiet:
            print("service unavailable", file=sys.stderr)
        return 1

    candidates = load_candidates(args.candidates)
    payload: Dict[str, object] = {
        "command": "enqueue",
        "candidates": candidates,
        "listen_port": args.listen_port,
        "reload_command": args.reload_command,
        "ttl_seconds": args.ttl_seconds,
    }

    try:
        response = request(args.socket, payload)
    except OSError:
        if args.json:
            print(json.dumps({"ok": False, "error": "service socket unavailable"}))
        elif not args.quiet:
            print("service socket unavailable", file=sys.stderr)
        return 1

    if not args.quiet:
        print_response(response, args.json)

    return 0 if response.get("ok") else 1


def cmd_stats(args: argparse.Namespace) -> int:
    try:
        response = request(args.socket, {"command": "stats"})
    except OSError:
        if args.json:
            print(json.dumps({"ok": False, "error": "service socket unavailable"}))
        else:
            print("service socket unavailable", file=sys.stderr)
        return 1

    print_response(response, args.json)
    return 0 if response.get("ok") else 1


def cmd_ping(args: argparse.Namespace) -> int:
    try:
        response = request(args.socket, {"command": "ping"})
    except OSError:
        if args.json:
            print(json.dumps({"ok": False, "error": "service socket unavailable"}))
        else:
            print("service socket unavailable", file=sys.stderr)
        return 1

    print_response(response, args.json)
    return 0 if response.get("ok") else 1


def cmd_stop(args: argparse.Namespace) -> int:
    try:
        response = request(args.socket, {"command": "shutdown"})
    except OSError:
        if args.json:
            print(json.dumps({"ok": False, "error": "service socket unavailable"}))
        else:
            print("service socket unavailable", file=sys.stderr)
        return 1

    print_response(response, args.json)
    return 0 if response.get("ok") else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="tmux session switcher service control"
    )
    parser.add_argument("--socket", default=default_socket_path())
    parser.add_argument("--cache", default=default_cache_path())
    parser.add_argument("--service-script", default=default_service_script())
    parser.add_argument("--batch-size", type=int, default=6)
    parser.add_argument("--sleep-ms", type=int, default=5)
    parser.add_argument("--max-age-seconds", type=int, default=120)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--quiet", action="store_true")

    subparsers = parser.add_subparsers(dest="command", required=True)

    start_parser = subparsers.add_parser("start")
    start_parser.set_defaults(func=cmd_start)

    enqueue_parser = subparsers.add_parser("enqueue")
    enqueue_parser.add_argument("--candidates", required=True)
    enqueue_parser.add_argument("--listen-port", type=int, default=0)
    enqueue_parser.add_argument("--reload-command", default="")
    enqueue_parser.add_argument("--ttl-seconds", type=int, default=45)
    enqueue_parser.add_argument("--start", action="store_true", default=True)
    enqueue_parser.add_argument("--no-start", action="store_false", dest="start")
    enqueue_parser.set_defaults(func=cmd_enqueue)

    stats_parser = subparsers.add_parser("stats")
    stats_parser.set_defaults(func=cmd_stats)

    ping_parser = subparsers.add_parser("ping")
    ping_parser.set_defaults(func=cmd_ping)

    stop_parser = subparsers.add_parser("stop")
    stop_parser.set_defaults(func=cmd_stop)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
