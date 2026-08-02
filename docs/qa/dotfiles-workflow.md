# Dotfiles workflow QA plan

> Safety: use a disposable repository under `/tmp`. Do **not** destroy existing tmux sessions or real worktrees. Every destructive scenario below operates only on names prefixed `qa-workflow-`.

## Automated safe checks

1. Run `bash -n` on every changed shell script and `zsh -n zshrc`.
2. Run `bun run check` in `alt-k-tui/`.
3. Run `bun test` and `scripts/qa` in `alt-k-tui/`. The latter must use only its private nested tmux sockets and an owned `/tmp/qa-alt-k-*` root, and any lineage checks must keep their SQLite store under that same disposable root. Verify `ALT_K_TUI_QA_ROOT` rejects paths outside that pattern and refuses to replace an existing root without its `.alt-k-qa-owned` marker.
4. Run `nvim --headless '+lua require("pi_tmux").setup()' +qa`.
5. Run `git grep` for removed entrypoints and tools (`spawn-pi-tworker`, `remote-tworker`, `tmux-session-switcher-live`, `tmux_subagent`, `tmux_tworker`, `tworker`) and classify any documentation-only matches.
6. With a temporary `HOME`, run `bin/install-pi-packages`; verify `pi list` contains pinned `npm:@tintinweb/pi-subagents@0.14.0`.
7. Run installers with temporary `HOME`, `DOTFILES_DIR` pointing here, and pre-create an unmanaged regular file at one manifest destination. Confirm installation refuses to replace it. Then use an empty HOME, install twice, remove one temporary manifest row, and confirm only its ledger-owned symlink is removed.

## Disposable repository fixture

1. Create `/tmp/qa-workflow-origin`, initialize git, commit one file, and configure Worktrunk as normally documented by `wt`.
2. Record `tmux list-sessions` and `git worktree list` before each scenario; use a dedicated tmux socket (`tmux -L qa-workflow`) where command injection permits it.
3. Run `dotfiles-workflow identity` from the main checkout and a linked checkout. Verify canonical paths differ and `commonDir` is identical.
4. Set disposable `XDG_STATE_HOME` and `XDG_RUNTIME_DIR`, run `dotfiles-workflow workspace project`, and verify the SQLite file is created only under the disposable state directory while runtime files stay under the disposable runtime directory.

## In-process Pi subagents

1. Start Pi and verify `Agent`, `get_subagent_result`, and `steer_subagent` are registered while `tmux_subagent`, `tworker`, and `tmux_tworker` are absent.
2. Run foreground and background built-in agents. Verify they complete in-process without creating tmux windows, and background concurrency does not exceed `pi/subagents.json`.
3. Verify only the package's built-in `general-purpose`, `Explore`, and `Plan` types are present unless a project defines additional agents.
4. Confirm package worktree isolation is not used by the documented handoff path.

## Lineage store and manifests

1. In the disposable fixture, run `dotfiles-workflow workspace reconcile` from the main worktree. Verify `.alt-k/workspace.json` exists in each active worktree, `git status --porcelain` stays clean, `.git/info/exclude` contains exactly `/.alt-k/workspace.json`, and the manifest carries durable workspace/repository IDs, canonical path/common dir, branch, parent ID or null, revision, and timestamps.
2. Remove one manifest, rerun `dotfiles-workflow workspace reconcile`, and verify the database rewrites it without changing durable IDs.
3. Delete the disposable SQLite file, run `dotfiles-workflow workspace bootstrap`, and verify `dotfiles-workflow workspace tree` reconstructs the same active graph from manifests alone.
4. Create conflicting manifest cases in a disposable worktree only: tracked file, symlinked `.alt-k` directory, symlinked manifest file, malformed JSON, and valid JSON whose canonical path points elsewhere. Verify `best-effort` worker/session flows keep working, `strict` fails loudly, and none of those files are overwritten.
5. Corrupt or replace the disposable lineage SQLite file. Verify the picker still opens without lineage annotations in default/best-effort mode, while `dotfiles-workflow workspace show|tree|project|reconcile|bootstrap` and other strict administrative lineage commands fail loudly.
6. Seed a disposable lineage database with a newer `PRAGMA user_version` than supported and verify both tests and manual admin commands reject it.
7. Verify store invariants with explicit commands or tests: self-parenting, A→B→A cycles, cross-repo parenting, and one-active-parent reparenting all behave as documented.

