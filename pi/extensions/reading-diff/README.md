# Pi reading diff

`/reading-diff` creates a compact, source-constrained view of a Git diff. It asks Pi's **currently selected model**, using Pi's resolved authentication, to choose immutable physical-line ranges. The extension validates that plan and mechanically renders only selected original lines, deterministic omission markers, and the model's one-line summary.

## Usage

```text
/reading-diff                         # unstaged tracked changes (git diff)
/reading-diff --staged                # staged tracked changes
/reading-diff --range main...HEAD     # one Git revision expression
/reading-diff --input                 # explicitly paste a diff in Pi's editor
/reading-diff --help
```

The command is TUI-only so selection, cancellation, errors, and the rendered transcript entry have a predictable interface. Press Escape while the planning loader is visible to cancel. The generated entry is session metadata and is not added to later model context.

## Privacy and safety

- Default, staged, and range modes invoke `git` directly with an argument vector, `--no-ext-diff`, `--no-textconv`, `--no-color`, and a terminating `--`. No shell or pager is involved.
- Git-based modes expose only Git's diff of tracked paths. Untracked and ignored files are never enumerated or read. V1 offers no repository context-reading tools.
- Input mode sends only text the user explicitly pasted.
- The diff is sent to the current model provider. Nothing is sent if the selection is empty, unsafe, or over the local limits.
- Input is capped at 200 KiB, 4,000 physical lines, and 16 KiB per line. Terminal control characters are rejected. Model output, summary, range count, coordinates, ordering, and schema are deterministically bounded and validated.
- The extension does not write to the reviewed repository.

This is an original, intentionally smaller TypeScript implementation inspired by Bold Software's Apache-2.0-licensed [Meat](https://github.com/boldsoftware/meat) design at revision `f39f41dfe7b5b37a12b35fdfbaecc7e779855bd3`: model-selected immutable source coordinates followed by deterministic compilation. It does not copy Meat's implementation, prompt, or test fixtures and does not implement Meat's language-aware import, fold, move, or structural-diff compiler.
