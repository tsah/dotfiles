# Waystation agent API QA plan

> Safety: every integration scenario runs against a private tmux socket, disposable Git repository, runtime directory, and state directory under `/tmp/qa-waystation-agent-api-*`. The harness must never inspect, mutate, or destroy real tmux sessions or worktrees.

## Contract under test

```text
waystation agent list [--cwd PATH]
waystation agent status AGENT_ID
waystation agent capabilities AGENT_ID
waystation agent wait AGENT_ID [--after GENERATION] [--timeout SECONDS]
waystation agent send AGENT_ID [--delivery steer|follow-up] [--wait]
waystation agent result AGENT_ID [--generation GENERATION]
```

Tmux is permitted only for discovery, identity metadata, focus, and test-fixture inspection. Agent communication must not use `send-keys`, `load-buffer`, `paste-buffer`, or `capture-pane`. The QA harness may capture its own disposable pane before and after a native send solely to prove that terminal contents did not change.

## Automated checks

Run:

```bash
cd ~/dotfiles/wayfinder
bun run check
bun test
scripts/qa-agent-api
scripts/qa
```

Also:

1. Bundle-check `pi/extensions/tmux-worker-lifecycle.ts` with the Pi package import external.
2. Run shell syntax checks and Neovim's headless `pi_tmux` setup.
3. Search production communication paths for forbidden tmux input/capture commands.
4. Run `git diff --check`.

## Disposable integration scenarios

The executable harness must verify:

1. **Discovery and identity**
   - Pi, Claude, Codex, and OpenCode panes are discovered on a private tmux server.
   - A legacy pane without an ID receives one stable `ws-*` ID.
   - IDs survive repeated listing and tmux session rename.
   - `--cwd` filters by canonical worktree.
   - Duplicate IDs fail rather than selecting an arbitrary pane.

2. **Status and capabilities**
   - Pi advertises status, report wait/result, and native Unix-socket send.
   - Claude/Codex advertise report-based wait but no send/result.
   - OpenCode is monitor-only and rejects wait/send/result.
   - Unknown IDs produce versioned JSON errors and exit `3`.

3. **Native Pi communication**
   - Idle/default, explicit `steer`, and explicit `follow-up` sends reach the native socket.
   - `send --wait` waits for a newer settled generation and returns its matching result.
   - Latest and historical result lookup return the correct generations.
   - Socket requests carry the expected stable agent ID.
   - The Pi pane contents are byte-for-byte unchanged after communication.
   - A socket identity mismatch fails instead of routing to another agent.
   - Extension-level tests reject a second external send before the prior one settles.

4. **Waiting semantics**
   - `wait --after N` ignores generation `N` and wakes on `N+1`.
   - Waiting without `--after` does not treat an older settled generation as completion of a newer working generation.
   - Timeout exits `124`, emits versioned JSON, and leaves the pane alive.
   - Stale report identity is reset by the generic lifecycle reporter.

5. **Compatibility boundaries**
   - `dotfiles-workflow agents --cwd` returns the same stable identities.
   - `dotfiles-workflow send --pane` resolves to the native transport.
   - `dotfiles-workflow send --no-submit` fails explicitly.
   - Bare `waystation` remains the TUI entrypoint (covered by `scripts/qa`).
   - Neovim setup loads after its migration to stable IDs/native send.

6. **Cleanup**
   - Only the private tmux server and owned `/tmp/qa-waystation-agent-api-*` root are removed.
   - Cleanup runs on success, failure, and interruption.
