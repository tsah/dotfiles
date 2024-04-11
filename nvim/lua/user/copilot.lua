require("copilot").setup({
  suggestion = { enabled = true },
  panel = { enabled = true },
  suggestion = {
    enabled = true,
    auto_trigger = true,
    keymap= {
      accept = "<C-l>",
      accept_word = "<C-h>",
      next = "<M-j>",
      prev = "<M-k>",
    }
  },
})
