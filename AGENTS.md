# Agent Guidelines for dotfiles Repository

## Build/Lint/Test Commands
This is a dotfiles repository with configuration files. No traditional build/lint/test commands exist.

## Code Style Guidelines

### Shell Scripts (Bash)
- Use `#!/bin/bash` shebang
- Use descriptive variable names in UPPER_CASE
- Quote variables: `"${VARIABLE}"`
- Use `set -e` for error handling in install scripts
- Include usage comments and examples
- Use `>&2` for error messages

### Lua (Neovim config)
- Use `vim.*` API calls directly (ignore "undefined global vim" warnings)
- Table-based plugin declarations with `src` and optional `version`
- Simple, minimal configuration style
- No semicolons or complex syntax
- Ignore linting warnings for vim globals (expected in Neovim config)

### Configuration Files
- Follow respective format standards (TOML, JSON, YAML, KDL)
- Use consistent indentation (2-4 spaces)
- Include comments for complex configurations

### General
- No type checking or linting tools configured
- No specific import/formatting standards (minimal code)
- Error handling: Use `set -e` in scripts, basic error checks
- Naming: descriptive, lowercase with hyphens for scripts
- Python test files may contain intentional import errors for testing