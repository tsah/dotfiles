local status_ok, which_key = pcall(require, "which-key")
if not status_ok then
  return
end

local setup = {
  plugins = {
    marks = true, -- shows a list of your marks on ' and `
    registers = true, -- shows your registers on " in NORMAL or <C-r> in INSERT mode
    spelling = {
      enabled = true, -- enabling this will show WhichKey when pressing z= to select spelling suggestions
      suggestions = 20, -- how many suggestions should be shown in the list?
    },
    -- the presets plugin, adds help for a bunch of default keybindings in Neovim
    -- No actual key bindings are created
    presets = {
      operators = false, -- adds help for operators like d, y, ... and registers them for motion / text object completion
      motions = true, -- adds help for motions
      text_objects = true, -- help for text objects triggered after entering an operator
      windows = true, -- default bindings on <c-w>
      nav = true, -- misc bindings to work with windows
      z = true, -- bindings for folds, spelling and others prefixed with z
      g = true, -- bindings for prefixed with g
    },
  },
  -- add operators that will trigger motion and text object completion
  -- to enable all native operators, set the preset / operators plugin above
  -- operators = { gc = "Comments" },
  icons = {
    breadcrumb = "»", -- symbol used in the command line area that shows your active key combo
    separator = "➜", -- symbol used between a key and it's label
    group = "+", -- symbol prepended to a group
  },
  keys = {
    scroll_down = "<c-d>", -- binding to scroll down inside the popup
    scroll_up = "<c-u>", -- binding to scroll up inside the popup
  },
  win = {
    no_overlap = true,
    -- width = 1,
    -- height = { min = 4, max = 25 },
    -- col = 0,
    -- row = math.huge,
    -- border = "none",
    padding = { 1, 2 }, -- extra window padding [top/bottom, right/left]
    title = true,
    title_pos = "center",
    zindex = 1000,
  },
  layout = {
    height = { min = 4, max = 25 }, -- min and max height of the columns
    width = { min = 20, max = 50 }, -- min and max width of the columns
    spacing = 3, -- spacing between columns
    align = "left", -- align columns left, center or right
  },
  show_help = true, -- show help message on the command line when the popup is visible
}

local normal_opts = {
  mode = "n", -- NORMAL mode
  buffer = nil, -- Global mappings. Specify a buffer number for buffer local mappings
  silent = true, -- use `silent` when creating keymaps
  noremap = true, -- use `noremap` when creating keymaps
  nowait = true, -- use `nowait` when creating keymaps
}