## Session and worker behavior

1. Run `worker-pi qa-workflow-one 'Reply with done only'`. Verify Worktrunk performs its native setup, a lazy `repo@qa-workflow-one` session appears, and both the stable `main` window and tagged `pi` window remain after successful settlement.
2. Inspect the caller and child tmux sessions with `tmux show-option -qv`. Verify `@dotfiles_workspace_id` is set on both, the child carries the caller's ID in `@dotfiles_workspace_parent_id`, and `dotfiles-workflow workspace show --cwd <child>` reports the same relationship.
3. From `qa-workflow-one`, run `worker-pi qa-workflow-two 'Reply with done only'`. Verify the nested child links to `qa-workflow-one`, producing `main → qa-workflow-one → qa-workflow-two` in `dotfiles-workflow workspace tree`.
4. Repeat with `worker-pi --no-parent qa-workflow-root 'Reply with done only'` and `worker-pi --parent <workspace-id> qa-workflow-explicit 'Reply with done only'`. Verify `--no-parent` stores `null` and `--parent` reuses the requested parent.
5. Try `worker-pi --parent does-not-exist ...` in both default and strict lineage modes and verify it fails instead of silently rooting. Set `DOTFILES_WORKSPACE_LINEAGE=off` and verify explicit `--parent` is rejected clearly. Also break lineage persistence in the current worktree, run `dotfiles-workflow session --cwd <worktree>` under `strict`, and verify it fails rather than falling back to a plain directory session.
6. Launch `agent-pi` twice in that worktree. Verify `pi-2` and `pi-3` appear and no agent replaces `main` or an existing agent window.
7. Create a synthetic tmux session with the expected human name but another path, then spawn. Verify the new display name gains a stable eight-character suffix. Repeat and verify no duplicate session.
8. Rename a tagged worktree session with native tmux, then run session ensure and agent discovery for that worktree. Verify the renamed session is returned, its existing agents remain visible, its path/common-dir tags, workspace ID, and parent ID remain intact, and no canonical-name duplicate is created. Repeat with a legacy untagged session whose `session_path` is the worktree and verify first use adopts and tags it.
9. Run Pi with `--wait`; verify output arrives only after `agent_settled` and the successful window remains available after signaling. Set `DOTFILES_WORKER_WAIT_TIMEOUT=1` for a long prompt; verify timeout is nonzero and the worker remains attachable.
10. Launch Claude and verify `ANTHROPIC_API_KEY` is absent in its process environment. Launch OpenCode and verify it retains normal unrestricted filesystem access.

## Picker

