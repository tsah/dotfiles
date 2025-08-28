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

-- terminal
keymap("t", "<Esc>", "<C-\\><C-N>")

-- cd current dir
keymap("n", "<leader>cd", '<cmd>lua vim.fn.chdir(vim.fn.expand("%:p:h"))<CR>')

-- toggleable netrw
local netrw_buf = nil
local prev_buf = nil

local function find_project_root()
    local current_file = vim.fn.expand('%:p')
    local current_dir = vim.fn.expand('%:p:h')
    
    -- Common project root markers
    local root_markers = {
        '.git', '.gitignore', 'package.json', 'Cargo.toml', 
        'pyproject.toml', 'go.mod', 'Makefile', '.luarc.json'
    }
    
    local function has_marker(dir)
        for _, marker in ipairs(root_markers) do
            if vim.fn.isdirectory(dir .. '/' .. marker) == 1 or
               vim.fn.filereadable(dir .. '/' .. marker) == 1 then
                return true
            end
        end
        return false
    end
    
    -- Traverse up from current directory
    local dir = current_dir
    while dir ~= '/' and dir ~= '' do
        if has_marker(dir) then
            return dir
        end
        dir = vim.fn.fnamemodify(dir, ':h')
    end
    
    -- Fallback to current file's directory
    return current_dir
end

local function toggle_netrw()
    local current_buf = vim.api.nvim_get_current_buf()
    local current_ft = vim.bo[current_buf].filetype
    
    if current_ft == 'netrw' then
        -- Currently in netrw, go back to previous buffer
        if prev_buf and vim.api.nvim_buf_is_valid(prev_buf) then
            vim.api.nvim_set_current_buf(prev_buf)
        else
            -- If previous buffer is invalid, create a new one
            vim.cmd('enew')
        end
        netrw_buf = current_buf
    else
        -- Not in netrw, save current buffer and open netrw at current file's directory
        prev_buf = current_buf
        local current_file = vim.fn.expand('%:p')
        
        if current_file ~= '' and vim.fn.filereadable(current_file) == 1 then
            -- Open netrw in current file's directory
            local current_dir = vim.fn.fnamemodify(current_file, ':h')
            vim.cmd('Ex ' .. vim.fn.fnameescape(current_dir))
            
            -- Select the current file in the tree
            vim.schedule(function()
                local filename = vim.fn.fnamemodify(current_file, ':t')
                -- Simple search for filename in tree view
                local patterns = {
                    '│.*' .. vim.fn.escape(filename, '\\.*[]^$') .. '$',    -- Tree format
                    '^' .. vim.fn.escape(filename, '\\.*[]^$') .. '$'       -- Direct listing
                }
                
                for _, pattern in ipairs(patterns) do
                    if vim.fn.search(pattern, 'w') > 0 then
                        break
                    end
                end
            end)
        else
            -- No current file, open at project root
            local project_root = find_project_root()
            vim.cmd('Ex ' .. vim.fn.fnameescape(project_root))
        end
        
        netrw_buf = vim.api.nvim_get_current_buf()
    end
end

keymap("n", "\\", toggle_netrw, { desc = "Toggle netrw" })

-- Alternative: Simple project root netrw (no file selection)
local function simple_project_netrw()
    local project_root = find_project_root()
    vim.cmd('Ex ' .. vim.fn.fnameescape(project_root))
end

-- Uncomment if you want simpler project root navigation
keymap("n", "<leader>E", simple_project_netrw, { desc = "Project root netrw" })

local opts = { noremap = true, silent = true }
-- Definition navigation
keymap("n", "gd", "<cmd>lua vim.lsp.buf.definition()<CR>", opts)     -- go to definition
keymap("n", "gv", "<cmd>vsplit | lua vim.lsp.buf.definition()<CR>", opts) -- go to definition in vertical split
keymap("n", "<leader>dn", "<cmd>lua vim.diagnostic.jump({ count = 1 })<CR>", opts)
keymap("n", "<leader>dp", "<cmd>lua vim.diagnostic.jump({ count = -1 })<CR>", opts)
keymap("n", "<leader>dd", "<cmd>lua vim.diagnostic.open_float()<CR>", opts)

keymap("n", "<leader>e", '<cmd>edit!<CR>', { desc = "Force reload current file" })
keymap("n", "<leader>ps", '<cmd>lua vim.pack.update()<CR>')
keymap("n", "<leader>f", '<cmd>FzfLua files<CR>')
keymap("n", "<leader>F", '<cmd>FzfLua live_grep<CR>')
keymap("i", "<S-Tab>", 'copilot#Accept("\\<Tab>")', { expr = true, replace_keycodes = false })
keymap("n", "<leader>m", '<cmd>lua require("miniharp").toggle_file()<CR>')
keymap("n", "<leader>hl", '<cmd>lua require("miniharp").show_list()<CR>')
keymap("n", "<C-n>", require("miniharp").next)
keymap("n", "<C-p>", require("miniharp").prev)