local normal_mappings = {
  ["<leader>"] = {
    b = {
      "<cmd>lua require('telescope.builtin').buffers(require('telescope.themes').get_dropdown{previewer = false})<cr>",
      "Buffers",
    },
    c = {
      name = "GP",
      -- ["<C-t>"] = { "<cmd>GpChatNew tabnew<cr>", "New Chat tabnew" },
      -- ["<C-v>"] = { "<cmd>GpChatNew vsplit<cr>", "New Chat vsplit" },
      -- ["<C-x>"] = { "<cmd>GpChatNew split<cr>", "New Chat split" },
      a = { "<cmd>GpAppend<cr>", "Append (after)" },
      b = { "<cmd>GpPrepend<cr>", "Prepend (before)" },
      c = { "<cmd>GpChatNew<cr>", "New Chat" },
      f = { "<cmd>GpChatFinder<cr>", "Chat Finder" },
      g = { "generate into new .." ,
        e = { "<cmd>GpEnew<cr>", "GpEnew" },
        n = { "<cmd>GpNew<cr>", "GpNew" },
        p = { "<cmd>GpPopup<cr>", "Popup" },
        t = { "<cmd>GpTabnew<cr>", "GpTabnew" },
        g = { "<cmd>GpVnew<cr>", "GpVnew" },
      },
      n = { "<cmd>GpNextAgent<cr>", "Next Agent" },
      r = { "<cmd>GpRewrite<cr>", "Inline Rewrite" },
      s = { "<cmd>GpStop<cr>", "GpStop" },
      t = { "<cmd>GpChatToggle<cr>", "Toggle Chat" },
      w = {
        name = "Whisper",
        a = { "<cmd>GpWhisperAppend<cr>", "Whisper Append (after)" },
        b = { "<cmd>GpWhisperPrepend<cr>", "Whisper Prepend (before)" },
        e = { "<cmd>GpWhisperEnew<cr>", "Whisper Enew" },
        n = { "<cmd>GpWhisperNew<cr>", "Whisper New" },
        p = { "<cmd>GpWhisperPopup<cr>", "Whisper Popup" },
        r = { "<cmd>GpWhisperRewrite<cr>", "Whisper Inline Rewrite" },
        t = { "<cmd>GpWhisperTabnew<cr>", "Whisper Tabnew" },
        v = { "<cmd>GpWhisperVnew<cr>", "Whisper Vnew" },
        w = { "<cmd>GpWhisper<cr>", "Whisper" },
      },
      x = { "<cmd>GpContext<cr>", "Toggle GpContext" },
    },
    e = { "<cmd>NvimTreeToggle<cr>", "Explorer" },
    w = { "<cmd>w!<CR>", "Save" },
    q = { "<cmd>q!<CR>", "Quit" },
    Q = { "<cmd>ccl<CR>", "Close quickfix" },
    h = { "<cmd>nohlsearch<CR>", "No Highlight" },
    f = {
      "<cmd>lua require('telescope.builtin').find_files(require('telescope.themes').get_dropdown{previewer = false})<cr>",
      "Find files",
    },
    F = { "<cmd>Telescope live_grep theme=ivy<cr>", "Find Text" },
    y = {"<cmd>lua require('telescope').extensions.neoclip.default()<cr>", "Find in clipboard"},
    P = { "<cmd>lua require('telescope').extensions.projects.projects()<cr>", "Projects" },
    a = {
      name = "Args",
      s = {
        name = "Swap",
        p = {
          "<cmd>TSTextobjectSwapPrevious @parameter.inner<cr>",
          "Previous"
        },
        n = {
          "<cmd>TSTextobjectSwapNext @parameter.inner<cr>",
          "Next"
        },
      },
      w = {
          "<cmd>:ArgWrap<cr>",
          "Wrap"
      }
    },
    p = {
      name = "harpoon",
      a = { "<cmd>lua require('harpoon.mark').add_file()<cr>", "add mark" },
      m = { "<cmd>lua require('harpoon.ui').toggle_quick_menu()<cr>", "menu" },
    },

    g = {
      name = "Git",
      g = { "<cmd>lua _LAZYGIT_TOGGLE()<CR>", "Lazygit" },
      j = { "<cmd>lua require 'gitsigns'.next_hunk()<cr>", "Next Hunk" },
      k = { "<cmd>lua require 'gitsigns'.prev_hunk()<cr>", "Prev Hunk" },
      l = { "<cmd>lua require 'gitsigns'.blame_line()<cr>", "Blame" },
      p = { "<cmd>lua require 'gitsigns'.preview_hunk()<cr>", "Preview Hunk" },
      r = { "<cmd>lua require 'gitsigns'.reset_hunk()<cr>", "Reset Hunk" },
      R = { "<cmd>lua require 'gitsigns'.reset_buffer()<cr>", "Reset Buffer" },
      s = { "<cmd>lua require 'gitsigns'.stage_hunk()<cr>", "Stage Hunk" },
      u = {
        "<cmd>lua require 'gitsigns'.undo_stage_hunk()<cr>",
        "Undo Stage Hunk",
      },
      o = { "<cmd>Telescope git_status<cr>", "Open changed file" },
      b = { "<cmd>Telescope git_branches<cr>", "Checkout branch" },
      c = { "<cmd>Telescope git_commits<cr>", "Checkout commit" },
      d = {
        "<cmd>Gitsigns diffthis HEAD<cr>",
        "Diff",
      },
    },

    l = {
      name = "LSP",
      a = { "<cmd>lua vim.lsp.buf.code_action()<cr>", "Code Action" },
      d = {
        "<cmd>Telescope lsp_document_diagnostics<cr>",
        "Document Diagnostics",
      },
      w = {
        "<cmd>Telescope lsp_workspace_diagnostics<cr>",
        "Workspace Diagnostics",
      },
      f = { "<cmd>lua vim.lsp.buf.formatting()<cr>", "Format" },
      i = { "<cmd>LspInfo<cr>", "Info" },
      I = { "<cmd>LspInstallInfo<cr>", "Installer Info" },
      j = {
        "<cmd>lua vim.lsp.diagnostic.goto_next()<CR>",
        "Next Diagnostic",
      },
      k = {
        "<cmd>lua vim.lsp.diagnostic.goto_prev()<cr>",
        "Prev Diagnostic",
      },
      l = { "<cmd>lua vim.lsp.codelens.run()<cr>", "CodeLens Action" },
      q = { "<cmd>lua vim.lsp.diagnostic.set_loclist()<cr>", "Quickfix" },
      r = { "<cmd>lua vim.lsp.buf.rename()<cr>", "Rename" },
      s = { "<cmd>Telescope lsp_document_symbols<cr>", "Document Symbols" },
      S = {
        "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>",
        "Workspace Symbols",
      },
      p = {
        "<cmd> lua require('user.lsp.peek').Peek('definition')",
            "Peek definition",
        },
    },
    s = {
      name = "Search/surround",
      s = {
        name = "Surround",
        a = {"<cmd> lua require('mini.surround').add()<cr>", "Add"},
        d = {"<cmd> lua require('mini.surround').delete()<cr>", "Delete"},
        f = {"<cmd> lua require('mini.surround').find()<cr>", "Find"},
        h = {"<cmd> lua require('mini.surround').highlight()<cr>", "Highlight"},
        r = {"<cmd> lua require('mini.surround').operator('replace') . ' '<cr>", "Replace"},
      },
      b = { "<cmd>Telescope git_branches<cr>", "Checkout branch" },
      c = { "<cmd>Telescope colorscheme<cr>", "Colorscheme" },
      h = { "<cmd>Telescope help_tags<cr>", "Find Help" },
      M = { "<cmd>Telescope man_pages<cr>", "Man Pages" },
      r = { "<cmd>Telescope oldfiles<cr>", "Open Recent File" },
      R = { "<cmd>Telescope registers<cr>", "Registers" },
      k = { "<cmd>Telescope keymaps<cr>", "Keymaps" },
      C = { "<cmd>Telescope commands<cr>", "Commands" },
    },

    t = {
      name = "Terminal",
      p = { "<cmd>lua _PYTHON_TOGGLE()<cr>", "Python" },
      f = { "<cmd>ToggleTerm direction=float<cr>", "Float" },
      h = { "<cmd>ToggleTerm size=10 direction=horizontal<cr>", "Horizontal" },
      v = { "<cmd>ToggleTerm size=80 direction=vertical<cr>", "Vertical" },
    },
    d = {
      name = "DAP",
      b = {"<cmd> DapToggleBreakpoint<cr>", "Toggle Breakpoint"},
      c = {"<cmd> DapContinue<cr>", "Continue"},
      r = {"<cmd> DapToggleRepl<cr>", "REPL"},
      O = {"<cmd> DapStepOut<cr>", "Step out"},
      i = {"<cmd> DapStepInto<cr>", "Step into"},
      o = {"<cmd> DapStepOver<cr>", "Step over"},
      t = {"<cmd> DapTerminate<cr>", "Terminate"},
      u = {'<cmd>lua require"dapui".toggle()<cr>', "UI"},
    },
  },
}

