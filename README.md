# Tsah's dotfiles

## Instructions
1. Install packages (`./install-packages.sh`)
2. Apply symlinks (`./install-omarchy.sh`)

## EC2 server bootstrap

Use these scripts on Linux servers (Amazon Linux 2023 tested):

```bash
./install-server-packages.sh
./install-server.sh
```

- `install-server-packages.sh` installs shell and CLI tooling used by this repo.
- `install-server-packages.sh` also installs an `xterm-ghostty` terminfo shim so tmux works when SSHing from Ghostty.
- Neovim installs from `nightly` by default (`NEOVIM_CHANNEL=stable ./install-server-packages.sh` for stable).
- `install-server.sh` creates symlinks for dotfiles and config files and sets the default shell to fish.
