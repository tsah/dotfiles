local opt = vim.opt
-- opt.guicursor = "i:block"
opt.colorcolumn = "99"
opt.signcolumn = "yes:1"
opt.termguicolors = true
opt.ignorecase = true
opt.swapfile = false
opt.autoindent = true
opt.expandtab = true
opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4
opt.shiftround = true
opt.listchars = "tab: ,multispace:|   ,eol:󰌑"
opt.list = false
opt.number = true
opt.relativenumber = true
opt.numberwidth = 2
opt.wrap = false
opt.cursorline = true
opt.scrolloff = 8
opt.inccommand = "nosplit"
opt.undodir = os.getenv('HOME') .. '/.vim/undodir'
opt.undofile = true
opt.winborder = "rounded"
opt.hlsearch = false
opt.fillchars = "vert:│,horiz:─"

vim.cmd.filetype("plugin indent on")

vim.g.copilot_no_tab_map = true
vim.g.netrw_liststyle = 3  -- Tree view
vim.g.netrw_sort_by = "name"
vim.g.netrw_banner = 0     -- Remove banner
vim.g.netrw_browse_split = 0  -- Open files in current window

require('vim._extui').enable({})
