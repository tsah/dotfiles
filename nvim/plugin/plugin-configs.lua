require('command').setup({})
require('miniharp').setup({ show_on_autoload = true })
require('mason').setup({})

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

require('mini.surround').setup({
    mappings = {
        add = '<leader>sa',
        delete = '<leader>sd',
        find = '<leader>sf',
        find_left = '<leader>sF',
        highlight = '<leader>sh',
        replace = '<leader>sr',
        update_n_lines = '<leader>sn',
        suffix_last = 'l',
        suffix_next = 'n',
    },
    custom_surroundings = {
        ['('] = { output = { left = '(', right = ')' } },
        ['['] = { output = { left = '[', right = ']' } },
        ['{'] = { output = { left = '{', right = '}' } },
        [')'] = { output = { left = '( ', right = ' )' } },
        [']'] = { output = { left = '[ ', right = ' ]' } },
        ['}'] = { output = { left = '{ ', right = ' }' } },
    },
})

require('trevj').setup({})
require('typescript-tools').setup({})

require('flash').setup({
    modes = {
        char = {
            enabled = false,
        }
    }
})

require('yazi').setup({
    open_for_directories = false,
    enable_mouse_support = true,
    keymaps = {
        show_help = '<f1>',
    },
})

require('nvim-treesitter.configs').setup({
    ensure_installed = { "lua", "vim", "vimdoc", "javascript", "typescript", "python" },
    auto_install = true,
    highlight = {
        enable = true,
    },
})

require('treesitter-context').setup({
    enable = true,
    max_lines = 4,
})

require('hunk').setup({})

require('snacks').setup({
    input = { enabled = true },
    terminal = { enabled = true }
})

vim.g.opencode_opts = {}
vim.opt.autoread = true