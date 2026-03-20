-- Include hidden files in grug-far searches while always excluding .git and dependency directories
return {
  {
    "MagicDuck/grug-far.nvim",
    opts = {
      headerMaxWidth = 80,
      engines = {
        ripgrep = {
          extraArgs = "--hidden --glob=!node_modules/** --glob=!.gradle/** --glob=!.m2/** --glob=!target/** --glob=!build/**",
        },
      },
    },
    cmd = { "GrugFar", "GrugFarWithin" },
    keys = {
      {
        "<leader>sr",
        function()
          local grug = require("grug-far")
          grug.open({ transient = true })
        end,
        mode = { "n", "x" },
        desc = "Search and Replace",
      },
    },
  },
}
