# Dotfiles workflow QA plan

> Safety: use a disposable repository under `/tmp`. Do **not** destroy existing tmux sessions or real worktrees. Every destructive scenario below operates only on names prefixed `qa-workflow-`.

## Automated safe checks

1. Run `bash -n` on every changed shell script and `zsh -n zshrc`.
2. Run `bun run check` in `alt-k-tui/`.
3. Run `bun test` and `scripts/qa` in `alt-k-tui/`. The latter must use only its private nested tmux sockets and `/tmp/qa-alt-k-tree-$UID-$PID` runtime directory.
4. Run `nvim --headless '+lua require("pi_tmux").setup()' +qa`.
5. Run `git grep` for removed entrypoints and tools (`spawn-pi-tworker`, `remote-tworker`, `tmux-session-switcher-live`, `tmux_subagent`, `tmux_tworker`, `tworker`) and classify any documentation-only matches.
6. With a temporary `HOME`, run `bin/install-pi-packages`; verify `pi list` contains pinned `npm:@tintinweb/pi-subagents@0.14.0`.
7. Run installers with temporary `HOME`, `DOTFILES_DIR` pointing here, and pre-create an unmanaged regular file at one manifest destination. Confirm installation refuses to replace it. Then use an empty HOME, install twice, remove one temporary manifest row, and confirm only its ledger-owned symlink is removed.

## Disposable repository fixture

1. Create `/tmp/qa-workflow-origin`, initialize git, commit one file, and configure Worktrunk as normally documented by `wt`.
2. Record `tmux list-sessions` and `git worktree list` before each scenario; use a dedicated tmux socket (`tmux -L qa-workflow`) where command injection permits it.
3. Run `dotfiles-workflow identity` from the main checkout and a linked checkout. Verify canonical paths differ and `commonDir` is identical.

## In-process Pi subagents

1. Start Pi and verify `Agent`, `get_subagent_result`, and `steer_subagent` are registered while `tmux_subagent`, `tworker`, and `tmux_tworker` are absent.
2. Run foreground and background built-in agents. Verify they complete in-process without creating tmux windows, and background concurrency does not exceed `pi/subagents.json`.
3. Verify only the package's built-in `general-purpose`, `Explore`, and `Plan` types are present unless a project defines additional agents.
4. Confirm package worktree isolation is not used by the documented handoff path.

## Session and worker behavior

1. Run `worker-pi qa-workflow-one 'Reply with done only'`. Verify Worktrunk performs its native setup, a lazy `repo@qa-workflow-one` session appears, and both the stable `main` window and tagged `pi` window remain after successful settlement.
2. Launch `agent-pi` twice in that worktree. Verify `pi-2` and `pi-3` appear and no agent replaces `main` or an existing agent window.
3. Create a synthetic tmux session with the expected human name but another path, then spawn. Verify the new display name gains a stable eight-character suffix. Repeat and verify no duplicate session.
4. Rename a tagged worktree session with native tmux, then run session ensure and agent discovery for that worktree. Verify the renamed session is returned, its existing agents remain visible, its path/common-dir tags remain intact, and no canonical-name duplicate is created. Repeat with a legacy untagged session whose `session_path` is the worktree and verify first use adopts and tags it.
5. Run Pi with `--wait`; verify output arrives only after `agent_settled` and the successful window remains available after signaling. Set `DOTFILES_WORKER_WAIT_TIMEOUT=1` for a long prompt; verify timeout is nonzero and the worker remains attachable.
6. Launch Claude and verify `ANTHROPIC_API_KEY` is absent in its process environment. Launch OpenCode and verify it retains normal unrestricted filesystem access.

## Picker

1. From tmux, press Alt-K; from bash/zsh run `s`. Verify all open the same UI.
2. Verify sessions, Worktrunk/zoxide configured directories, branch, dirty marker, and every agent window are visible. Verify the session containing the Alt-K popup is initially selected and Enter attaches/switches to the selected target.
3. Verify sessions are sorted upward from the bottom prompt, trees with one to three children begin expanded, trees with four or more children begin collapsed, and Left/Right override the default without changing the selected parent. Select a plain window, Pi, Claude, Codex, and OpenCode child independently and verify Enter focuses the exact target. Search for text present only in a collapsed child and verify its parent and matching child remain visible.
4. Seed a completion report and verify it renders green `✓ ready`. Focus that exact child, reopen Alt-K, and verify it renders blue `○ idle`; emit a report with a newer `updatedAt` and verify it returns to `ready`. Verify red `! waiting`, the orange working spinner animates continuously, green `✓ ready`, blue `○ idle`, purple `? unknown`, a neutral gray `○` for plain non-agent windows, aggregate precedence, and legacy `running`/`attention` report compatibility.
5. With Alt-K already open, press Alt-K again and verify the repository picker is always shown, regardless of the highlighted jump row or current pane. Confirm the existing global Alt-N session-cycling binding is unchanged. In the branch screen, verify existing worktrees, local branches without worktrees, and remote-only branches have distinct labels. Select one of each and verify Worktrunk switches or creates the worktree as appropriate before entering its session.
6. In the same branch screen, verify cached refs appear immediately, a background remote fetch is reported, and newly fetched remote branches appear in newest-commit-first order without reopening the picker. Exercise Ctrl-R and a failed non-interactive fetch. Verify the picker remains usable and reports failure without discarding cached refs.
7. Paste a branch name without an exact match and verify the full pasted value appears in one create row. Select it, paste or choose an explicit base, and verify Worktrunk creates the branch/worktree before the picker ensures and enters its session. Verify Ctrl-B has no picker action.
8. Press Alt-R on the selected disposable tmux session parent, paste a new name, and confirm. Verify the row updates, remains selected, included agents remain visible, path/common-dir tags are unchanged, and subsequent session ensure returns the renamed session without creating a duplicate. Verify Alt-R does nothing on a child. Cancel a second rename and verify no change.
9. In the disposable repository only, exercise Alt-D deletion actions from parent and child rows. Cancel the y/n confirmation for a child and verify no mutation, then confirm and verify only that exact pane is destroyed. Select the final pane in another session, cancel once, then confirm and verify the linked worktree and session are both destroyed. Repeat parent deletion for clean/pushed and dirty, untracked, or unpushed worktrees, including legacy sessions without canonical path tags.

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
