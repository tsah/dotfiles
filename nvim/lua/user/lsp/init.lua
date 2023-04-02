local status_ok, _ = pcall(require, "lspconfig")
if not status_ok then
  return
end

require "user.lsp.configs"
require("user.lsp.handlers").setup()
require "user.lsp.null-ls"
require "user.lsp.metals"

require('rust-tools').setup({})
require "lsp_signature".setup({
    bind = true, -- This is mandatory, otherwise border config won't get registered.
    handler_opts = {
      border = "rounded"
    },
    toggle_key = '<C-s>'
  })
local lsp_lines = require('lsp_lines')
lsp_lines.setup()
lsp_lines.toggle()
