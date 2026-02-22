# Tsah's dotfiles

This repository is used on two machine profiles:

- **Main laptop**: Arch Linux + Omarchy desktop
- **Dev machine**: EC2 Linux server (headless)

Use the matching install scripts for each profile.

## Main laptop (Omarchy)

```bash
./install-packages.sh
./install-omarchy.sh
```

- Installs desktop packages for Omarchy/Hyprland.
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
- Neovim installs from `nightly` by default (`NEOVIM_CHANNEL=stable ./install-server-packages.sh` for stable).
- `install-server.sh` creates symlinks for dotfiles and config files and sets the default shell to fish.

## Notes

- Do not run `install-omarchy.sh` on EC2/dev servers.
- If Python LSP is missing on a machine, install it with:

```bash
nvim --headless "+MasonInstall basedpyright" +qa
```
