---
name: Tmux Interactive Control
description: >-
  Drive interactive CLIs inside tmux panes by sending keys, capturing pane
  output, and waiting for prompts. Use this for REPL/debug loops, not worker
  spawning.
---

# Tmux Interactive Control

Use tmux as a programmable terminal for interactive tools (python, lldb, gdb,
psql, mysql, node, bash).

Use this skill when you need to:

- control an existing tmux pane with `send-keys`
- capture pane output to inspect progress
- poll for prompts/readiness text before sending next commands

Do NOT use this skill to spawn worktree-backed opencode workers.
Use `Tworker` and `spawn-opencode-agent` for that workflow.

## Core Rules

- If you start a detached session, immediately print copy/paste monitor
  commands (attach and one-shot capture).
- For debugging tasks, default to `lldb` unless the user asks for another
  debugger.
- For Python interactive shells, always launch with `PYTHON_BASIC_REPL=1`.

## Session Modes

### Existing tmux server (default for your repo workflow)

Use plain `tmux ...` commands when interacting with sessions created by
`wt`/`spawn-opencode-agent`.

```bash
tmux list-sessions
tmux list-panes -a -F '#{session_name}:#{window_name}.#{pane_index}'
```

### Isolated socket (optional)

Use a private socket only when isolation is needed.

```bash
CLAUDE_TMUX_SOCKET_DIR=${CLAUDE_TMUX_SOCKET_DIR:-${TMPDIR:-/tmp}/claude-tmux-sockets}
mkdir -p "$CLAUDE_TMUX_SOCKET_DIR"
SOCKET="$CLAUDE_TMUX_SOCKET_DIR/claude.sock"
tmux -S "$SOCKET" new -d -s claude-debug -n shell
tmux -S "$SOCKET" list-sessions
```

## Safe Input and Output

- Send literal text with `-l` when possible.
- Use `capture-pane -p -J` to avoid wrapped-line artifacts.
- Use explicit pane targets: `session:window.pane`.

Examples:

```bash
tmux send-keys -t my-session:opencode.0 -l -- 'PYTHON_BASIC_REPL=1 python3 -q'
tmux send-keys -t my-session:opencode.0 Enter
tmux capture-pane -p -J -t my-session:opencode.0 -S -200
tmux send-keys -t my-session:opencode.0 C-c
```

## Prompt Synchronization

Use the helper script to poll until a prompt or completion line appears:

```bash
scripts/wait-for-text.sh -t my-session:opencode.0 -p '^>>>' -T 20 -l 4000
```

If using an isolated socket:

```bash
scripts/wait-for-text.sh -S "$SOCKET" -t claude-debug:shell.0 -p '\(lldb\)'
```

## Monitoring Commands (always print after starting a detached session)

```bash
To monitor this session yourself:
  tmux attach -t my-session

Or capture output once:
  tmux capture-pane -p -J -t my-session:opencode.0 -S -200
```

For isolated sockets:

```bash
To monitor this session yourself:
  tmux -S "$SOCKET" attach -t claude-debug

Or capture output once:
  tmux -S "$SOCKET" capture-pane -p -J -t claude-debug:shell.0 -S -200
```

## Helper Scripts

- `scripts/find-sessions.sh`: list sessions on default socket, named socket,
  socket path, or scan all sockets under `CLAUDE_TMUX_SOCKET_DIR`.
- `scripts/wait-for-text.sh`: poll pane output with timeout until a regex (or
  fixed string) appears.

## Cleanup

```bash
tmux kill-session -t my-session
tmux kill-server
tmux -S "$SOCKET" kill-session -t claude-debug
tmux -S "$SOCKET" kill-server
```
