# Agent Guidelines for dotfiles Repository

## Repository Overview

Personal dotfiles for Arch Linux with Hyprland (Omarchy), including configurations for:
- Neovim, tmux, zsh, starship prompt
- Hyprland window manager (via Omarchy)
- Terminal emulators (Ghostty, Alacritty, WezTerm)
- Development tools (jj/jujutsu, sesh, lazygit, opencode)

## Build/Lint/Test Commands

This is a dotfiles repository - no traditional build system exists.

### Installation & Verification
```bash
# Install/update symlinks and configurations
./install-omarchy.sh

# Install required packages (Arch Linux)
./install-packages.sh

# Reload Hyprland config (if running)
hyprctl reload

# Reload tmux config
tmux source-file ~/.tmux.conf
```

### Testing Changes
- **Shell scripts**: Run with `bash -n script.sh` for syntax check
- **Lua configs**: Open Neovim and check `:messages` for errors
- **Hyprland**: Run `hyprctl reload` and check for errors
- **tmux**: Source config and verify bindings work

## Code Style Guidelines

### Shell Scripts (Bash/POSIX sh)

**Shebang selection:**
- Use `#!/bin/bash` for scripts requiring bash features
- Use `#!/bin/sh` for portable install scripts

**Variables:**
```bash
# Quote all variable expansions
WORKTREE_ROOT=$(git rev-parse --show-toplevel)
echo "Current directory: ${CURRENT_DIR}"

# Use uppercase for global/environment variables
REPO_NAME=$(basename "$MAIN_REPO_ROOT")

# Use lowercase for local function variables (optional)
local session_name="$1"
```

**Functions:**
```bash
# Use snake_case for function names
spawn_impl() {
    local branch_name="$1"
    # ...
}

# Include usage() function for scripts with arguments
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  spawn <branch>    Create new worktree"
}
```

**Error handling:**
```bash
# Use set -e in install scripts
set -e

# Check command success explicitly in interactive scripts
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: Not in a git repository" >&2
    exit 1
fi

# Use >&2 for error messages
echo "Error: Branch not found" >&2
```

**Control flow:**
```bash
# Use [[ ]] for conditionals in bash
if [[ -n "$TMUX" ]]; then

# Use [ ] in POSIX sh scripts
if [ -n "$NIRI_SOCKET" ]; then

# Case statements for option parsing
case $1 in
    -m|--from-master)
        FROM_MASTER=true
        shift
        ;;
    *)
        BRANCH_NAME="$1"
        ;;
esac
```

### Lua (Neovim Configuration)

**General style:**
```lua
-- Use local for all variables
local keymap = vim.keymap.set
local opt = vim.opt

-- No semicolons
opt.number = true
opt.relativenumber = true

-- Inline comments explain the "why"
opt.scrolloff = 8 -- minimum lines above/below cursor
```

**Plugin declarations (vim.pack format):**
```lua
local plugins = {
    { src = "https://github.com/user/plugin.nvim" },
    {
        src = "https://github.com/user/plugin.nvim",
        version = "v1.0.0"
    },
}

vim.pack.add(plugins, { load = true })
```

**Keymaps:**
```lua
local opts = { noremap = true, silent = true }
local s = { silent = true }

-- Group related keymaps with comments
-- LSP actions
keymap("n", "<Leader>lf", ":lua vim.lsp.buf.format()<CR>", s)
keymap("n", "gd", "<cmd>lua vim.lsp.buf.definition()<CR>", opts)

-- Use functions for complex mappings
keymap("n", "j", function()
    return tonumber(vim.api.nvim_get_vvar("count")) > 0 and "j" or "gj"
end, { expr = true, silent = true })
```

**LSP configuration:**
```lua
-- Enable LSP servers in lsp.lua
vim.lsp.enable({
  "bashls",
  "gopls",
  "lua_ls",
})

-- Individual LSP configs go in nvim/lsp/<server>.lua
```

**Important:** The `vim` global is provided by Neovim - ignore "undefined global vim" linting warnings.

### Configuration Files

**TOML (starship, sesh, jj):**
```toml
# Use sections for grouping
[section]
key = "value"

# Arrays of tables for lists
[[session]]
name = "project"
path = "~/dev/project"
```

**JSON (opencode.json):**
```json
{
  "$schema": "https://example.com/schema.json",
  "key": {
    "nested": "value"
  }
}
```

