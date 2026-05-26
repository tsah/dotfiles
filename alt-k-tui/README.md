# Alt-K TUI Prototype

Experimental tmux session and directory switcher built with Bun, TypeScript, Effect, and OpenTUI.

The layout is a compact fzf-like list with a bottom prompt, inline agent state badges, right-aligned git metadata, and a details box for the selected row.

Run directly:

```bash
bun run ~/dotfiles/alt-k-tui/src/main.tsx
```

The `alt+k` tmux binding launches this TUI. The previous live fzf switcher is kept on `alt+u` as a fallback.

Controls:
- `Up/Down`: move selection
- `Enter`: switch to the selected tmux session, agent pane, or zoxide directory
- Type: fuzzy filter rows
- `Esc`: clear search when searching, otherwise close
- `Ctrl-C` or `Alt-K`: close

Not implemented yet:
- `Ctrl-D` worktree/session destroy confirmation
- `Ctrl-Y` copy PR URL
