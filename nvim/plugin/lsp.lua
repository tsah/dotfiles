vim.lsp.enable({
  "bashls",
  "gopls",
  "lua_ls",
  "texlab",
  "rust-analyzer",
  "helm_ls",
  "basedpyright"
})

vim.diagnostic.config({ 
    signs = true,
    virtual_text = true,
    update_in_insert = false,
    severity_sort = true,
})
