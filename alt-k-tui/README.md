# Alt-K TUI Prototype

Experimental tmux session and directory switcher built with Bun, TypeScript, Effect, and OpenTUI.

The jump layout is a bottom-sorted selectable tree. Sessions with up to three concrete window/agent targets begin expanded; larger trees begin collapsed. The bottom prompt filters both levels while retaining the parent of every matching child.

The launcher keeps a background cache server running. The server refreshes tmux, opencode, zoxide, process, and git state, then the TUI client reads the latest JSON cache on startup.

Recovery activity is stored by canonical directory path under `$XDG_STATE_HOME/alt-k-tui/activity` (default `~/.local/state/alt-k-tui/activity`), so it survives cache, tmux-server, and machine restarts. Session creation, picker target opening, active tmux work, and agent lifecycle reports update that ledger. Sessionless directories are sorted by the newest durable event, modified/untracked file mtime, worktree HEAD reflog, or commit; zoxide frecency breaks otherwise equal ties. Directory rows show the winning source and age, such as `[edited 12m]` or `[agent 3h]`. Git fallback scans are cached for one minute.

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

Controls:
- `Up/Down`: move between session parents and window/agent children
- `Right/Left`: expand a session or collapse back to its parent
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

The branch flow always begins with the repository picker; it never infers a repository from the current pane or selected jump target. Selecting a repository immediately shows cached refs and starts `git fetch --all --prune` in the background; remote rows are ordered by most recent commit and refresh when the fetch settles. In the branch picker, a query without an exact branch match adds a `create new branch` row. Selecting it asks for the base before creating the worktree and session. Alt-B opens the same TUI directly at the repository picker.

Not implemented yet:
- `Ctrl-Y` copy PR URL
