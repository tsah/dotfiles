#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: find-sessions.sh [-L socket-name|-S socket-path|-A] [-q pattern]

List tmux sessions on a socket (default tmux socket if none provided).

Options:
  -L, --socket       tmux socket name (passed to tmux -L)
  -S, --socket-path  tmux socket path (passed to tmux -S)
  -A, --all          scan all sockets under CLAUDE_TMUX_SOCKET_DIR
  -q, --query        case-insensitive substring filter for session names
  -h, --help         show this help
USAGE
}

socket_name=""
socket_path=""
query=""
scan_all=false
socket_dir="${CLAUDE_TMUX_SOCKET_DIR:-${TMPDIR:-/tmp}/claude-tmux-sockets}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -L|--socket)
            socket_name="${2-}"
            shift 2
            ;;
        -S|--socket-path)
            socket_path="${2-}"
            shift 2
            ;;
        -A|--all)
            scan_all=true
            shift
            ;;
        -q|--query)
            query="${2-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ "$scan_all" == true && ( -n "$socket_name" || -n "$socket_path" ) ]]; then
    echo "Cannot combine --all with --socket/--socket-path" >&2
    exit 1
fi

if [[ -n "$socket_name" && -n "$socket_path" ]]; then
    echo "Use either --socket or --socket-path, not both" >&2
    exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
    echo "tmux not found in PATH" >&2
    exit 1
fi

list_sessions() {
    local label="$1"
    shift
    local tmux_cmd=(tmux "$@")

    local sessions
    if ! sessions="$("${tmux_cmd[@]}" list-sessions -F '#{session_name}\t#{session_attached}\t#{session_created_string}' 2>/dev/null)"; then
        echo "No tmux server found on $label" >&2
        return 1
    fi

    if [[ -n "$query" ]]; then
        sessions="$(printf '%s\n' "$sessions" | grep -i -- "$query" || true)"
    fi

    if [[ -z "$sessions" ]]; then
        echo "No sessions found on $label"
        return 0
    fi

    echo "Sessions on $label:"
    while IFS=$'\t' read -r name attached created; do
        local attached_label="detached"
        if [[ "$attached" == "1" ]]; then
            attached_label="attached"
        fi
        printf '  - %s (%s, started %s)\n' "$name" "$attached_label" "$created"
    done <<< "$sessions"
}

if [[ "$scan_all" == true ]]; then
    if [[ ! -d "$socket_dir" ]]; then
        echo "Socket directory not found: $socket_dir" >&2
        exit 1
    fi

    shopt -s nullglob
    sockets=("$socket_dir"/*)
    shopt -u nullglob

    if [[ "${#sockets[@]}" -eq 0 ]]; then
        echo "No sockets found under $socket_dir" >&2
        exit 1
    fi

    exit_code=0
    for socket in "${sockets[@]}"; do
        if [[ ! -S "$socket" ]]; then
            continue
        fi
        if ! list_sessions "socket path '$socket'" -S "$socket"; then
            exit_code=1
        fi
    done

    exit "$exit_code"
fi

if [[ -n "$socket_name" ]]; then
    list_sessions "socket name '$socket_name'" -L "$socket_name"
elif [[ -n "$socket_path" ]]; then
    list_sessions "socket path '$socket_path'" -S "$socket_path"
else
    list_sessions "default socket"
fi
