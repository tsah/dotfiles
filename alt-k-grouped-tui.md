# Alt-K Grouped TUI

## Problem

The current `alt+k` picker is built on fzf. fzf is excellent for flat fuzzy selection, but grouped session/window layouts are awkward because filtering hides parent rows independently from child rows. That makes hierarchy unreliable: a child row can appear with missing or misleading parent context.

The grouped `alt+k` UI should be a real TUI with explicit session groups, stable focus, and filtering behavior that understands parent-child relationships.

## Information Model

Each tmux session is the primary entity.

Session fields:
- session name
- last attached age/order
- worktree status flags: `wt`, `merged`, `squash`, `dirty`, `missing`
- session path
- agent markers: `opencode`, `pi`, `claude`
- windows/panes summary

Detail row fields:
- window name
- agent type, if any
- opencode/pi/claude status
- task title or pane title
- age/activity
- target window/pane id

Selection behavior:
- selecting a session switches to the session
- selecting an agent/window switches to that session and then selects the target window/pane
- filtering must keep the selected detail pane contextualized by the selected session

## Design: Two-Pane Browser

Left pane lists sessions. Right pane shows windows and agents for the selected session.

```text
Sessions                              Details
> dotfiles@master        wt/dirty     opencode  generating  Instant Alt+D...
  dotfiles                            pi        running     pi - dotfiles
  tweezr@control-m...    wt           other     nvim, zsh, htop
  tweezr/master
```

Filtering behavior:
- query filters sessions by session name, path, child title, agent type, and agent status
- left pane shows only matching sessions
- right pane always shows children for the highlighted session
- matching child rows should cause their parent session to remain in the left pane
- match highlights should appear in both panes where applicable

Why this direction:
- session is the primary navigation unit
- details are always contextualized by the selected session
- it supports both quick session switching and precise agent/window targeting
- it avoids the fzf problem where filtering breaks visible hierarchy
- it stays compact because only one session's details are expanded at a time

## Layout Details

Use a two-column layout:
- left pane: 40-50% width, session list
- right pane: remaining width, selected session details
- top line: query/status bar
- bottom line: key help and transient messages

Left pane row format:

```text
> dotfiles@master                 wt/dirty  oc pi   9s
  tweezr@control-m-backfill...    wt        oc      21m
  tweezr/master                             oc      22h
```

Right pane row format:

```text
dotfiles@master  /home/tsah/dotfiles-newtest

> opencode   generating   Instant Alt+D background launch        9s
  pi         running      pi - dotfiles
  other      nvim, zsh, htop
```

Status flags should be terse and consistent:
- `wt`: worktree-backed session
- `merged`: branch is ancestor of default branch
- `squash`: patch-equivalent to default branch
- `dirty`: worktree has local changes
- `missing`: worktree path no longer exists
- `oc`: has opencode window/pane
- `pi`: has pi window/pane
- `C`: has Claude Code window/pane

## Controls

- `Up/Down`: move session selection in the left pane
- `Tab`: move focus between session list and details
- `Enter`: open selected session or selected detail row
- `Ctrl-D`: confirm and destroy selected worktree/session
- `Ctrl-Y`: copy PR URL for selected worktree/session
- `/`: focus search
- `Esc`: clear search when searching, otherwise close
- `Alt-K`: close

## Implementation Stack

Use:
- Bun as the runtime
- TypeScript as the language
- Effect for data loading, process execution, errors, concurrency, and dependency wiring
- OpenTUI for terminal rendering and input handling

Implementation notes:
- keep tmux/git/opencode data collection isolated behind Effect services
- preserve existing shell/Python data sources initially where practical, then replace them incrementally
- model sessions and detail rows explicitly rather than deriving hierarchy from display strings
- keep filtering in application state, not in the renderer
- make row actions target concrete tmux session/window/pane ids
- avoid fzf-style hidden columns; every row should have a typed action payload

The custom TUI should preserve the current `alt+k` behavior where useful, but replace fzf rendering/filtering with stateful grouping and explicit parent-child relationships.
