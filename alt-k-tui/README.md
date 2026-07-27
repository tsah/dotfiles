# Alt-K TUI Prototype

Experimental tmux session and directory switcher built with Bun, TypeScript, Effect, and OpenTUI.

The jump layout is a bottom-sorted selectable tree. Every session row remains selectable, its own windows/agents stay nested immediately beneath it, and lineage children render as real recursive subtrees with tree connectors. Sessions whose direct expanded content totals one to three items (selectable details plus child sessions) begin expanded; larger trees begin collapsed. The bottom prompt filters the full hierarchy while retaining the complete ancestor context of every matching descendant.

The launcher keeps a background cache server running. The server refreshes tmux, opencode, zoxide, process, and git state, then the TUI client reads the latest JSON cache on startup.

Recovery activity is stored by canonical directory path under `$XDG_STATE_HOME/alt-k-tui/activity` (default `~/.local/state/alt-k-tui/activity`), so it survives cache, tmux-server, and machine restarts. Session creation, picker target opening, active tmux work, and agent lifecycle reports update that ledger. Sessionless directories are sorted by the newest durable event, modified/untracked file mtime, worktree HEAD reflog, or commit; zoxide frecency breaks otherwise equal ties. Directory rows show the winning source and age, such as `[edited 12m]` or `[agent 3h]`. Git fallback scans are cached for one minute.

Workspace lineage is stored separately in `$XDG_STATE_HOME/alt-k-tui/workspaces.sqlite3` and projected into each worktree at `.alt-k/workspace.json`. The picker renders that lineage as a real hierarchy, while subtle markers still help searching: `↖` means the workspace is derived from another active workspace, and `⇣N` means it currently has `N` active child workspaces.

Claude Code state is reported through hooks installed by:

```bash
~/dotfiles/bin/alt-k-install-claude-hooks
```

Those hooks write per-pane state into the same runtime cache directory, keyed by `TMUX_PANE`. Pi uses the globally installed `pi/extensions/tmux-worker-lifecycle.ts` extension for the same purpose, including Pi sessions started directly. The cache server prefers these structured reports over pane-title heuristics and normalizes state as `blocked`, `working`, `done`, `idle`, or `unknown`. The UI renders those as blinking red `waiting`, animated orange `working`, green `ready`, blue `idle`, and purple `unknown`; plain non-agent windows use a neutral gray `○`. A completed agent remains ready until its pane/window is focused, then becomes idle; a later completion becomes ready again.

Run directly:

```bash
bun run ~/dotfiles/alt-k-tui/src/main.tsx
```

Run the cache server directly:

```bash
bun run ~/dotfiles/alt-k-tui/src/main.tsx --server
```

The `alt+k` tmux binding launches this TUI. The previous live fzf switcher is kept on `alt+u` as a fallback.

Useful CLI inspection/repair commands:
- `dotfiles-workflow workspace show --cwd PATH`
- `dotfiles-workflow workspace tree --cwd PATH`
- `dotfiles-workflow workspace project --cwd PATH`
- `dotfiles-workflow workspace reconcile --cwd PATH`
- `dotfiles-workflow workspace bootstrap --cwd PATH`

Controls:
- `Up/Down`: move between session rows and nested window/agent children
- `Right`: expand the selected session
- `Left`: jump from a detail to its session, collapse an expanded session, or jump from a collapsed nested session to its lineage parent
- `Enter`: switch to the exact selected session/window/agent target or advance the current flow
- `Alt-R`: rename the selected tmux session without changing its worktree identity
- Type or paste: fuzzy filter rows and fill the branch/base form
- `Alt-K` while the picker is open: choose a repository, then open an existing worktree/branch or type a new branch name to create it
- `Ctrl-R`: refresh remotes while in the branch picker
- `Alt-D`: confirm and destroy the selected pane; destroying a session's final pane also destroys its linked worktree and session
- `Esc`: clear search, move back one flow step, or close
- `Ctrl-C`: close

On startup, the tmux session containing the popup is selected when it appears in the jump list. Renaming stays inside the TUI and preserves the session's canonical path metadata and included agents.

Run the model tests and isolated real-terminal smoke test with:

```bash
bun test
scripts/qa
```

Capture a deterministic lineage render from a disposable real OpenTUI fixture with:

```bash
ALT_K_TUI_QA_ROOT=/tmp/qa-alt-k-lineage ALT_K_TUI_QA_KEEP=1 ALT_K_TUI_QA_VISUAL=1 scripts/qa
```

Then either inspect `/tmp/qa-alt-k-lineage/lineage-render.txt` or attach live with `tmux -S /tmp/qa-alt-k-lineage/outer.sock attach -t harness`.

The branch flow always begins with the repository picker; it never infers a repository from the current pane or selected jump target. Selecting a repository immediately shows cached refs and starts `git fetch --all --prune` in the background; remote rows are ordered by most recent commit and refresh when the fetch settles. In the branch picker, a query without an exact branch match adds a `create new branch` row. Selecting it asks for the base before creating the worktree and session. Alt-B opens the same TUI directly at the repository picker.

Not implemented yet:
- `Ctrl-Y` copy PR URL
