return {
  "fang2hou/go-impl.nvim",
  ft = "go",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "nvim-lua/plenary.nvim",

    -- Choose one of the following fuzzy finder
    "folke/snacks.nvim",
    "ibhagwan/fzf-lua",
  },
  opts = {},
  keys = {
    {
      "<leader>Gi",
      function()
        require("go-impl").open()
      end,
      mode = { "n" },
      desc = "Go Impl",
    },
  },
}