1. From tmux, press Alt-K; from bash/zsh run `s`; and run `waystation` directly. Verify all open Waystation.
2. Verify sessions, Worktrunk/zoxide configured directories, dirty/activity metadata, inline window or agent names, and every agent window are visible. Verify root rows place their color-coded state glyph before the disclosure marker, nested sessions place it immediately to the right of their `├─`/`└─` child connector, and expanded detail rows place it immediately after their subdued `·` marker, collapsed summary names sit immediately after the session name without right-edge status glyphs, the session containing the Waystation popup is initially selected, and Enter attaches/switches to the selected target.
3. Verify root groups are sorted upward from the bottom prompt with blocked/working live sessions nearest the prompt, followed by ready sessions, idle sessions, neutral/unknown sessions, sessionless worktrees, and plain directories last; verify recency and frecency reorder rows only within those groups. Verify small lineage subtrees with one to three direct child sessions begin expanded, and larger ones begin collapsed. Verify lineage renders as a real recursive hierarchy rather than marker-only hints: each session row stays selectable, lineage child sessions stay contiguous inside the same subtree, and exact window or agent rows appear only as subdued bullet rows under an explicitly expanded session. Exercise Left/Right fully: Right first exposes hidden lineage children, then exact details; Left on a detail jumps to its owning session; Left then collapses exact details before collapsing lineage children and finally jumping to the lineage parent. Verify a leaf session with collapsed inline summaries does not show a misleading collapsed lineage triangle. With a long synthetic list inside the disposable root, drive repeated Up/Down across more than one viewport and confirm the selected row never disappears, skips, or jumps unexpectedly; a centered viewport after leaving the bottom edge is acceptable. Select a plain window, Pi, Claude, Codex, and OpenCode child independently and verify Enter focuses the exact target. Exercise both typed search and bracketed-paste search from the same safe fixture. Search for an exact session name such as `z-root` and verify unrelated rows do not survive through concatenated-field false positives. Search for text present only in a collapsed child detail and verify its full ancestor chain remains visible while unrelated collapsed or explicitly expanded details stay hidden. Clear the query with Backspace, verify zero-match Enter leaves the picker open, and, if practical, rewrite the disposable cache while the picker stays open to confirm vanished rows disappear, refreshed ordering is adopted, and selection restores by stable row identity. Search by workspace ID, parent workspace ID, child-count lineage text, and lineage branch/session names and verify the same parent rows remain discoverable without ordering regressions. In the disposable fixture, record durable activity for one worktree and modify a file in another, restart without their tmux sessions, and verify both sort ahead of an old clean worktree with `[source age]` recovery labels.
4. Seed a completion report and verify it renders green `✓ ready`. Focus that exact child, reopen Alt-K, and verify it renders blue `○ idle`; emit a report with a newer `updatedAt` and verify it returns to `ready`. Verify the red waiting `!` blinks, the orange working spinner animates continuously, green `✓ ready`, blue `○ idle`, purple `? unknown`, a neutral gray `○` for plain non-agent windows, aggregate precedence, and legacy `running`/`attention` report compatibility.
5. With Alt-K already open, press Alt-K again and verify the repository picker is always shown, regardless of the highlighted jump row or current pane. Confirm the existing global Alt-N session-cycling binding is unchanged. In the branch screen, verify existing worktrees, local branches without worktrees, and remote-only branches have distinct labels. Select one of each and verify Worktrunk switches or creates the worktree as appropriate before entering its session.
6. In the same branch screen, verify cached refs appear immediately, a background remote fetch is reported, and newly fetched remote branches appear in newest-commit-first order without reopening the picker. Exercise Ctrl-R and a failed non-interactive fetch. Verify the picker remains usable and reports failure without discarding cached refs.
7. Paste a branch name without an exact match and verify the full pasted value appears in one create row. Select it, paste or choose an explicit base, and verify Worktrunk creates the branch/worktree before the picker ensures and enters its session. Verify Ctrl-B has no picker action.
8. Press Alt-R on the selected disposable tmux session row, paste a new name, and confirm. Verify the row updates, remains selected, included agents remain visible, path/common-dir tags are unchanged, and subsequent session ensure returns the renamed session without creating a duplicate. Repeat on a nested lineage child session row and verify the same guarantees hold. Cancel a second rename and verify no change.
9. In the disposable repository only, exercise Alt-D deletion actions from parent and child rows. Cancel the y/n confirmation for a child and verify no mutation, then confirm and verify only that exact pane is destroyed. Select the final pane in another session, cancel once, then confirm and verify the linked worktree and session are both destroyed. Repeat parent deletion for clean/pushed and dirty, untracked, or unpushed worktrees, including legacy sessions without canonical path tags. Force one disposable Worktrunk removal to fail and verify the picker stays open, displays the command error, and preserves both the session and worktree.
10. Capture a deterministic visual hierarchy from the safe fixture without touching real tmux state:
   ```bash
   cd ~/dotfiles/alt-k-tui
   ALT_K_TUI_QA_ROOT=/tmp/qa-alt-k-lineage ALT_K_TUI_QA_KEEP=1 ALT_K_TUI_QA_VISUAL=1 scripts/qa
   ```
   Then inspect the live render with `tmux -S /tmp/qa-alt-k-lineage/outer.sock attach -t harness` or read the captured pane text at `/tmp/qa-alt-k-lineage/lineage-render.txt`. Confirm the `tweezr@idp-java` subtree visibly contains `tweezr@fix-coverage-hyphenation` and `tweezr@fix-java-failed-tests` with session-only tree connectors, inline `main` or `pi` summaries on compact rows, and subdued bullet detail rows for the explicitly expanded child session.

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
