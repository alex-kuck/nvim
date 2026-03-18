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

  -- Show indent guides only for the current scope/block.
  {
    "snacks.nvim",
    opts = {
      -- Disable Snacks guides; mini.indentscope below will handle current scope.
      indent = { enabled = false },
      scope = { enabled = false },
    },
  },

  {
    "nvim-mini/mini.indentscope",
    event = "VeryLazy",
    opts = function()
      local indentscope = require("mini.indentscope")
      return {
        -- Draw a single guide only for the current scope.
        symbol = "▎",
        options = {
          try_as_border = true,
        },
        draw = {
          delay = 0,
          animation = indentscope.gen_animation.none(),
        },
      }
    end,
    config = function(_, opts)
      require("mini.indentscope").setup(opts)
    end,
    init = function()
      -- Keep the scope guide visible and consistent across colorschemes.
      local function set_scope_hl()
        vim.api.nvim_set_hl(0, "MiniIndentscopeSymbol", { fg = "#7aa2f7" })
      end
      set_scope_hl()
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = set_scope_hl,
      })
    end,
  },

  -- Git change indicators in the gutter (IntelliJ-like bars).
  {
    "lewis6991/gitsigns.nvim",
    keys = {
      { "]h", function() require("gitsigns").next_hunk() end, desc = "Next Git Hunk" },
      { "[h", function() require("gitsigns").prev_hunk() end, desc = "Prev Git Hunk" },
      { "<leader>gh", function() require("gitsigns").preview_hunk() end, desc = "Git Preview Hunk" },
      { "<leader>gs", function() require("gitsigns").stage_hunk() end, desc = "Git Stage Hunk" },
      { "<leader>gr", function() require("gitsigns").reset_hunk() end, desc = "Git Reset Hunk" },
      { "<leader>gS", function() require("gitsigns").stage_buffer() end, desc = "Git Stage Buffer" },
      { "<leader>gR", function() require("gitsigns").reset_buffer() end, desc = "Git Reset Buffer" },
      { "<leader>gb", function() require("gitsigns").blame_line({ full = true }) end, desc = "Git Blame Line" },
      { "<leader>gd", function() require("gitsigns").diffthis() end, desc = "Git Diff This" },
      {
        "<leader>gt",
        function()
          require("gitsigns").toggle_current_line_blame()
        end,
        desc = "Git Toggle Line Blame",
      },
      {
        "<leader>gD",
        function()
          require("gitsigns").toggle_deleted()
        end,
        desc = "Git Toggle Deleted",
      },
    },
    opts = {
      signs = {
        -- Use slim bars instead of symbols for a cleaner gutter.
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "▎" },
        topdelete = { text = "▎" },
        changedelete = { text = "▎" },
        untracked = { text = "▎" },
      },
      signcolumn = true,
      numhl = false,
      linehl = false,
    },
    config = function(_, opts)
      require("gitsigns").setup(opts)

      -- Force add/change/delete colors to green/blue/red so bars stay consistent
      -- across themes and match requested IDE-style semantics.
      local function set_git_sign_colors()
        vim.api.nvim_set_hl(0, "GitSignsAdd", { fg = "#73daca" })
        vim.api.nvim_set_hl(0, "GitSignsChange", { fg = "#7aa2f7" })
        vim.api.nvim_set_hl(0, "GitSignsDelete", { fg = "#f7768e" })
      end

      set_git_sign_colors()
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = set_git_sign_colors,
      })
    end,
  },
}
