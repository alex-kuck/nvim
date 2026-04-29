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

  -- Show all indent guides (gray) with active scope highlighted (blue).
  {
    "snacks.nvim",
    opts = {
      indent = {
        enabled = true,
        char = "▎",
        only_scope = false,
        hl = "SnacksIndent",
      },
      animate = { enabled = false },
      scope = {
        enabled = true,
        char = "▎",
        hl = "SnacksIndentScope",
      },
      picker = {
        hidden = true,
        sources = {
          files = {
            hidden = true,
          },
        },
      },
    },
    init = function()
      local group = vim.api.nvim_create_augroup("snacks_indent_hl", { clear = true })

      local function set_indent_hl()
        vim.api.nvim_set_hl(0, "SnacksIndent", { fg = "#4a4a5a" })
        vim.api.nvim_set_hl(0, "SnacksIndentScope", { fg = "#7aa2f7" })
      end

      set_indent_hl()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = set_indent_hl,
      })

      -- Open explorer on startup only for repo-root sessions (no direct file args).
      -- This keeps startup clean when launching into a specific file.
      local function should_open_explorer_on_start()
        local argc = vim.fn.argc()
        if argc > 0 then
          for i = 0, argc - 1 do
            local arg = vim.fn.argv(i)
            if arg ~= "" then
              local abs = vim.fn.fnamemodify(arg, ":p")
              if vim.fn.isdirectory(abs) == 0 then
                return false
              end
            end
          end
        end

        local cwd = vim.uv.cwd() or vim.fn.getcwd()
        if not cwd or cwd == "" then
          return false
        end
        return vim.fs.find({ ".git" }, { path = cwd, upward = true })[1] ~= nil
      end

      -- Keep startup dashboard focused after opening the explorer sidebar.
      local function find_dashboard_win()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_is_valid(win) then
            local buf = vim.api.nvim_win_get_buf(win)
            local ft = vim.bo[buf].filetype
            if ft == "snacks_dashboard" or ft == "dashboard" or ft == "ministarter" then
              return win
            end
          end
        end
      end

      vim.api.nvim_create_autocmd("VimEnter", {
        group = group,
        once = true,
        callback = function()
          vim.schedule(function()
            if should_open_explorer_on_start() and type(Snacks) == "table" and Snacks.explorer and Snacks.explorer.open then
              local target_win = find_dashboard_win() or vim.api.nvim_get_current_win()
              Snacks.explorer.open()
              vim.defer_fn(function()
                local restore_win = find_dashboard_win() or target_win
                if restore_win and vim.api.nvim_win_is_valid(restore_win) then
                  vim.api.nvim_set_current_win(restore_win)
                end
              end, 20)
            end
          end)
        end,
      })
    end,
  },

  -- Git change indicators in the gutter (IntelliJ-like bars).
  {
    "lewis6991/gitsigns.nvim",
    keys = {
      {
        "]h",
        function()
          require("gitsigns").next_hunk()
        end,
        desc = "Next Git Hunk",
      },
      {
        "[h",
        function()
          require("gitsigns").prev_hunk()
        end,
        desc = "Prev Git Hunk",
      },
      {
        "<leader>gh",
        function()
          require("gitsigns").preview_hunk()
        end,
        desc = "Git Preview Hunk",
      },
      {
        "<leader>gs",
        function()
          require("gitsigns").stage_hunk()
        end,
        desc = "Git Stage Hunk",
      },
      {
        "<leader>gr",
        function()
          require("gitsigns").reset_hunk()
        end,
        desc = "Git Reset Hunk",
      },
      {
        "<leader>gS",
        function()
          require("gitsigns").stage_buffer()
        end,
        desc = "Git Stage Buffer",
      },
      {
        "<leader>gR",
        function()
          require("gitsigns").reset_buffer()
        end,
        desc = "Git Reset Buffer",
      },
      {
        "<leader>gb",
        function()
          require("gitsigns").blame_line({ full = true })
        end,
        desc = "Git Blame Line",
      },
      {
        "<leader>gd",
        function()
          require("gitsigns").diffthis()
        end,
        desc = "Git Diff This",
      },
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
      current_line_blame = true,
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

  -- Add current repository name between mode and branch in lualine.
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      local function repo_name()
        local root = vim.fs.root(0, { ".git" })
        if not root or root == "" then
          return ""
        end
        return vim.fs.basename(root)
      end

      opts.sections = opts.sections or {}
      opts.sections.lualine_b = opts.sections.lualine_b or {}
      table.insert(opts.sections.lualine_b, 1, {
        repo_name,
        icon = "",
        separator = { right = "" },
        cond = function()
          return repo_name() ~= ""
        end,
      })
    end,
  },
}
