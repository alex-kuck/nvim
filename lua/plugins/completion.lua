return {
  {
    "hrsh7th/nvim-cmp",
    opts = function(_, opts)
      opts.completion.completeopt = "menu,menuone,noinsert"

      opts.experimental = {
        ghost_text = true, -- Inline suggestions
      }
    end,
  },
}
