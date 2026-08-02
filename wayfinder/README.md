# Waystation

Waystation is a tmux session/directory navigator and headless agent control surface built with Bun, TypeScript, Effect, and OpenTUI. Open the unchanged TUI with bare `waystation`, `Alt-K`, or `s`.

The jump layout is a bottom-sorted selectable tree, with the newest/highest-priority root group nearest the prompt. Session-to-session lineage uses real tree connectors and each row has one color-coded aggregate-state glyph beside its node: roots place it before the disclosure marker, while nested sessions place it immediately after the `├─`/`└─` child connector. Window and agent details stay collapsed by default and their names are summarized inline immediately after the owning session name, without moving status glyphs to the right edge. Small lineage subtrees with one to three direct child sessions begin expanded, as do larger subtrees containing a working or ready agent. Expanding exact details renders subdued `·` rows with their own left-side state glyphs beneath the owning session. The bottom prompt filters the full hierarchy while retaining the complete ancestor context of every matching descendant; non-empty queries show only directly matching detail rows.

The launcher keeps a background cache server running. The server refreshes tmux, opencode, zoxide, process, and git state, then the TUI client reads the latest authoritative JSON cache on startup and restores selection by stable row identity when it can.

Recovery activity is stored by canonical directory path under `$XDG_STATE_HOME/alt-k-tui/activity` (default `~/.local/state/alt-k-tui/activity`), so it survives cache, tmux-server, and machine restarts. Session creation, picker target opening, active tmux work, and agent lifecycle reports update that ledger. Sessionless directories are sorted by the newest durable event, modified/untracked file mtime, worktree HEAD reflog, or commit; zoxide frecency breaks otherwise equal ties. Directory rows show the winning source and age, such as `[edited 12m]` or `[agent 3h]`. Git fallback scans are cached for one minute.

Workspace lineage is stored separately in `$XDG_STATE_HOME/alt-k-tui/workspaces.sqlite3` and projected into each worktree at `.alt-k/workspace.json`. The picker renders that lineage as a real hierarchy. Parent/child lineage metadata still helps searching, and a collapsed lineage parent may show a small child count when useful.

Claude Code state is reported through hooks installed by:

```bash
~/dotfiles/bin/alt-k-install-claude-hooks
```

Those hooks write per-pane state into the same runtime cache directory, keyed by `TMUX_PANE`. Pi uses the globally installed `pi/extensions/tmux-worker-lifecycle.ts` extension for the same purpose, including Pi sessions started directly. It also exposes a mode-`0600` per-process Unix socket and routes incoming messages through native `pi.sendUserMessage`. A Pi pane remains `working` while any in-process subagent is running or queued, even if the parent agent has settled. Reports carry lifecycle and settled generations plus bounded Pi result history. The cache server prefers these structured reports over pane-title heuristics and normalizes state as `blocked`, `working`, `done`, `idle`, or `unknown`. The UI renders those as blinking red `waiting`, animated orange `working`, green `ready`, blue `idle`, and purple `unknown`; plain non-agent windows use a neutral gray `○`. A completed agent remains ready until its pane/window is focused, then becomes idle; a later completion becomes ready again.

## Headless agent API

Every agent has a stable generated ID stored in pane option `@waystation_agent_id`. Tmux supplies discovery and metadata only; the API never uses `send-keys`, buffer paste, or pane capture for agent communication.

```bash
waystation agent list [--cwd PATH]
waystation agent status AGENT_ID
waystation agent capabilities AGENT_ID
waystation agent wait AGENT_ID [--after GENERATION] [--timeout SECONDS]
printf '%s' 'Continue with the tests' | waystation agent send AGENT_ID [--delivery steer|follow-up] [--wait]
waystation agent result AGENT_ID [--generation GENERATION]
```

Successful responses are JSON. Errors are versioned JSON on stderr; unsupported capabilities exit `4`, unavailable native endpoints exit `5`, and nondestructive wait timeouts exit `124`.

Pi supports the complete API through its native socket and lifecycle reports. Busy sends default to a native follow-up, and Waystation admits only one unsettled external message at a time so waits remain correlated. Pi processes that were already running when this update was installed need `/reload` or a restart to advertise the endpoint. Claude and Codex can be listed and can wait on their lifecycle reports, but unverified native send/result operations fail explicitly. OpenCode is currently monitor-only: HTTP mutation and lifecycle waiting remain disabled until its local contract is verified.

Run the TUI directly:

```bash
bun run ~/dotfiles/wayfinder/src/main.tsx
```

Run the cache server directly:

```bash
bun run ~/dotfiles/wayfinder/src/main.tsx --server
```

The `Alt-K` tmux binding launches Waystation. The previous live fzf switcher is kept on `Alt-U` as a fallback.

## Resource-pressure guard

