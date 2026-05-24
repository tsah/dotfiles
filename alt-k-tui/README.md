# Alt-K TUI Prototype

Experimental two-pane tmux session switcher built with Bun, TypeScript, Effect, and OpenTUI.

The layout borrows the useful parts of `ghui`'s terminal UI style: a top status/filter area, explicit pane titles with counts, compact metadata chips, a selected-item summary, dense target rows, and context-aware footer hints.

Run directly:

```bash
bun run ~/dotfiles/alt-k-tui/src/main.ts
```

The existing `alt+k` fzf switcher is intentionally unchanged. A separate tmux binding launches this prototype while it is being evaluated.

Controls:
- `Up/Down`: move session selection or detail selection
- `Tab`: switch focus between sessions and details
- `Enter`: switch to the selected session/detail target
- `/`: focus search
- `Esc`: clear search when searching, otherwise close
- `Ctrl-C` or `Alt-K`: close

Not implemented yet:
- `Ctrl-D` worktree/session destroy confirmation
- `Ctrl-Y` copy PR URL
