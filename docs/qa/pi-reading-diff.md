# Pi reading-diff extension QA plan

> Safety: run Git scenarios only in this isolated worktree or a disposable repository. Do not run destructive commands, modify the repository under review through the extension, kill unrelated tmux sessions, or install into the real home directory during QA.

## Automated checks

1. Run the focused core suite:
   ```bash
   bun test pi/extensions/reading-diff/core.test.ts
   ```
   Expected: all parser, command argument, structural chunking, coordinate remapping, plan-schema, bounds, prompt-injection labeling, terminal-control rejection, and source-constrained rendering tests pass.
2. Bundle the runtime entry point while leaving Pi-provided packages external:
   ```bash
   out=$(mktemp -d)
   bun build pi/extensions/reading-diff/index.ts --target=node --outdir "$out" \
     --external '@earendil-works/pi-ai' --external '@earendil-works/pi-ai/*' \
     --external '@earendil-works/pi-coding-agent' --external '@earendil-works/pi-tui'
   rm -rf "$out"
   ```
   Expected: the entry point and local core module bundle without errors.
3. In a temporary `HOME`, run `DOTFILES_DIR="$PWD" bin/dotfiles-install server` twice. Verify `~/.pi/agent/extensions/reading-diff` is a symlink to this repository's extension directory and both runs succeed. Do not run the installer against the real home during QA.
4. Inspect the changed extension for forbidden behavior:
   ```bash
   git grep -nE 'exec\(|spawn|shell|readFile|writeFile|fetch\(|https?://' -- pi/extensions/reading-diff
   git diff --check
   ```
   Expected: Git is spawned only with a fixed executable, argument array, `shell: false`, bounded stdout/stderr, disabled optional locks/fsmonitor, and cancellation; there are no repository file reads/writes, browser/network calls other than Pi's model API, or whitespace errors. The README's Meat URL is documentation only.

## Disposable Git privacy and selection checks

Create a disposable repository containing committed `tracked.txt`, ignored `secret.txt`, and untracked `untracked.txt`. Change the tracked file in both index and worktree as needed.

1. Default: `/reading-diff`. Expected: only unstaged tracked changes are sent and represented; staged-only, ignored, and untracked content is absent.
2. Staged: `/reading-diff --staged`. Expected: only staged tracked changes are sent and represented.
3. Range: `/reading-diff --range HEAD~1..HEAD` (after making two commits). Expected: only that revision diff is sent. An invalid range reports `Git diff failed` and renders no entry.
4. Input: `/reading-diff --input`, paste a small unified diff, and submit the editor. Expected: only explicitly pasted text is sent; cancellation from the editor renders nothing.
5. Put a repository-configured external diff driver, textconv driver, and pager in the fixture, each writing a sentinel if executed. Expected: no sentinel is created because the extension supplies `--no-ext-diff`, `--no-textconv`, invokes Git without a shell, and does not invoke a pager.
6. Put unique canaries in ignored and untracked files, complete default/staged/range model calls, and inspect provider request logging only in an account/environment approved for such logging. Expected: neither canary occurs. If request logging is unavailable, record this scenario as unexecuted rather than inferring it from the rendered output.
7. Record `git status --porcelain=v1` before and after every command. Expected: byte-for-byte identical status; the extension creates no reviewed-repository files.

## Tmux/manual Pi scenarios

Use one clearly named QA window (for example `qa-reading-diff`) in this clanker's existing workshop session, launch `pi -e "$PWD/pi/extensions/reading-diff/index.ts"`, and remove only that window afterward.

1. Startup: inspect Pi's Extensions list. Expected: `reading-diff` is present and there are no startup errors.
2. Help and argument errors: run `/reading-diff --help`, `/reading-diff --staged --input`, `/reading-diff --range`, and `/reading-diff --range --output=/tmp/x`. Expected: clear usage/safe-revision errors, no model call, and no reading-diff entry.
3. Empty selection: in a clean disposable worktree run default and staged modes. Expected: `The selected diff is empty.` and no model call/entry.
4. Successful current-model path: make a small tracked change and run the relevant selection. Expected: loader names the active `provider/model`; success produces a durable transcript entry containing one `Summary:` line, exact selected source lines, and only `... N physical line(s) omitted ...` between them. It does not create a user/assistant message or trigger an extra agent turn.
5. Source constraint: compare every visible non-summary, non-marker output line against the original selected diff. Expected: every such line occurs byte-for-byte in the normalized original diff; no model-authored source line is possible.
6. Cancellation: run a sufficiently large valid selection and press Escape while the planning loader is active. Expected: `Reading diff cancelled.`, no entry, and no late entry/error after the provider request settles.
7. Authentication/model errors: in an isolated Pi invocation with no selected model, and then with a model lacking resolved auth, invoke the command. Expected: explicit `No Pi model is selected.` or authentication error and no entry. Do not alter the normal user's stored credentials.
8. Malformed model plans: with a test provider or recorded response fixture, return fenced JSON, prose, unknown keys, out-of-bounds/overlapping/adjacent ranges, multiline/control-bearing/oversized summary, empty ranges, and over-limit output. Expected: deterministic validation error and no entry in each case.
9. Bounds and chunking: try empty input, a 4,410-line diff, more than 2 MiB, more than 40,000 lines, one line over 16 KiB, CRLF input, and input containing ESC or lone CR. Expected: the 4,410-line diff is split at file/hunk boundaries into bounded model calls and renders one combined source-constrained result; empty/overall-oversized/control cases fail before a model request; CRLF is normalized and accepted.
10. Exit the QA Pi normally and kill only the named QA window if it remains. Expected: unrelated windows and sessions are unchanged.

