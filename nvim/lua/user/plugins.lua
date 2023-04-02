local fn = vim.fn

-- Automatically install packer
local install_path = fn.stdpath "data" .. "/site/pack/packer/start/packer.nvim"
if fn.empty(fn.glob(install_path)) > 0 then
  PACKER_BOOTSTRAP = fn.system {
    "git",
    "clone",
    "--depth",
    "1",
    "https://github.com/wbthomason/packer.nvim",
    install_path,
  }
  print "Installing packer close and reopen Neovim..."
  vim.cmd [[packadd packer.nvim]]
end

-- Autocommand that reloads neovim whenever you save the plugins.lua file
vim.cmd [[
  augroup packer_user_config
    autocmd!
    autocmd BufWritePost plugins.lua source <afile> | PackerSync
  augroup end
]]

-- Use a protected call so we don't error out on first use
local status_ok, packer = pcall(require, "packer")
if not status_ok then
  return
end

-- Have packer use a popup window
packer.init {
  display = {
    open_fn = function()
      return require("packer.util").float { border = "rounded" }
    end,
  },
}

return packer.startup(function(use)
  use "wbthomason/packer.nvim" -- Have packer manage itself
  use "nvim-lua/popup.nvim" -- An implementation of the Popup API from vim in Neovim
  use "nvim-lua/plenary.nvim" -- Useful lua functions used ny lots of plugins
  use "kyazdani42/nvim-web-devicons"
  use "kyazdani42/nvim-tree.lua"
  use "akinsho/toggleterm.nvim"
  use "lewis6991/impatient.nvim"
  use "lukas-reineke/indent-blankline.nvim"
  use "antoinemadec/FixCursorHold.nvim" -- This is needed to fix lsp doc highlight
  use "folke/which-key.nvim"
  use {
    "ggandor/leap.nvim",
    config = function()
      require('leap').set_default_keymaps()
   end
  }
  use { 'echasnovski/mini.nvim', branch = 'stable' }
  use { 'FooSoft/vim-argwrap'}
  use  {"ThePrimeagen/harpoon"}
  use {
    "gbprod/yanky.nvim",
    config = function()
      require('yanky').setup({})
    end
  }

  -- Colorschemes
  -- use "lunarvim/darkplus.nvim"
  use { "catppuccin/nvim", as = "catppuccin" }

  -- LSP
  use "tamago324/nlsp-settings.nvim" -- language server settings defined use {
  use "neovim/nvim-lspconfig" -- enable LSP-- LSP Support
  use {'williamboman/mason.nvim'}
  use {'williamboman/mason-lspconfig.nvim'}
  use {"ray-x/lsp_signature.nvim"}
  use {"https://git.sr.ht/~whynothugo/lsp_lines.nvim"}
  use "williamboman/nvim-lsp-installer" -- simple to use language server installer
  use {'hrsh7th/cmp-nvim-lsp-signature-help'}
  use "jose-elias-alvarez/null-ls.nvim" -- for formatters and linters
  use({
    "scalameta/nvim-metals",
    requires = {
      "nvim-lua/plenary.nvim",
      "mfussenegger/nvim-dap",
    },
  })
  use('simrat39/rust-tools.nvim')

  -- Autocompletion
  use {'hrsh7th/nvim-cmp'}
  use {'hrsh7th/cmp-buffer'}
  use {'hrsh7th/cmp-path'}
  use {'saadparwaiz1/cmp_luasnip'}
  use {'hrsh7th/cmp-nvim-lsp'}
  use {'hrsh7th/cmp-nvim-lua'}

  -- Snippets
  use {'L3MON4D3/LuaSnip'}
  use {'rafamadriz/friendly-snippets'}

  -- Telescope
  use "nvim-telescope/telescope.nvim"
  use {
    "AckslD/nvim-neoclip.lua",
    requires = {
      {'kkharji/sqlite.lua', module = 'sqlite'},
      -- you'll need at least one of these
    },
    config = function()
      require('neoclip').setup()
    end,
  }
  use { 'nvim-telescope/telescope-fzf-native.nvim', run = 'make', cond = vim.fn.executable 'make' == 1 }
  -- Treesitter
  use {
    "nvim-treesitter/nvim-treesitter",
    run = ":TSUpdate",
  }
  use "JoosepAlviste/nvim-ts-context-commentstring"
  use 'nvim-treesitter/nvim-treesitter-textobjects'
  use 'nvim-treesitter/nvim-treesitter-context'
  -- Git
  use "tpope/vim-fugitive"
  use "tpope/vim-rhubarb"
  use "lewis6991/gitsigns.nvim"

  -- DAP
  use {
    'mfussenegger/nvim-dap-python',
    config = function ()
      require('dap-python').setup()
      require('dap-python').test_runner = 'pytest'
    end
  }
  -- Automatically set up your configuration after cloning packer.nvim
  -- Put this at the end after all plugins
  if PACKER_BOOTSTRAP then
    require("packer").sync()
  end
end)
