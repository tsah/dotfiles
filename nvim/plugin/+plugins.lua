vim.g.mapleader = " "

local plugins = {
    { src = "https://github.com/mason-org/mason.nvim" },
    { src = "https://github.com/catppuccin/nvim" },
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
     { src = "https://github.com/AckslD/nvim-trevJ.lua" },
     { src = "https://github.com/luancgs/argonaut.nvim" },
     { src = "https://github.com/neovim/nvim-lspconfig" },
    { src = "https://github.com/pmizio/typescript-tools.nvim" },
    { src = "https://github.com/folke/flash.nvim" },
    { src = "https://github.com/nvim-lua/plenary.nvim" },
    { src = "https://github.com/lervag/vimtex" },
    { src = "https://github.com/mikavilpas/yazi.nvim" },
    { src = "https://github.com/nvim-treesitter/nvim-treesitter" },
    { src = "https://github.com/nvim-treesitter/nvim-treesitter-context" },
    { src = "https://github.com/MunifTanjim/nui.nvim" },
    { src = "https://github.com/julienvincent/hunk.nvim" },
    { src = "https://github.com/folke/snacks.nvim" },
    { src = "https://github.com/NickvanDyke/opencode.nvim" },
}

vim.pack.add(plugins, { load = true })

vim.env.PATH = vim.fn.stdpath("data") .. "/mason/bin:" .. vim.env.PATH
