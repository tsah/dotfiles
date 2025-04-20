-- Configuration for VSCode Neovim extension
local M = {}

function M.setup()
  -- VSCode-specific settings
  vim.g.vscode = true
  
  -- Disable certain features that don't make sense in VSCode
  -- For example, disable UI elements that VSCode already provides
  vim.opt.showmode = false
  vim.opt.showcmd = false
  vim.opt.ruler = false
  
  -- You might want to adjust key mappings for VSCode integration
  -- Example: local keymap = vim.api.nvim_set_keymap
  -- keymap("n", "<C-j>", "<Cmd>call VSCodeNotify('workbench.action.navigateDown')<CR>", { noremap = true, silent = true })
  
  -- Load VSCode-specific keymaps if they exist
  local ok, vscode_keymaps = pcall(require, "user.vscode_keymaps")
  if ok then
    vscode_keymaps.setup()
  end
end

return M