## Executed results

Record the date, worktree, exact commands, counts, and any limitations here. Never mark a scenario passed unless it was actually executed.

### 2026-08-04 — `/home/tsah/dotfiles.pi-reading-diff`

Executed:

- `bun test pi/extensions/reading-diff/core.test.ts` — **20 passed, 0 failed, 42 assertions** (Bun 1.3.14).
- The documented `bun build ... --external ...` command — **passed**, 2 modules bundled; `index.js` was 15.97 KiB in a removed temporary directory.
- `git diff --cached --check` — **passed with no output**.
- `git grep -nE 'exec\\(|spawn|shell|readFile|writeFile|fetch\\(|https?://' -- pi/extensions/reading-diff` — inspected all six matches: the only runtime process call is `spawn("git", argv, { shell: false, ... })`; remaining matches are tests/documentation and the documented Meat URL. No file read/write, browser, `fetch`, or shell execution exists.
- Temporary-home installer reconciliation, twice:
  `HOME=/tmp/qa-reading-diff-home.ThJzsF DOTFILES_DIR="$PWD" bin/dotfiles-install server` — **both passed**; the resulting link target was `/home/tsah/dotfiles.pi-reading-diff/pi/extensions/reading-diff`. The temporary home was removed.
- Disposable Git fixture `/tmp/qa-reading-diff-git.*` with staged, unstaged, ignored, and untracked canaries plus configured external diff/pager sentinel — **passed**. Default output contained only `unstaged-canary`; staged output contained only `staged-canary`; neither contained ignored/untracked canaries; sentinel remained absent. Observed bounded outputs were 148 and 137 bytes. Fixture was removed.
- Visible tmux QA window `qa-reading-diff`, launched with
  `PI_TUI_WRITE_LOG=/tmp/qa-reading-diff.ansi pi -e "$PWD/pi/extensions/reading-diff/index.ts"` — Pi 0.83.0 listed `reading-diff` under Extensions with no startup error. `/reload` also succeeded after implementation changes.
- In that window, default `/reading-diff` using the configured `openai-codex/gpt-5.6-sol` model at medium thinking — **passed**. Collapsed output showed only `Summary: Adds the reading-diff extension directory to the installation manifest.` Expanding with the configured tool expansion key showed exact original `install-manifest.tsv` diff lines plus deterministic omission markers. The untracked extension/docs files were absent from the selected Git diff.
- Cancellation in the same window: submit `/reading-diff`, then Escape during the loader — **passed** with `Reading diff cancelled.` No second summary or late error appeared afterward.
- Manual argument errors in the same window — `/reading-diff --staged --input` produced exact usage; `/reading-diff --range --output=/tmp/x` produced the safe-revision error; neither rendered an entry.

Not executed: provider-request canary logging; keyless/ambient-auth provider; missing-auth/model invocation; staged/range/input end-to-end model calls; malformed-plan responses through a fake provider; Git timeout/oversized live-process cases; empty clean-worktree TUI case. These remain manual scenarios above and are **not claimed as passed**. No standalone TypeScript compiler was available; runtime loading, hot reload, bundling, tests, and two real current-provider calls were executed instead.

### 2026-08-04 — large-diff chunking follow-up

Executed in tmux session `dotfiles@master` (`$1`), current-worktree window `qa-reading-diff-chunking` (`@65`), without another clanker or separate workshop:

- `bun test pi/extensions/reading-diff/core.test.ts` — **25 passed, 0 failed, 53 assertions**. Added coverage for the former 4,000-line failure, file/hunk boundary preference, oversized-hunk fallback splitting, lossless line preservation, local-to-global coordinate mapping, boundary-range merging, and bounded UTF-8 summary combination.
- `bun /tmp/qa-reading-diff-chunking.ts` — **passed**. A synthetic 4,410-line diff was accepted and losslessly split into two chunks starting at global physical lines 1 and 3,501; combined rendering retained global source coordinates and deterministic omission markers.
- `bun build pi/extensions/reading-diff/index.ts --target=node ...` — **passed**, 2 modules bundled (`index.js`, 20.12 KiB) in a removed temporary directory.
- `git diff --check` — **passed with no output**.

Not executed for this follow-up: a live provider call over all chunks. The deterministic chunking/remapping path and extension bundle were exercised, but multi-request provider behavior should be confirmed by rerunning the original 4,410-line `/reading-diff` after `/reload`.
