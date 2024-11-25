local wk = require("which-key")
wk.add({

  { "<leader>b", "<cmd>lua require('telescope.builtin').buffers(require('telescope.themes').get_dropdown{previewer = false})<cr>", desc = "Buffers", mode = "n" },

  { "<leader>c", group = "Chat" }, -- group
  { "<leader>ca", "<cmd>GpAppend<cr>", desc = "Append", mode = "n" },
  { "<leader>cb", "<cmd>GpPrepend<cr>", desc = "Prepend", mode = "n" },
  { "<leader>cc", "<cmd>GpChatNew<cr>", desc = "New", mode = "n" },
  { "<leader>cf", "<cmd>GpChatFinder<cr>", desc = "Find", mode = "n" },
  { "<leader>cn", "<cmd>GpNextAgent<cr>", desc = "Agents", mode = "n" },
  { "<leader>cr", "<cmd>GpRewrite<cr>", desc = "Rewrite", mode = "v" },
  { "<leader>cs", "<cmd>GpStop<cr>", desc = "Stop", mode = "n" },
  { "<leader>ct", "<cmd>GpChatToggle<cr>", desc = "Toggle", mode = "n" },
  { "<leader>cg", "<cmd>GpChatRespond<cr>", desc = "Respond", mode = "n" },

  { "<leader>v", "<cmd>lua require('telescope.builtin').buffers(require('telescope.themes').get_dropdown{previewer = false})<cr>", desc = "Buffers", mode = "n" },

  { "<leader>f", "<cmd>Telescope find_files<cr>", desc = "Find File", mode = "n" },
  { "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "Explorer", mode = "n" },
  { "<leader>h",  "<cmd>nohlsearch<CR>", desc = "No Highlight" },
  { "<leader>F",  "<cmd>Telescope live_grep theme=ivy<cr>", desc = "Find Text" },

  { "<leader>a", group = "Args" },
  {"<leader>aw", "<cmd>:ArgWrap<cr>", desc = "Wrap"},

  { "<leader>as", group = "Swap" },
  { "<leader>asp",
   "<cmd>TSTextobjectSwapPrevious @parameter.inner<cr>",
   desc = "Previous"
  },
  { "<leader>asn",
   "<cmd>TSTextobjectSwapNext @parameter.inner<cr>",
   desc = "Next"
  },

  {"<leader>p", group="Harpoon"},
  {"<leader>pa", "<cmd>lua require('harpoon.mark').add_file()<cr>", desc = "add mark" },
  {"<leader>pm", "<cmd>lua require('harpoon.ui').toggle_quick_menu()<cr>", desc = "menu" },

  {"<leader>g", group="git"},
  {"<leader>gj", "<cmd>lua require 'gitsigns'.next_hunk()<cr>", desc = "Next Hunk" },
  {"<leader>gk", "<cmd>lua require 'gitsigns'.prev_hunk()<cr>", desc = "Prev Hunk" },
  {"<leader>gl", "<cmd>lua require 'gitsigns'.blame_line()<cr>", desc = "Blame line" },
  {"<leader>gp", "<cmd>lua require 'gitsigns'.preview_hunk()<cr>", desc = "Preview Hunk" },
  {"<leader>gr", "<cmd>lua require 'gitsigns'.reset_hunk()<cr>", desc = "Reset Hunk" },
  {"<leader>gR", "<cmd>lua require 'gitsigns'.reset_buffer()<cr>", desc = "Reset Buffer" },
  {"<leader>gs", "<cmd>lua require 'gitsigns'.stage_hunk()<cr>", desc = "Stage Hunk" },
  {"<leader>gu", "<cmd>lua require 'gitsigns'.undo_stage_hunk()<cr>", desc = "Undo Stage Hunk" },
  {"<leader>go", "<cmd>Telescope git_status<cr>", desc = "Open changed file" },
  {"<leader>gb", "<cmd>Telescope git_branches<cr>", desc = "Checkout Branch" },
  {"<leader>gc", "<cmd>Telescope git_commits<cr>", desc = "Checkout Commit" },
  {"<leader>gd", "<cmd>/gitsigns diffthis HEAD<cr>", desc = "Diff" },

  {"<leader>l", group="LSP"},
  {"<leader>la", "<cmd>lua vim.lsp.buf.code_action()<cr>", desc = "Code Action" },
  {"<leader>ld", "<cmd>Telescope lsp_document_diagnostics<cr>", desc = "Document Diagnostics" },
  {"<leader>lw", "<cmd>Telescope lsp_workspace_diagnostics<cr>", desc = "Workspace Diagnostics" },
  {"<leader>lf", "<cmd>lua vim.lsp.buf.formatting()<cr>", desc = "Format" },
  {"<leader>li", "<cmd>LspInfo<cr>", desc = "Info" },
  {"<leader>lI", "<cmd>LspInstallInfo<cr>", desc = "Installer Info" },
  {"<leader>lj", "<cmd>lua vim.lsp.diagnostic.goto_next()<cr>", desc = "Next Diagnostic" },
  {"<leader>lk", "<cmd>lua vim.lsp.diagnostic.goto_prev()<cr>", desc = "Prev Diagnostic" },
  {"<leader>ll", "<cmd>lua vim.lsp.codelens.run()<cr>", desc = "CodeLens Action" },
  {"<leader>ll", "<cmd>lua vim.lsp.diagnostic.set_loclist()<cr>", desc = "Quickfix" },
  {"<leader>lr", "<cmd>lua vim.lsp.buf.rename()<cr>", desc = "Rename" },
  {"<leader>ls", "<cmd>Telescope lsp_document_symbols<cr>", desc = "Document Symbols" },
  {"<leader>lS", "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", desc = "Workspace Symbols" },
  {"<leader>lp", "<cmd>lua require('user.lsp.peek').Peek('definition')<cr>", desc = "Peek Definition" },

  {"<leader>s", group="Search"},
  {"<leader>sc", "<cmd>Telescope colorscheme<cr>", desc = "Colorscheme" },
  {"<leader>sf", "<cmd>Telescope oldfiles<cr>", desc = "Recent files" },
  {"<leader>sr", "<cmd>Telescope registers<cr>", desc = "Registers" },
  {"<leader>sk", "<cmd>Telescope keymaps<cr>", desc = "Keymaps" },
  {"<leader>sC", "<cmd>Telescope commands<cr>", desc = "Commands" },

  {"<leader>d", group="DAP"},
  {"<leader>db", "<cmd>DapToggleBreakpoint<cr>", desc = "Breakpoint" },
  {"<leader>dc", "<cmd>DapContinue<cr>", desc = "Continue" },
  {"<leader>dr", "<cmd>DapToggleRepl<cr>", desc = "Repl" },
  {"<leader>dO", "<cmd>DapStepOut<cr>", desc = "Step Out" },
  {"<leader>di", "<cmd>DapStepInto<cr>", desc = "Step Into" },
  {"<leader>do", "<cmd>DapStepOver<cr>", desc = "Step Over" },
  {"<leader>dt", "<cmd>DapTerminate<cr>", desc = "Terminate" },
  {"<leader>du", "<cmd>lua require('dapui').toggle()<cr>", desc = "UI" },
  {
    mode = { "n", "v" }, -- NORMAL and VISUAL mode
    { "<leader>q", "<cmd>q<cr>", desc = "Quit" }, -- no need to specify mode since it's inherited
    { "<leader>w", "<cmd>w<cr>", desc = "Write" },
    }
  })
