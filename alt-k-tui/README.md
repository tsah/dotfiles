# Alt-K TUI Prototype

Experimental tmux session and directory switcher built with Bun, TypeScript, Effect, and OpenTUI.

The layout is a compact fzf-like list with a bottom prompt, inline agent state badges, right-aligned git metadata, and a details box for the selected row.

The launcher keeps a background cache server running. The server refreshes tmux, opencode, zoxide, process, and git state, then the TUI client reads the latest JSON cache on startup.

Claude Code state is reported through hooks installed by:

```bash
~/dotfiles/bin/alt-k-install-claude-hooks
```

Those hooks write per-pane state into the same runtime cache directory, keyed by `TMUX_PANE`. Pi uses the globally installed `pi/extensions/tmux-worker-lifecycle.ts` extension for the same purpose, including Pi sessions started directly. The cache server prefers these structured reports over pane-title and pane-content heuristics.

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
- `Up/Down`: move selection
- `Enter`: switch to the selected target or advance the current flow
- `Alt-R`: rename the selected tmux session without changing its worktree identity
- Type or paste: fuzzy filter rows and fill the branch/base form
- `Alt-K` while the picker is open: choose a repository, then open an existing worktree/branch or type a new branch name to create it
- `Ctrl-R`: refresh remotes while in the branch picker
- `Alt-D`: delete the selected worktree/session
- `Esc`: clear search, move back one flow step, or close
- `Ctrl-C`: close

On startup, the tmux session containing the popup is selected when it appears in the jump list. Renaming stays inside the TUI and preserves the session's canonical path metadata and included agents.

The branch flow always begins with the repository picker; it never infers a repository from the current pane or selected jump target. Selecting a repository immediately shows cached refs and starts `git fetch --all --prune` in the background; remote rows are ordered by most recent commit and refresh when the fetch settles. In the branch picker, a query without an exact branch match adds a `create new branch` row. Selecting it asks for the base before creating the worktree and session. Alt-B opens the same TUI directly at the repository picker.

Not implemented yet:
- `Ctrl-Y` copy PR URL
