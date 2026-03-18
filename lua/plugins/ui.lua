return {
  -- Better UI for LSP
  {
    "glepnir/lspsaga.nvim",
    event = "LspAttach",
    opts = {
      lightbulb = {
        enable = false, -- disable lightbulb
      },
    },
  },
}