**KDL (zellij):**
```kdl
section {
    key value
    nested {
        inner "string value"
    }
}
```

**Hyprland config:**
```conf
# Source other configs
source = ~/.config/hypr/monitors.conf

# Key bindings: bind = MODS, key, dispatcher, params
bind = $mainMod, T, exec, ghostty

# Window rules
windowrule = workspace 5, class:qemu
```

### Symlink Conventions

All config files live in `~/dotfiles` and are symlinked by `install-omarchy.sh`:

```bash
# Pattern: mkdir if needed, then symlink
mkdir -p ~/.config/sesh
ln -sf ~/dotfiles/sesh.toml ~/.config/sesh/sesh.toml

# For directories, remove existing first
rm -rf ~/.config/hypr
ln -sf ~/dotfiles/omarchy/hypr ~/.config/hypr
```

When adding new configs:
1. Create the config file in `~/dotfiles/`
2. Add symlink command to `install-omarchy.sh`
3. Run `./install-omarchy.sh` to apply

## File Organization

```
dotfiles/
├── bin/                    # Executable scripts (added to PATH)
├── nvim/                   # Neovim config (symlinked to ~/.config/nvim)
│   ├── plugin/            # Auto-loaded plugin configs
│   └── lsp/               # LSP server configurations
├── omarchy/               # Hyprland/Omarchy configs
│   ├── hypr/             # Hyprland config files
│   └── waybar/           # Waybar config
├── *.toml                 # Various tool configs (starship, sesh, jj)
├── *.json                 # JSON configs (opencode)
├── zshrc                  # Zsh configuration
├── .tmux.conf            # Tmux configuration
├── install-omarchy.sh    # Symlink installer
└── install-packages.sh   # Package installer (Arch)
```

## OpenCode Configuration

OpenCode configs are in `~/dotfiles/opencode/` and symlinked to `~/.config/opencode/`:

```
dotfiles/
├── opencode.json              # Main config (symlinked to ~/.config/opencode/opencode.json)
└── opencode/
    ├── agents/                # Custom subagent definitions (markdown)
    │   ├── code-review.md
    │   ├── pr-ci-analyzer.md
    │   └── pr-comments-gatherer.md
    └── commands/              # Custom slash commands (markdown)
        ├── pr.md
        ├── prepare_pr.md
        └── ...
```

### Key Configuration

**opencode.json** configures:
- MCP servers (e.g., Linear integration)
- Provider/model settings
- Agent overrides (model, tools, permissions)
- Global tool enable/disable

**Limiting MCP to specific agents:**
```json
{
  "mcp": {
    "linear": { "type": "remote", "url": "https://mcp.linear.app/mcp" }
  },
  "tools": {
    "linear_*": false
  },
  "agent": {
    "linear-agent": {
      "mode": "subagent",
      "tools": { "linear_*": true }
    }
  }
}
```

### Omarchy Skill

OpenCode loads the **Omarchy skill** from `~/.claude/skills/omarchy/SKILL.md` (Claude Code compatibility path). This skill provides domain-specific knowledge for:
- Hyprland, Waybar, Walker configuration
- Terminal emulator configs (Ghostty, Alacritty, Kitty)
- Omarchy commands (`omarchy-*`)
- Theme and keybinding customization
- Safe customization patterns (never edit `~/.local/share/omarchy/`)

The skill is automatically loaded when editing files in `~/.config/hypr/`, `~/.config/waybar/`, etc.

**Useful debug commands:**
```bash
opencode debug skill          # List available skills and locations
opencode debug config         # Show resolved configuration
opencode agent list           # List agents and their permissions
opencode mcp list             # List MCP servers and status
```

## Common Tasks

**Adding a new shell script to bin/:**
1. Create script in `bin/` with proper shebang
2. Make executable: `chmod +x bin/script-name`
3. Script is automatically in PATH via zshrc

**Adding a new Neovim plugin:**
1. Add to `nvim/plugin/+plugins.lua`
2. Configure in `nvim/plugin/plugin-configs.lua` or dedicated file
3. Run `:lua vim.pack.update()` in Neovim

**Adding a new tool config:**
1. Create config file in dotfiles root
2. Add symlink to `install-omarchy.sh`
3. Run `./install-omarchy.sh`
