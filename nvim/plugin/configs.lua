local opt = vim.opt
-- opt.guicursor = "i:block" -- cursor style in insert mode
opt.colorcolumn = "99" -- vertical line at column 99 for line length guide
opt.signcolumn = "yes:1" -- always show sign column with width 1
opt.termguicolors = true -- enable 24-bit RGB colors in terminal
opt.ignorecase = true -- ignore case in search patterns
opt.swapfile = false -- disable swap file creation
opt.autoindent = true
opt.expandtab = true -- use spaces instead of tabs
opt.tabstop = 4
opt.softtabstop = 4 -- number of spaces for tab in insert mode
opt.shiftwidth = 4
opt.shiftround = true -- round indent to multiple of shiftwidth
opt.listchars = "tab: ,multispace:|   ,eol:󰌑"
opt.list = false -- hide whitespace characters
opt.number = true
opt.relativenumber = true -- show relative line numbers
opt.numberwidth = 2
opt.wrap = false -- disable line wrapping
opt.cursorline = true
opt.scrolloff = 8 -- minimum lines above/below cursor
opt.inccommand = "nosplit"
opt.undodir = os.getenv('HOME') .. '/.vim/undodir' -- directory for undo files
opt.undofile = true
opt.winborder = "rounded" -- rounded window borders
opt.hlsearch = true
opt.fillchars = "vert:│,horiz:─" -- characters for window separators

vim.cmd.filetype("plugin indent on")

vim.g.copilot_no_tab_map = true

-- Disable netrw (replaced by snacks explorer)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

require('vim._extui').enable({})
