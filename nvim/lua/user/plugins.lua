local fn = vim.fn

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)


plugins = {
  "nvim-lua/popup.nvim", -- An implementation of the Popup API from vim in Neovim
  "nvim-lua/plenary.nvim", -- Useful lua functions used ny lots of plugins
  "kyazdani42/nvim-web-devicons",
  "kyazdani42/nvim-tree.lua",{
  'stevearc/oil.nvim',
    opts = {},
    -- Optional dependencies
    dependencies = { "nvim-tree/nvim-web-devicons" },
  },
  "akinsho/toggleterm.nvim",
  "lewis6991/impatient.nvim",
  "lukas-reineke/indent-blankline.nvim",
  "antoinemadec/FixCursorHold.nvim", -- This is needed to fix lsp doc highlight
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Buffer Local Keymaps (which-key)",
      },
    },
  },
  "gcmt/wildfire.vim",
  { 'echasnovski/mini.nvim', branch = 'stable' },
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    ---@type Flash.Config
    opts = {
        modes = {
          char = {
            enabled = false
          },
          search = {
            enabled = false
          }
        }
      },
    -- stylua: ignore
    keys = {
      { "s", mode = { "n", "o", "x" }, function() require("flash").jump() end, desc = "Flash" },
      { "S", mode = { "n", "o", "x" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
      { "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
    },
  },
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "rcarriga/nvim-notify",
    }
  },
  { 'FooSoft/vim-argwrap'},
  {"ThePrimeagen/harpoon"},
  {
    "gbprod/yanky.nvim",
    config = function()
      require('yanky').setup({})
    end
  },

  -- Colorschemes
  -- "lunarvim/darkplus.nvim"
  { "catppuccin/nvim", as = "mocha" },
  -- 'overcache/NeoSolarized',

  -- LSP
  "tamago324/nlsp-settings.nvim", -- language server settings defined {
  "neovim/nvim-lspconfig", -- enable LSP-- LSP Support
  {'williamboman/mason.nvim'},
  {'williamboman/mason-lspconfig.nvim'},
  {"ray-x/lsp_signature.nvim"},
  {"https://git.sr.ht/~whynothugo/lsp_lines.nvim"},
  "williamboman/nvim-lsp-installer", -- simple to language server installer
  {'hrsh7th/cmp-nvim-lsp-signature-help'},
  "jose-elias-alvarez/null-ls.nvim", -- for formatters and linters
  {
    "scalameta/nvim-metals",
    requires = {
      "nvim-lua/plenary.nvim",
      "mfussenegger/nvim-dap",
    },
  },
  'simrat39/rust-tools.nvim',
  {
    "pmizio/typescript-tools.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig" },
    opts = {},
  },

  -- Autocompletion
  {'hrsh7th/nvim-cmp'},
  {'hrsh7th/cmp-buffer'},
  {'hrsh7th/cmp-path'},
  -- {'saadparwaiz1/cmp_luasnip'},
  {'hrsh7th/cmp-nvim-lsp'},
  {'hrsh7th/cmp-nvim-lua'},
  {'rafamadriz/friendly-snippets'},
  -- AI autocompletion
  {
    "supermaven-inc/supermaven-nvim",
    config = function()
      require("supermaven-nvim").setup({})
    end,
  },
  -- AI assistants
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    lazy = false,
    version = false, -- set this if you want to always pull the latest change
    opts = {
      -- add any opts here
    },
    build = "make",
    dependencies = {
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "hrsh7th/nvim-cmp", -- autocompletion for avante commands and mentions
      "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
      "zbirenbaum/copilot.lua", -- for providers='copilot'
      {
        "HakonHarnes/img-clip.nvim",
        event = "VeryLazy",
        opts = {
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = {
              insert_mode = true,
            },
          },
        },
      },
      {
        'MeanderingProgrammer/render-markdown.nvim',
        opts = {
          file_types = { "markdown", "Avante" },
        },
        ft = { "markdown", "Avante" },
      },
    },
  },
--  {
--     "robitx/gp.nvim",
--     config = function()
--         require("gp").setup({
--           openai_api_key = {"cat", "/Users/tsah/openai_key"},
--           providers = {
--             anthropic = {
--               endpoint = "https://api.anthropic.com/v1/messages",
--               secret = {"cat", "/Users/tsah/anthropic_key"},
--             },
--           }
--         })
--     end,
-- },
  -- Telescope
  "nvim-telescope/telescope.nvim",
  {
    "AckslD/nvim-neoclip.lua",
    requires = {
      {'kkharji/sqlite.lua', module = 'sqlite'},
      -- you'll need at least one of these
    },
    config = function()
      require('neoclip').setup()
    end,
  },
  { 'nvim-telescope/telescope-fzf-native.nvim', run = 'make', cond = vim.fn.executable 'make' == 1 },
  -- Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    run = ":TSUpdate",
  },
  "JoosepAlviste/nvim-ts-context-commentstring",
  'nvim-treesitter/nvim-treesitter-textobjects',
  'nvim-treesitter/nvim-treesitter-context',
  -- Git
  "tpope/vim-fugitive",
  "tpope/vim-rhubarb",
  "lewis6991/gitsigns.nvim",

  -- DAP
  {"mfussenegger/nvim-dap"},
  { "rcarriga/nvim-dap-ui", requires = {"mfussenegger/nvim-dap"} },
  {
    'mfussenegger/nvim-dap-python',
    config = function ()
      require('dap-python').setup()
      require('dap-python').test_runner = 'pytest'
    end
  },
  -- tmux
  {
    'mrjones2014/smart-splits.nvim',
    config = function()
      require('smart-splits').setup()
    end,
  },
  -- markdown
  {
    'MeanderingProgrammer/render-markdown.nvim',
    opts = {},
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.nvim' }, -- if you use the mini.nvim suite
    -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
  }
}
require("lazy").setup(plugins)

