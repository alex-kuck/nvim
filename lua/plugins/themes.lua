return {
  {
    "projekt0n/github-nvim-theme",
    name = "github-theme",
    lazy = false, -- make sure we load this during startup if it is your main colorscheme
    priority = 1000, -- make sure to load this before all the other start plugins
    config = function()
      require("github-theme").setup({
        -- ...
        options = {
          transparent = true,
          dim_inactive = true,
        },
      })

      vim.cmd("colorscheme github_dark_high_contrast")

      vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
        callback = function()
          vim.api.nvim_set_hl(0, "Normal", { fg = "#ffdb00" })
        end,
        desc = "Set active buffer text to bright yellow",
      })
    end,
  },
  -- {
  --   "folke/tokyonight.nvim",
  --   opts = {
  --     transparent = true,
  --     styles = {
  --       sidebars = "transparent",
  --       floats = "transparent",
  --     },
  --   },
  -- },
}
