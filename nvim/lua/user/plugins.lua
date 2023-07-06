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
  "kyazdani42/nvim-tree.lua",
  "akinsho/toggleterm.nvim",
  "lewis6991/impatient.nvim",
  "lukas-reineke/indent-blankline.nvim",
  "antoinemadec/FixCursorHold.nvim", -- This is needed to fix lsp doc highlight
  "folke/which-key.nvim",
{
  "folke/flash.nvim",
  event = "VeryLazy",
  ---@type Flash.Config
  opts = {},
  keys = {
    {
      "s",
      mode = { "n", "x", "o" },
      function()
        require("flash").jump()
      end,
      desc = "Flash",
    },
    {
      "S",
      mode = { "n", "o", "x" },
      function()
        require("flash").treesitter()
      end,
      desc = "Flash Treesitter",
    },
    {
      "r",
      mode = "o",
      function()
        require("flash").remote()
      end,
      desc = "Remote Flash",
    },
    {
      "R",
      mode = { "o", "x" },
      function()
        require("flash").treesitter_search()
      end,
      desc = "Flash Treesitter Search",
    },
    {
      "<c-s>",
      mode = { "c" },
      function()
        require("flash").toggle()
      end,
      desc = "Toggle Flash Search",
    },
  },
} ,
{ 'echasnovski/mini.nvim', branch = 'stable' },
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

  -- Autocompletion
  {'hrsh7th/nvim-cmp'},
  {'hrsh7th/cmp-buffer'},
  {'hrsh7th/cmp-path'},
  {'saadparwaiz1/cmp_luasnip'},
  {'hrsh7th/cmp-nvim-lsp'},
  {'hrsh7th/cmp-nvim-lua'},

  -- Snippets
  {'L3MON4D3/LuaSnip'},
  {'rafamadriz/friendly-snippets'},

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
  { "rcarriga/nvim-dap-ui", requires = {"mfussenegger/nvim-dap"} },
  {
    'mfussenegger/nvim-dap-python',
    config = function ()
      require('dap-python').setup()
      require('dap-python').test_runner = 'pytest'
    end
  },
  -- tmux
  'christoomey/vim-tmux-navigator'

}
require("lazy").setup(plugins)

