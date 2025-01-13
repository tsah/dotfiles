
if vim.g.vscode then
  -- VSCode Neovim
  require "user.vscode_keymaps"
else
  require "user.options"
  require "user.plugins"
  require "user.keymaps"
  require "user.colorscheme"
  require "user.cmp"
  require "user.lsp"
  require "user.telescope"
  require "user.treesitter"
  require "user.gitsigns"
  require "user.nvim-tree"
  require "user.toggleterm"
  require "user.project"
  require "user.impatient"
  require "user.whichkey"
  require "user.autocommands"
  require "user.mini"
  -- require "user.copilot"
  require "user.oil"
end