local v_opts = {
  mode = "v", -- NORMAL mode
  buffer = nil, -- Global mappings. Specify a buffer number for buffer local mappings
  silent = true, -- use `silent` when creating keymaps
  noremap = true, -- use `noremap` when creating keymaps
  nowait = true, -- use `nowait` when creating keymaps
}

local v_mapping = {
    r = {
      name = "Refactor",
      e = { [[ <Esc><Cmd>lua require('refactoring').refactor('Extract Function')<CR>]], "Extract Function" },
      f = {
        [[ <Esc><Cmd>lua require('refactoring').refactor('Extract Function to File')<CR>]],
        "Extract Function to File",
      },
      v = { [[ <Esc><Cmd>lua require('refactoring').refactor('Extract Variable')<CR>]], "Extract Variable" },
      i = { [[ <Esc><Cmd>lua require('refactoring').refactor('Inline Variable')<CR>]], "Inline Variable" },
      r = { [[ <Esc><Cmd>lua require('telescope').extensions.refactoring.refactors()<CR>]], "Refactor" },
      V = { [[ <Esc><Cmd>lua require('refactoring').debug.print_var({})<CR>]], "Debug Print Var" },
    },
  }
which_key.setup(setup)
which_key.register(normal_mappings, normal_opts)
which_key.register(v_mapping, v_opts)
