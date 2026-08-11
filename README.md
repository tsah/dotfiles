# Tsah's dotfiles

This repository is used on two machine profiles:

- **Main laptop**: Arch Linux + Omarchy desktop
- **Dev machine**: EC2 Linux server (headless)

Use the matching install scripts for each profile.

## Clankerhouse

`clankerhouse` opens the product's interactive tmux/worktree TUI. `clankers` is
the primary CLI. A **workshop** is a durable worktree plus its canonical/lazy
tmux-session container; a **clanker** is one visible Pi, Claude, OpenCode, or
Codex harness session inside it. Harness-native in-process subagents are not
clankers.

```bash
clankers workshop spawn --name feature-x --harness pi
clankers spawn --workshop feature-x --name reviewer --harness claude
clankers list --cwd "$PWD"
clankers status CLANKER_ID
clankers capabilities CLANKER_ID
clankers wait CLANKER_ID --after GENERATION
printf '%s' 'Review the latest changes' | clankers send CLANKER_ID --wait
clankers result CLANKER_ID
```

The first command asks Worktrunk to create branch/worktree `feature-x`, records
the workshop, lazily ensures its tmux session and stable `main` window, then
starts its initial Pi clanker. The second adds a `reviewer` window to that same
workshop without creating a worktree or lineage edge. Omitted prompts default to
`Ready for instructions.` Names are labels; the returned `clankerId` is identity.

Pi send/result communication is native through the globally installed lifecycle
extension's per-process Unix socket. Tmux is discovery and metadata only;
unsupported harness transports fail explicitly instead of injecting terminal
input. Pi, Claude, and OpenCode launches also persist exact native session
identity and desired state; the one-shot boot recovery service automatically
recreates and continues them once after a hard reboot. It does not resurrect a
clanker that is later interrupted with Ctrl-C; same-boot tmux recovery is an
explicit service restart or reconciliation. EC2 Spot notices are a checkpoint
fast path rather than a recovery dependency. See
[`clankerhouse/README.md`](clankerhouse/README.md),
[`clankerhouse-tui.md`](clankerhouse-tui.md),
[`docs/qa/clanker-api.md`](docs/qa/clanker-api.md), and
[`docs/qa/clankerhouse-recovery.md`](docs/qa/clankerhouse-recovery.md).

## Main laptop (Omarchy)

```bash
./install-packages.sh
./install-omarchy.sh
```

- Installs desktop packages for Omarchy/Hyprland.
- Ensures `neovim` stable is installed (and removes `neovim-git` if present).
- Applies local symlinks and desktop config.
- Bootstraps Neovim Mason LSP servers used by this config.

## Dev machine (EC2)

Use these scripts on Linux servers (Amazon Linux 2023 tested):

```bash
./install-server-packages.sh
./install-server.sh
```

- `install-server-packages.sh` installs shell and CLI tooling used by this repo.
- `install-server-packages.sh` also installs an `xterm-ghostty` terminfo shim so tmux works when SSHing from Ghostty.
- Neovim installs from `stable` by default (`NEOVIM_CHANNEL=nightly ./install-server-packages.sh` to opt into nightly).
- `install-server.sh` creates symlinks for dotfiles and config files.

## Linear skill

The shared `linear` skill gives Pi, Claude Code, and OpenCode the ability to
search and inspect Linear data and, after explicit confirmation, create or
update issues and add comments. It replaces OpenCode's remote Linear MCP.
Create a least-privilege Linear personal API key in `~/.env`, then restart the
harness:

```bash
export LINEAR_API_KEY="..."
```

The normal installers link the skill into each harness and install its pinned
SDK dependency. Ask the harness to work with Linear; in Pi, it can also be
invoked explicitly with `/skill:linear`.

## Notes

- Do not run `install-omarchy.sh` on EC2/dev servers.
- Run `dotfiles-doctor` to check common local setup issues after installing or changing symlinks. It reports missing commands, broken config links, and suggests `./install-omarchy.sh` when local symlinks need refreshing.
- If Python LSP is missing on a machine, install it with:

```bash
nvim --headless "+MasonInstall basedpyright" +qa
```
