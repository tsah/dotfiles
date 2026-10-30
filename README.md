# Tsah's dotfiles

This repository is used on two machine profiles:

- **Main laptop**: Arch Linux + Omarchy desktop
- **Dev machine**: EC2 Linux server (headless)

Use the matching install scripts for each profile.

## Clankerhouse

The tmux configuration installs [tsah/clankerhouse](https://github.com/tsah/clankerhouse)
through TPM. The profile installers install its commands, harness integrations,
and user services under `~/.local`; this repository owns only personal bindings
and client configuration.

## Main laptop (Omarchy)

```bash
./install-packages.sh
./install-omarchy.sh
```

- Installs desktop packages for Omarchy/Hyprland.
- Ensures `neovim` stable is installed (and removes `neovim-git` if present).
- Applies local symlinks and desktop config.
- Bootstraps Neovim Mason LSP servers used by this config.

## Dev machines

From the laptop, provision and register a Linux devbox with one command:

```bash
setup-new-devbox puffin
# Different display name and SSH target:
setup-new-devbox staging tsah@staging.tailnet-name
```

The command clones this repository when necessary, runs the server package and
configuration installers, creates a dedicated browser-forwarding key, creates
and registers a separate GitHub SSH key, and adds the machine to
[`devboxes.tsv`](devboxes.tsv). The browser key is restricted on the laptop to
`bin/xdg-open-from-ssh`; it cannot start a shell. The GitHub private key never
leaves the devbox. Use `--configure-only` for an already-provisioned server,
`--no-services` when Clankerhouse services should remain disabled, or
`--skip-github` when GitHub access is intentionally unnecessary.

`devboxes.tsv` is the committed inventory used by screenshot sharing. Its
columns are a display name, an SSH/scp target, and the remote screenshot
directory. Choosing `remote` in the Omarchy screenshot menu opens a second menu
containing the inventory entries. Manage it directly or idempotently with:

```bash
devbox-inventory list
devbox-inventory upsert puffin puffin /tmp/
```

The underlying scripts remain usable directly on a server (Debian and Amazon
Linux are supported):

```bash
./install-server-packages.sh
./install-server.sh
```

- `install-server-packages.sh` installs shell and CLI tooling used by this repo, including Bun and Yazi.
- `install-server-packages.sh` also installs an `xterm-ghostty` terminfo shim so tmux works when SSHing from Ghostty.
- Neovim installs from `stable` by default (`NEOVIM_CHANNEL=nightly ./install-server-packages.sh` to opt into nightly).
- `install-server.sh` creates symlinks for dotfiles and config files and installs the Pi packages. It does not
  install tmux plugins or Clankerhouse; deploy Clankerhouse from its own repository.
- Tools that are already installed are skipped; run `UPGRADE=1 ./install-server-packages.sh` to pull the latest releases.
- The `opencode`/`pi`/`claude`/`codex` wrappers check npm for a new release at most once a day; `NPX_WRAPPER_REFRESH=1 <tool>` forces a check.
- AWS CLI v2 is installed for IAM Identity Center (SSO) workflows.

## AWS SSO on a dev machine

Configure an SSO profile and select it only while working inside a project:

```bash
cd ~/dev/project
aws-sso configure company-dev
aws sts get-caller-identity
```

`aws-sso configure` runs `aws configure sso` with the device authorization
flow and forces its browser launch through `~/.local/bin/xdg-open`, which the
server profile links to the laptop-opening shim. The SSO profile and token
cache remain under `~/.aws`; the project gets only an ignored
`mise.local.toml` containing `AWS_PROFILE`, so no credentials are written into
the repository. Mise activates the profile on entry and restores the previous
environment on exit.

Renew an expired SSO session with the directory-selected profile:

```bash
aws-sso login
```

## Linear access

Dotfiles no longer installs a personal `linear` skill. Use the project's
integration instead: Tweezr provides `AI/skills/linear`, which routes agents
through `./task/agent/linear` using a pinned `schpet/linear-cli`.
Keep `LINEAR_API_KEY` in `~/.env`; the Tweezr CLI still uses it:

```bash
export LINEAR_API_KEY="..."
```

## Worktrunk

`worktrunk/config.toml` is installed on desktop/server profiles. Bare repositories
stored at `<repo>/.git` create worktrees at `<repo>/<branch>` instead of
`<repo>/.git.<branch>`. Ordinary repositories retain Worktrunk's default sibling
`<repo>.<branch>` layout; branch slashes are sanitized and existing checkouts are
never moved. `bin/dotfiles-check` exercises both layouts in an isolated HOME when
`wt` is available.

## Symlinks

Every symlink is a tab-separated row in `install-manifest.tsv`, reconciled by
`bin/dotfiles-install [--dry-run] desktop|server|macos`. On macOS run
`./install-macos.sh`. Put machine-specific git settings (for example a work
identity via `includeIf`) in `~/.gitconfig.local`.

## Notes

- Run `dotfiles-check` before committing; CI runs the same script.
- Do not run `install-omarchy.sh` on EC2/dev servers.
- Run `dotfiles-doctor` to check common local setup issues after installing or changing symlinks. It verifies every manifest link for the current profile, reports missing commands, and suggests `./install-omarchy.sh` when local symlinks need refreshing.
- If Python LSP is missing on a machine, install it with:

```bash
nvim --headless "+MasonInstall basedpyright" +qa
```
