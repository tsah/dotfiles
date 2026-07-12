# Local worktree workflow

## Architecture

Worktrunk is authoritative for worktree creation, setup hooks, switching, and destruction. Stock `wt` remains the native Worktrunk executable: this repository intentionally provides no `bin/wt`, compatibility wrapper, or parallel worktree manager. `alt-k-tui/src/workflow.ts` invokes native Worktrunk and adds only tmux and local agent orchestration; `bin/dotfiles-workflow` is its stable shell boundary.

A worker is identified by its canonical worktree path. Repository identity comes from `git rev-parse --git-common-dir`. Tmux session names are display labels (`repo@branch`) with an eight-character path hash only when that label collides. The canonical path and common dir are recorded as tmux user options. Never use a tmux name as identity.

Sessions are created lazily. Their stable `main` window is retained; every agent gets a dedicated, uniquely named window. `worker-pi`, `worker-claude`, and `worker-opencode` are thin harness adapters. `agent-*` starts another agent in the current worktree. OpenCode is not filesystem-sandboxed. Repository agent configuration takes precedence over personal configuration through each harness's native lookup.

The Alt-K picker is the shared interactive entrypoint (`workspace-picker`, and shell function `s`). It combines tmux sessions, worktrees/configured directories, git state, and agent state. Worktree creation/destruction remains delegated to native Worktrunk so its setup and confirmation behavior remains authoritative.

Pi settled waiting uses `agent_settled`, not `agent_end`. A timeout reports failure but deliberately leaves the window and worktree running. Neovim considers only agent windows tagged with the canonical current worktree path. It auto-targets exactly one; otherwise it uses `vim.ui.select`. Sending uses tmux's acknowledged buffer APIs. It never reads pane screen contents or retries blind.

## Milestones and acceptance criteria

1. **Identity and orchestration:** canonical path/common-dir identity; lazy collision-safe session; stable main window; multiple agent windows; thin harness adapters; native `wt spawn` setup.
2. **One navigation surface:** Alt-K and `s` invoke one picker; picker displays sessions, configured/zoxide directories, git and agent status; no legacy switcher or remote-worker process remains.
3. **Editor and agent lifecycle:** unified `Agent*` commands, current-worktree filtering, explicit unsaved-buffer choice, settled Pi wait, verified self-destruction boundary.
4. **Distribution:** one desktop/server manifest, only ledger-owned stale links reconciled, neutral skills under `skills/`, obsolete entrypoints absent.

See [the executable QA plan](qa/dotfiles-workflow.md).
