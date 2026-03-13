-- require('command').setup({})
-- require('miniharp').setup({ show_on_autoload = true })
require('mason').setup({})

require('catppuccin').setup({})
vim.schedule(function()
    vim.cmd.colorscheme('catppuccin-mocha')
end)

require('gitsigns').setup({
    signcolumn = true,
    on_attach = function(bufnr)
        local gs = require('gitsigns')
        local opts = { buffer = bufnr, silent = true }

        vim.keymap.set('n', '<leader>hp', gs.preview_hunk, opts)
        vim.keymap.set('n', '<leader>hs', gs.stage_hunk, opts)
        vim.keymap.set('n', '<leader>hu', gs.undo_stage_hunk, opts)
    end
})

-- Global hunk navigation (works everywhere, no-op when gitsigns isn't attached)
local gs = require('gitsigns')
vim.keymap.set('n', '<leader>n', function() gs.nav_hunk('next') end, { silent = true })
vim.keymap.set('n', '<leader>p', function() gs.nav_hunk('prev') end, { silent = true })

require('blink.cmp').setup({
    fuzzy = {
        implementation = 'prefer_rust',
        prebuilt_binaries = {
            force_version = 'v1.7.0',
        },
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
        find = '',
        find_left = '',
        highlight = '',
        replace = '<leader>sr',
        update_n_lines = '',
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

local ts_languages = { "lua", "vim", "vimdoc", "javascript", "typescript", "python" }
local has_ts_configs, ts_configs = pcall(require, 'nvim-treesitter.configs')

if has_ts_configs then
    ts_configs.setup({
        ensure_installed = ts_languages,
        auto_install = true,
        highlight = {
            enable = true,
        },
    })
else
    local has_ts, ts = pcall(require, 'nvim-treesitter')
    if has_ts then
        ts.setup({})

        if #vim.api.nvim_list_uis() > 0 then
            local installed = ts.get_installed()
            local missing = {}

            for _, language in ipairs(ts_languages) do
                local is_installed = false
                for _, installed_language in ipairs(installed) do
                    if installed_language == language then
                        is_installed = true
                        break
                    end
                end

                if not is_installed then
                    table.insert(missing, language)
                end
            end

            if #missing > 0 then
                ts.install(missing)
            end
        end

        vim.api.nvim_create_autocmd('FileType', {
            callback = function(args)
                pcall(vim.treesitter.start, args.buf)
            end,
        })
    end
end

require('treesitter-context').setup({
    enable = true,
    max_lines = 4,
})

require('diffview').setup({

    view = {
        default = { layout = "diff2_horizontal" },
        merge_tool = { layout = "diff3_horizontal" },
        file_history = { layout = "diff2_horizontal" },
    },
    keymaps = {
        view = {
            { "n", "<leader>n", "]c", { desc = "Next hunk" } },
            { "n", "<leader>p", "[c", { desc = "Previous hunk" } },
            { "n", "q", "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } },
        },
        file_panel = {
            { "n", "q", "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } },
        },
        file_history_panel = {
            { "n", "q", "<cmd>DiffviewClose<CR>", { desc = "Close diffview" } },
        },
    },
})

-- Vd: diff current branch against its fork point from master/main
vim.api.nvim_create_user_command('Vd', function()
    local base = 'master'
    if vim.fn.system('git rev-parse --verify origin/master 2>/dev/null'):find('^fatal') or
       vim.v.shell_error ~= 0 then
        base = 'main'
    end
    vim.fn.system('git fetch origin ' .. base .. ' --quiet 2>/dev/null')
    local current = vim.fn.system('git branch --show-current'):gsub('%s+$', '')
    if current == base then
        vim.cmd('DiffviewOpen HEAD~1')
    else
        local fork = vim.fn.system('git merge-base HEAD origin/' .. base):gsub('%s+$', '')
        vim.cmd('DiffviewOpen ' .. fork)
    end
end, { desc = 'Diff branch against fork point' })

-- Vdh: file history in diffview
vim.api.nvim_create_user_command('Vdh', function(opts)
    if opts.args ~= '' then
        vim.cmd('DiffviewFileHistory ' .. opts.args)
    else
        vim.cmd('DiffviewFileHistory')
    end
end, { nargs = '?', complete = 'file', desc = 'Diffview file history' })

require('snacks').setup({
    input = { enabled = true },
    terminal = { enabled = true }
})

vim.g.opencode_opts = {
    provider = { enabled = false }  -- Always use external opencode instances (started with --port)
}
vim.opt.autoread = true

require('better_escape').setup({
    timeout = 100,  -- fast jk escape
    mappings = {
        i = { j = { k = "<Esc>" } },
    },
})
