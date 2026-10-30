# Agent Guidelines for dotfiles Repository

## IMPORTANT: Edit Files in This Repository

**All configuration edits should be made to files in THIS repository (`~/dotfiles/`), NOT in `~/.config/`, `~/.pi/`, or other live config directories directly.** The files here are symlinked to their destinations by `bin/dotfiles-install`, which reads `install-manifest.tsv`. For example:
- Omarchy shell config: edit `omarchy/shell.json` (NOT `~/.config/omarchy/`)
- Hyprland config: edit `omarchy/hypr/` (NOT `~/.config/hypr/`)
- Neovim config: edit `nvim/` (NOT `~/.config/nvim/`)
- Pi config: edit `pi/` (NOT `~/.pi/agent/`)

## Repository Overview

Personal dotfiles for Arch Linux with Hyprland (Omarchy), including configurations for:
- Neovim, tmux, zsh, starship prompt
- Hyprland window manager (via Omarchy)
- Ghostty terminal configuration
- Development tools (Worktrunk, lazygit, opencode, pi)

## Build/Lint/Test Commands

This is a dotfiles repository - no traditional build system exists.

### Installation & Verification
```bash
# Install/update symlinks and configurations (desktop / server / macOS)
./install-omarchy.sh
./install-server.sh
./install-macos.sh

# Preview link changes without touching anything
bin/dotfiles-install --dry-run desktop

# Lint: shell syntax, shellcheck, manifest sources, JSON, extension tests
bin/dotfiles-check

# Verify every manifest link on this machine
bin/dotfiles-doctor

# Install required packages (Arch Linux)
./install-packages.sh

# Reload Hyprland config (if running)
hyprctl reload

# Reload tmux config
tmux source-file ~/.tmux.conf
```

### Testing Changes
- **Everything**: Run `bin/dotfiles-check` before committing (CI runs the same script)
- **Shell scripts**: Run with `bash -n script.sh` for syntax check; keep them shellcheck-clean at warning level
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
if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then

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

**TOML (starship and tool configuration):**
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

**Hyprland config (Lua, Omarchy Quattro):**
```lua
-- omarchy/hypr/hyprland.lua loads Omarchy defaults, then the personal modules
require("hypr.bindings")

-- Omarchy defaults load first, so unbind a chord before rebinding it
hl.unbind("SUPER + E")
o.bind("SUPER + E", "File manager", "uwsm-app -- nautilus --new-window")

-- Window rules
o.window({ class = "^zoom$" }, { float = true })
```

### Symlink Conventions

All config files live in `~/dotfiles`. `install-manifest.tsv` declares every
symlink as a tab-separated `scope<TAB>source<TAB>destination` row, and
`bin/dotfiles-install <profile>` reconciles them:

```
# a = desktop and server, d = desktop, s = server, m = macos
a	starship.toml	~/.config/starship.toml
d	omarchy/hypr	~/.config/hypr
```

The installer refuses to replace a real file or directory (unless it is
identical to the source), fails when a source is missing, and removes links
whose rows were deleted. Never add `ln -s` commands to the install scripts.

When adding new configs:
1. Create the config file in `~/dotfiles/`
2. Add a row to `install-manifest.tsv` (use real tabs)
3. Run `bin/dotfiles-install --dry-run <profile>`, then the profile installer

## File Organization

```
dotfiles/
├── bin/                    # Executable scripts (added to PATH)
├── claude/                 # Claude Code commands and shared skills
├── nvim/                   # Neovim config (symlinked to ~/.config/nvim)
│   ├── plugin/            # Auto-loaded plugin configs
│   └── lsp/               # LSP server configurations
├── omarchy/               # Hyprland/Omarchy configs
│   ├── hypr/             # Hyprland Lua config and helper scripts
│   ├── extensions/       # Omarchy menu extensions
│   └── shell.json        # Omarchy shell (bar) config
├── pi/                    # Pi agent extensions and agent definitions
├── *.toml                 # Tool configuration
├── *.json                 # JSON configs (opencode)
├── zshrc                  # Zsh configuration
├── .tmux.conf            # Tmux configuration
├── skills/               # Skills shared across agent harnesses
├── install-manifest.tsv  # Declares every symlink per profile
├── install-omarchy.sh    # Desktop installer (links + post-install steps)
├── install-server.sh     # Server installer
└── install-packages.sh   # Package installer (Arch)
```

