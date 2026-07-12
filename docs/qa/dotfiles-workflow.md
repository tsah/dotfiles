# Dotfiles workflow QA plan

> Safety: use a disposable repository under `/tmp`. Do **not** destroy existing tmux sessions or real worktrees. Every destructive scenario below operates only on names prefixed `qa-workflow-`.

## Automated safe checks

1. Run `bash -n` on every changed shell script and `zsh -n zshrc`.
2. Run `bun run check` in `alt-k-tui/`.
3. Run `nvim --headless '+lua require("pi_tmux").setup()' +qa`.
4. Run `git grep` for removed entrypoints (`spawn-pi-tworker`, `remote-tworker`, `tmux-session-switcher-live`) and classify any documentation-only matches.
5. Run installers with temporary `HOME`, `DOTFILES_DIR` pointing here, and pre-create an unmanaged regular file at one manifest destination. Confirm installation refuses to replace it. Then use an empty HOME, install twice, remove one temporary manifest row, and confirm only its ledger-owned symlink is removed.

## Disposable repository fixture

1. Create `/tmp/qa-workflow-origin`, initialize git, commit one file, and configure Worktrunk as normally documented by `wt`.
2. Record `tmux list-sessions` and `git worktree list` before each scenario; use a dedicated tmux socket (`tmux -L qa-workflow`) where command injection permits it.
3. Run `dotfiles-workflow identity` from the main checkout and a linked checkout. Verify canonical paths differ and `commonDir` is identical.

## Session and worker behavior

1. Run `worker-pi qa-workflow-one 'Reply with done only'`. Verify Worktrunk performs its native setup, a lazy `repo@qa-workflow-one` session appears, window `main` remains, and a tagged `pi` window exists.
2. Launch a second `agent-pi` in that worktree. Verify `pi-2` appears and neither agent replaces `main`.
3. Create a synthetic tmux session with the expected human name but another path, then spawn. Verify the new display name gains a stable eight-character suffix. Repeat and verify no duplicate session.
4. Run Pi with `--wait`; verify output arrives only after `agent_settled`. Set `DOTFILES_WORKER_WAIT_TIMEOUT=1` for a long prompt; verify timeout is nonzero and the worker remains attachable.
5. Launch Claude and verify `ANTHROPIC_API_KEY` is absent in its process environment. Launch OpenCode and verify it retains normal unrestricted filesystem access.

## Picker

1. From tmux, press Alt-K; from bash/zsh run `s`. Verify all open the same UI.
2. Verify sessions, Worktrunk/zoxide configured directories, branch, dirty marker, and every agent window are visible. Verify Enter attaches/switches to the selected target.
3. In the disposable repository only, exercise spawn-session and deletion actions. Clean/pushed deletion needs one simple confirmation; dirty, untracked, or unpushed states require typing the displayed branch. Cancel each confirmation once and verify no mutation. Then confirm and compare Worktrunk/tmux state.

## Neovim

1. Open a tracked file in the disposable worktree with zero, one, then two tagged agent windows. Verify zero reports no candidates, one auto-targets, and two opens the selector.
2. Exercise `AgentSendReference`, `AgentSendContents`, and `AgentAppendContext` over no range and a visual range. Verify default payload includes path and range. Verify append does not submit.
3. Modify without saving and send contents. Test save, send contents, and cancel independently. Verify disk state and received payload.
4. Exercise `AgentFocus`, `AgentChoose`, and `AgentSpawn`. Confirm another worktree's agents never appear.
5. Confirm delivery uses `tmux load-buffer`/`paste-buffer`, reports command failure, and does not inspect pane screen text or retry.

## Self-destruction

In the disposable fixture, invoke the self-destruct skill/core. Verify canonical identity before mutation. A clean, pushed branch may proceed without human confirmation. Dirty, untracked, or unpushed variants must request human confirmation and cancellation must preserve both session and worktree.

## Cleanup

Only after comparing against recorded baselines, remove `qa-workflow-*` resources using native Worktrunk and the dedicated tmux socket. Never use broad prune/kill commands.
