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

-- yazi file manager
keymap("n", "\\", "<cmd>Yazi<CR>", { desc = "Open Yazi file manager" })



local opts = { noremap = true, silent = true }
-- Definition navigation
keymap("n", "gd", "<cmd>lua vim.lsp.buf.definition()<CR>", opts)     -- go to definition
keymap("n", "gv", "<cmd>vsplit | wincmd l | lua vim.lsp.buf.definition()<CR>", opts) -- go to definition in vertical split
keymap("n", "gr", "<cmd>FzfLua lsp_references<CR>", opts)           -- go to references
keymap("n", "<leader>dn", "<cmd>lua vim.diagnostic.jump({ count = 1 })<CR>", opts)
keymap("n", "<leader>dp", "<cmd>lua vim.diagnostic.jump({ count = -1 })<CR>", opts)

-- Quickfix navigation
keymap("n", "]q", "<cmd>cnext<CR>", opts)
keymap("n", "[q", "<cmd>cprev<CR>", opts)
keymap("n", "gl", "<cmd>lua vim.diagnostic.open_float()<CR>", opts)

-- Close diagnostic float and clear search highlights with Escape
keymap("n", "<Esc>", function()
    vim.cmd("nohlsearch")  -- Clear search highlights
    for _, win in pairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= "" then  -- floating window
            vim.api.nvim_win_close(win, false)
        end
    end
end, { desc = "Clear search highlights and close floating windows" })

keymap("n", "<leader>e", '<cmd>edit!<CR>', { desc = "Force reload current file" })
keymap("n", "<leader>ps", '<cmd>lua vim.pack.update()<CR>')
keymap("n", "<leader>f", '<cmd>FzfLua files<CR>')
keymap("n", "<leader>F", '<cmd>FzfLua live_grep<CR>')
keymap("n", "<leader>R", '<cmd>FzfLua resume<CR>')


-- Command mode navigation with Ctrl+j/k (wildmenu aware)
keymap("c", "<C-j>", 'pumvisible() ? "\\<C-n>" : "\\<Down>"', { expr = true })
keymap("c", "<C-k>", 'pumvisible() ? "\\<C-p>" : "\\<Up>"', { expr = true })
keymap("n", "<leader>m", '<cmd>lua require("miniharp").toggle_file()<CR>')
keymap("n", "<leader>hl", '<cmd>lua require("miniharp").show_list()<CR>')
keymap("n", "<C-n>", require("miniharp").next)
keymap("n", "<C-p>", require("miniharp").prev)

keymap('n', '<leader>aw', function() require('trevj').format_at_cursor() end, { noremap = true, silent = true })



keymap({ 'n', 'x', 'o' }, 's', function() require('flash').jump() end, { desc = "Flash jump" })

keymap('n', '<leader>ot', function() require('opencode').toggle() end, { desc = 'Toggle opencode' })
keymap('n', '<leader>oa', function() require('opencode').ask('@cursor: ') end, { desc = 'Ask about cursor' })
keymap('v', '<leader>oa', function() require('opencode').ask('@selection: ') end, { desc = 'Ask about selection' })
keymap('n', '<leader>o+', function() require('opencode').prompt('@buffer', { append = true }) end, { desc = 'Add buffer to prompt' })
keymap('v', '<leader>o+', function() require('opencode').prompt('@selection', { append = true }) end, { desc = 'Add selection to prompt' })
keymap('n', '<leader>oe', function() require('opencode').prompt('Explain @cursor and its context') end, { desc = 'Explain code at cursor' })
keymap('n', '<leader>on', function() require('opencode').command('session_new') end, { desc = 'New opencode session' })
keymap('n', '<S-C-u>', function() require('opencode').command('messages_half_page_up') end, { desc = 'Opencode messages up' })
keymap('n', '<S-C-d>', function() require('opencode').command('messages_half_page_down') end, { desc = 'Opencode messages down' })
keymap({ 'n', 'v' }, '<leader>os', function() require('opencode').select() end, { desc = 'Select opencode prompt' })
