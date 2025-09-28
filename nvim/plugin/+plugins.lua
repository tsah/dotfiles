vim.g.mapleader = " "

local HOME = vim.fn.expand("~")
local local_dev = "file://" .. HOME

-- Core plugins (always loaded)
local core_plugins = {
    { src = "https://github.com/mason-org/mason.nvim" },

    { src = "https://github.com/catppuccin/nvim" }, -- catppuccin theme
    { src = "https://github.com/vieitesss/miniharp.nvim" },
    { src = "https://github.com/ibhagwan/fzf-lua" },
     {
         src = "https://github.com/lewis6991/gitsigns.nvim",
         version = "v1.0.2"
     },
     {
         src = "https://github.com/saghen/blink.cmp",
         version = "v1.7.0"
     },
    { src = "https://github.com/vieitesss/command.nvim" },
    { src = "https://github.com/tpope/vim-fugitive" },
    { src = "https://github.com/echasnovski/mini.surround" },
     { src = "https://github.com/luancgs/argonaut.nvim" },
    { src = "https://github.com/neovim/nvim-lspconfig" },
    { src = "https://github.com/pmizio/typescript-tools.nvim" },
    { src = "https://github.com/folke/flash.nvim" },
     { src = "https://github.com/olimorris/codecompanion.nvim" },
     { src = "https://github.com/nvim-lua/plenary.nvim" },
     { src = "https://github.com/ravitemer/mcphub.nvim" },
     { src = "https://github.com/lervag/vimtex" },
    { src = "https://github.com/mikavilpas/yazi.nvim" },
    { src = "https://github.com/nvim-treesitter/nvim-treesitter" },
    { src = "https://github.com/nvim-treesitter/nvim-treesitter-context" },
    { src = "https://github.com/MunifTanjim/nui.nvim" },
    { src = "https://github.com/julienvincent/hunk.nvim" },
}

-- Combine core and theme plugins
local all_plugins = core_plugins

vim.pack.add(all_plugins, { load = true })

vim.env.PATH = vim.fn.stdpath("data") .. "/mason/bin:" .. vim.env.PATH

require('command').setup({})
require('miniharp').setup({ show_on_autoload = true })
require('mason').setup({})

-- Setup theme
require('catppuccin').setup({})
vim.schedule(function()
    vim.cmd.colorscheme('catppuccin-mocha')
end)
require('gitsigns').setup({ signcolumn = false })
require('blink.cmp').setup({
    fuzzy = {
        implementation = 'prefer_rust_with_warning',
        sorts = { 'score', 'sort_text', 'label' }
    },
    signature = {
        enabled = true,
        trigger = {
            show_on_insert_on_trigger_character = true,
        }
    },
    keymap = {
        preset = "enter",
    },

    appearance = {
        use_nvim_cmp_as_default = true,
        nerd_font_variant = "normal",
    },

    completion = {
        documentation = {
            auto_show = true,
            auto_show_delay_ms = 200,
        },
        menu = {
            auto_show = true,
        },
        list = {
            selection = { preselect = false, auto_insert = false }
        },
        keyword = { range = 'full' }
    },

    cmdline = {
        keymap = {
            preset = 'inherit',
            ['<CR>'] = { 'accept_and_enter', 'fallback' },
        },
    },

    sources = { default = { "lsp" } }
})

local actions = require('fzf-lua.actions')
require('fzf-lua').setup({
    winopts = {
        layout = "horizontal",
        fullscreen = true
    },
    keymap = {
        builtin = {
            ["<C-f>"] = "preview-page-down",
            ["<C-b>"] = "preview-page-up",
            ["<C-p>"] = "toggle-preview",
            ["<C-j>"] = "down",
            ["<C-k>"] = "up",
        },
        fzf = {
            ["ctrl-a"] = "toggle-all",
            ["ctrl-t"] = "first",
            ["ctrl-g"] = "last",
            ["ctrl-d"] = "half-page-down",
            ["ctrl-u"] = "half-page-up",
            ["ctrl-j"] = "down",
            ["ctrl-k"] = "up",
        }
    },
    actions = {
        files = {
            ["ctrl-q"] = actions.file_sel_to_qf,
            ["ctrl-n"] = actions.toggle_ignore,
            ["ctrl-h"] = actions.toggle_hidden,
            ["enter"]  = actions.file_edit_or_qf,
        }
    }
})

require('codecompanion').setup({
    extensions = {
        mcphub = {
            callback = "mcphub.extensions.codecompanion",
            opts = {
                make_vars = true,
                make_slash_commands = true,
                show_result_in_chat = true
            }
        }
    },
})

vim.g.vimtex_imaps_enabled = 0
vim.g.vimtex_view_method = "skim"
vim.g.latex_view_general_viewer = "skim"
vim.g.latex_view_general_options = "-reuse-instance -forward-search @tex @line @pdf"
vim.g.vimtex_compiler_method = "latexmk"
vim.g.vimtex_quickfix_open_on_warning = 0
vim.g.vimtex_quickfix_ignore_filters = { "Underfull", "Overfull", "LaTeX Warning: .\\+ float specifier changed to",
    "Package hyperref Warning: Token not allowed in a PDF string" }

-- Configure mini.surround with <leader>s prefix
require('mini.surround').setup({
    mappings = {
        add = '<leader>sa',            -- Add surrounding in Normal and Visual modes
        delete = '<leader>sd',         -- Delete surrounding
        find = '<leader>sf',           -- Find surrounding (to the right)
        find_left = '<leader>sF',      -- Find surrounding (to the left)
        highlight = '<leader>sh',      -- Highlight surrounding
        replace = '<leader>sr',        -- Replace surrounding
        update_n_lines = '<leader>sn', -- Update `n_lines`

        suffix_last = 'l',             -- Suffix to search with "prev" method
        suffix_next = 'n',             -- Suffix to search with "next" method
    },
    
    -- Custom surrounding pairs with flipped spacing
    custom_surroundings = {
        -- No space versions (default behavior flipped)
        ['('] = { output = { left = '(', right = ')' } },
        ['['] = { output = { left = '[', right = ']' } },
        ['{'] = { output = { left = '{', right = '}' } },
        
        -- Space versions (accessible with shift+key)  
        [')'] = { output = { left = '( ', right = ' )' } },
        [']'] = { output = { left = '[ ', right = ' ]' } },
        ['}'] = { output = { left = '{ ', right = ' }' } },
    },
})

-- Configure argonaut
require('argonaut').setup({})
vim.keymap.set('n', '<leader>aw', ':<c-u>ArgonautToggle<cr>', { noremap = true, silent = true })



-- Configure typescript-tools
require('typescript-tools').setup({})

-- Configure flash.nvim
require('flash').setup({
    modes = {
        char = {
            enabled = false,  -- Disable f/F/t/T flash integration
        }
    }
})

-- Flash keymaps (simple)
vim.keymap.set({ 'n', 'x', 'o' }, 's', function() require('flash').jump() end, { desc = "Flash jump" })

-- Configure yazi.nvim
require('yazi').setup({
    open_for_directories = false,
    enable_mouse_support = true,
    keymaps = {
        show_help = '<f1>',
    },
})

-- Configure treesitter
require('nvim-treesitter.configs').setup({
    ensure_installed = { "lua", "vim", "vimdoc", "javascript", "typescript", "python" },
    auto_install = true,
    highlight = {
        enable = true,
    },
})

-- Configure treesitter-context
require('treesitter-context').setup({
    enable = true,
    max_lines = 4,
})

-- Configure hunk.nvim
require('hunk').setup({})