## Pi Configuration

Pi configs are in `~/dotfiles/pi/` and symlinked to `~/.pi/agent/`:

```
dotfiles/
└── pi/
    ├── extensions/                  # Personal Pi extensions
    └── subagents.json               # @tintinweb/pi-subagents limits and UI settings
```

`bin/install-pi-packages` installs the pinned in-process subagent package and,
when present, the local pi-slopchop package's runtime dependencies.
Use the subagent package's `Agent` tool for same-session delegation;
use the externally installed `workshop-pi` only for explicit handoffs that require
a visible clanker in a Worktrunk-isolated workshop.

A request to run QA, tests, a shell, or an interactive command in a tmux window
or pane means the current tmux session and current worktree unless the user
explicitly requests delegation or isolation. The words "tmux", "window",
"pane", "visible", or "separate" alone never imply a workshop. Use a current-
session window/pane for command execution, `clanker-*` only when another visible
clanker in the current workshop is requested, and `workshop-*` only for an
explicit isolated handoff. Harness-native in-process subagents are not clankers.
Ask when "separate" is ambiguous.

## Claude Code Configuration

Claude Code commands are in `~/dotfiles/claude/commands/` and symlinked to `~/.claude/commands/`.
Shared skills live in `~/dotfiles/skills/` and are symlinked to each supported
harness.

Workshop launchers:
- Claude Code: `workshop-claude`
- OpenCode: `workshop-opencode`
- Codex: `workshop-codex`
- Pi: `workshop-pi`

## OpenCode Configuration

This repository targets the **OpenCode 2 beta**. Use the `opencode2` CLI and the
documentation under `https://opencode.ai/v2/docs/`; do not infer behavior from
OpenCode 1 or the unversioned `opencode` binary.

OpenCode 2 configs are in `~/dotfiles/opencode/` and symlinked to `~/.config/opencode/`:

```
dotfiles/
└── opencode/
    ├── global.json            # Main config (symlinked to ~/.config/opencode/opencode.json)
    ├── agents/                # Custom subagent definitions (markdown; currently empty)
    ├── commands/              # Custom slash commands (markdown): handoff, lavish, plf, ship-pr
    └── plugins/               # Local plugins (Plannotator shortcuts, TUI attention timeline)
```

Plugin versions in `global.json` are pinned.

### Key Configuration

**opencode/global.json** configures:
- Provider/model settings
- Agent overrides (model, tools, permissions)
- Global tool enable/disable

Linear access is project-owned, not provided by a personal dotfiles skill.
In Tweezr, use its `AI/skills/linear` skill and `./task/agent/linear` CLI.
Keep `LINEAR_API_KEY` in `~/.env`, never in tracked config.

### Slash Commands

OpenCode 2 Markdown slash commands are prompt templates. Invoking one submits a
durable user prompt in the current session and schedules normal model execution;
they cannot register direct command handlers or bypass the model. TUI plugins
can register direct slash handlers with `api.keymap.registerLayer`. `/plr` and
`/pll` use that API in `opencode/plugins/plannotator-shortcuts.ts` to run
Plannotator directly; do not replace them with Markdown command files.

The Plannotator plugin's direct `/plannotator-review`, `/plannotator-annotate`,
and `/plannotator-last` handlers are OpenCode 1-only. Do not recommend those as
a direct-execution workaround for OpenCode 2.

### Omarchy Skill

OpenCode loads the **Omarchy skill** from `~/.claude/skills/omarchy/SKILL.md` (Claude Code compatibility path). This skill provides domain-specific knowledge for:
- Hyprland, Waybar, Walker configuration
- Terminal emulator configs (Ghostty)
- Omarchy commands (`omarchy-*`)
- Theme and keybinding customization
- Safe customization patterns (never edit `~/.local/share/omarchy/`)

The skill is automatically loaded when editing files in `~/.config/hypr/`, `~/.config/waybar/`, etc.

**Useful debug commands:**
```bash
opencode2 service status              # Check the shared background service
opencode2 api get /api/health         # Verify API connectivity
opencode2 plugin list                 # List loaded plugins
opencode2 --standalone                # Isolate shared-service problems
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
2. Add a tab-separated row to `install-manifest.tsv`
3. Run `bin/dotfiles-install <profile>` (or the profile installer)