On Linux, `wayfinder-resource-guard` samples guest-kernel memory PSI and `MemAvailable` every five seconds. After one minute of sustained pressure it terminates at most one validated, non-focused Pi, Claude, or OpenCode process per boot. It prefers done/idle agents, then unknown, blocked, and working agents; within a state it chooses the largest process tree. The process is revalidated against its tmux pane, UID, ancestry, start time, harness, and stable agent ID immediately before `SIGTERM`, with `SIGKILL` only after the grace period.

Actions are persisted under `$XDG_STATE_HOME/alt-k-tui/incidents` and appear in the TUI as a red `×` with `terminated`. The daemon also snapshots working, blocked, and unknown agents with the Linux boot ID. If a hard reset changes the boot ID without a clean daemon shutdown, the lost sessions reappear as red `×` entries labeled `lost on reboot`. An orderly reboot does not create crash incidents.

EC2 needs no special metrics API: PSI and `/proc/meminfo` report pressure inside the instance, which is exactly what the guard needs. On swapless EC2 instances the default reserve is the larger of 512 MiB or 10% of RAM; elsewhere it is 7.5% of RAM. CPU credits and host-level steal time are separate concerns and do not affect this memory-pressure decision.

```sh
systemctl --user status wayfinder-resource-guard
journalctl --user -u wayfinder-resource-guard
wayfinder-resource-guard --once --dry-run
```

Thresholds can be overridden with `RESOURCE_GUARD_SAMPLES`, `RESOURCE_GUARD_INTERVAL`, `RESOURCE_GUARD_EC2_FLOOR_MIB`, `RESOURCE_GUARD_EC2_PERCENT`, `RESOURCE_GUARD_GENERIC_PERCENT`, `RESOURCE_GUARD_PSI_SOME`, `RESOURCE_GUARD_PSI_FULL`, and `RESOURCE_GUARD_TERM_GRACE`. Set `RESOURCE_GUARD_DRY_RUN=1` to audit selections without signaling processes. The server must keep the user systemd manager running after logout (normally via `loginctl enable-linger $USER`).

Useful CLI inspection/repair commands:
- `dotfiles-workflow workspace show --cwd PATH`
- `dotfiles-workflow workspace tree --cwd PATH`
- `dotfiles-workflow workspace project --cwd PATH`
- `dotfiles-workflow workspace reconcile --cwd PATH`
- `dotfiles-workflow workspace bootstrap --cwd PATH`

Controls:
- `Up/Down`: move between session rows and nested window/agent children
- `Right`: first expand hidden lineage children for the selected session, then expand its exact detail rows
- `Left`: jump from a detail to its session, collapse exact detail rows first, then collapse lineage children, then jump to the lineage parent
- `Enter`: switch to the exact selected session/window/agent target or advance the current flow; Enter on zero matches does nothing
- `Alt-R`: rename the selected tmux session without changing its worktree identity
- `Alt-A`: search valid parent workspaces and attach the selected workspace beneath one
- `Alt-L`: detach the selected workspace from its parent, making its existing subtree top-level
- Type or paste: structured fuzzy-filter rows and fill the branch/base form; current selection is preserved when it still matches
- `Alt-K` while Waystation is open: choose a repository, then open an existing worktree/branch or type a new branch name to create it
- `Ctrl-R`: refresh remotes while in the branch picker
- `Alt-D`: confirm and destroy the selected pane; destroying a session's final pane also destroys its linked worktree and session
- `Esc`: clear search, move back one flow step, or close
- `Ctrl-C`: close

On startup, the tmux session containing the popup is selected when it appears in the jump list. Renaming stays inside Waystation and preserves the session's canonical path metadata and included agents.

Run checks, model/API tests, and the isolated real-terminal smoke test with:

```bash
bun run check
bun test
scripts/qa
```

Capture a deterministic lineage render from a disposable real OpenTUI fixture with:

```bash
ALT_K_TUI_QA_ROOT=/tmp/qa-alt-k-lineage ALT_K_TUI_QA_KEEP=1 ALT_K_TUI_QA_VISUAL=1 scripts/qa
```

Then either inspect `/tmp/qa-alt-k-lineage/lineage-render.txt` or attach live with `tmux -S /tmp/qa-alt-k-lineage/outer.sock attach -t harness`. The capture should show session-only lineage connectors, inline `main`/agent summaries, and subdued bullet detail rows for an explicitly expanded child session.

The branch flow always begins with the repository picker; it never infers a repository from the current pane or selected jump target. Selecting a repository immediately shows cached refs and starts `git fetch --all --prune` in the background; remote rows are ordered by most recent commit and refresh when the fetch settles. In the branch picker, a query without an exact branch match adds a `create new branch` row. Selecting it asks for the base before creating the worktree and session. Alt-B opens the same TUI directly at the repository picker.

Not implemented yet:
- `Ctrl-Y` copy PR URL
