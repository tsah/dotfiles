local keymap = vim.keymap.set
local s = { silent = true }

keymap("n", "<space>", "<Nop>")


-- movement
keymap("n", "j", function()
    return tonumber(vim.api.nvim_get_vvar("count")) > 0 and "j" or "gj"
end, { expr = true, silent = true })
keymap("n", "k", function()
    return tonumber(vim.api.nvim_get_vvar("count")) > 0 and "k" or "gk"
end, { expr = true, silent = true })
keymap("n", "<C-d>", "<C-d>zz")
keymap("n", "<C-u>", "<C-u>zz")

-- edit
keymap("i", "jk", "<Esc>", s)

--- save and quit
keymap("n", "<Leader>w", "<cmd>w!<CR>", s)
keymap("n", "<Leader>q", "<cmd>q<CR>", s)

-- tabs
keymap("n", "<Leader>te", "<cmd>tabnew<CR>", s)

--- split windows
keymap("n", "<Leader>_", "<cmd>vsplit<CR>", s)
keymap("n", "<Leader>-", "<cmd>split<CR>", s)

-- LSP actions
keymap("n", "<Leader>lf", ":lua vim.lsp.buf.format()<CR>", s)        -- lsp format
keymap("n", "<Leader>lr", "<cmd>lua vim.lsp.buf.rename()<CR>", opts) -- lsp rename  
keymap("n", "<Leader>la", "<cmd>lua vim.lsp.buf.code_action()<CR>", opts) -- lsp actions
keymap("n", "<Leader>lh", "<cmd>lua vim.lsp.buf.hover()<CR>", opts)  -- lsp hover
keymap("n", "<Leader>ls", "<cmd>lua vim.lsp.buf.signature_help()<CR>", opts) -- lsp signature

-- copy and paste
keymap("v", "<Leader>p", '"_dP')
keymap("x", "y", [["+y]], s)
keymap("n", "y", [["+y]], s)

-- terminal
keymap("t", "<Esc>", "<C-\\><C-N>")

-- cd current dir
keymap("n", "<leader>cd", '<cmd>lua vim.fn.chdir(vim.fn.expand("%:p:h"))<CR>')

-- snacks explorer keybindings
keymap("n", "\\", function() Snacks.explorer() end, { desc = "Toggle Explorer" })
keymap("n", "<leader>E", function() Snacks.explorer() end, { desc = "Explorer" })

local opts = { noremap = true, silent = true }
-- Definition navigation
keymap("n", "gd", "<cmd>lua vim.lsp.buf.definition()<CR>", opts)     -- go to definition
keymap("n", "gv", "<cmd>vsplit | lua vim.lsp.buf.definition()<CR>", opts) -- go to definition in vertical split
keymap("n", "<leader>dn", "<cmd>lua vim.diagnostic.jump({ count = 1 })<CR>", opts)
keymap("n", "<leader>dp", "<cmd>lua vim.diagnostic.jump({ count = -1 })<CR>", opts)
keymap("n", "gl", "<cmd>lua vim.diagnostic.open_float()<CR>", opts)

-- Close diagnostic float with Escape
keymap("n", "<Esc>", function()
    for _, win in pairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= "" then  -- floating window
            vim.api.nvim_win_close(win, false)
        end
    end
end, { desc = "Close floating windows" })

keymap("n", "<leader>e", '<cmd>edit!<CR>', { desc = "Force reload current file" })
keymap("n", "<leader>ps", '<cmd>lua vim.pack.update()<CR>')
keymap("n", "<leader>f", '<cmd>FzfLua files<CR>')
keymap("n", "<leader>F", '<cmd>FzfLua live_grep<CR>')
keymap("i", "<S-Tab>", 'copilot#Accept("\\<Tab>")', { expr = true, replace_keycodes = false })

-- Command mode navigation with Ctrl+j/k (wildmenu aware)
keymap("c", "<C-j>", 'pumvisible() ? "\\<C-n>" : "\\<Down>"', { expr = true })
keymap("c", "<C-k>", 'pumvisible() ? "\\<C-p>" : "\\<Up>"', { expr = true })
keymap("n", "<leader>m", '<cmd>lua require("miniharp").toggle_file()<CR>')
keymap("n", "<leader>hl", '<cmd>lua require("miniharp").show_list()<CR>')
keymap("n", "<C-n>", require("miniharp").next)
keymap("n", "<C-p>", require("miniharp").prev)




