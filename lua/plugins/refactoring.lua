return {
  {
    "ThePrimeagen/refactoring.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    opts = {
      prompt_func_return_type = {
        go = true,
      },
      prompt_func_param_type = {
        go = true,
      },
      printf_statements = {},
      print_var_statements = {},
    },
    keys = {
      {
        "<leader>rr",
        function()
          require("refactoring").select_refactor()
        end,
        mode = { "n", "x" },
        desc = "Refactor Menu",
      },
      {
        "<leader>re",
        function()
          return require("refactoring").refactor("Extract Function")
        end,
        expr = true,
        mode = { "x" },
        desc = "Extract Function",
      },
      {
        "<leader>rf",
        function()
          return require("refactoring").refactor("Extract Function To File")
        end,
        expr = true,
        mode = { "x" },
        desc = "Extract Function To File",
      },
      {
        "<leader>rv",
        function()
          -- Prefer gopls extract-variable in Go buffers because it is more
          -- reliable than refactoring.nvim's Tree-sitter based extract_var.
          if vim.bo.filetype == "go" then
            local has_gopls = false
            for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
              if client.name == "gopls" then
                has_gopls = true
                break
              end
            end
            if has_gopls then
              vim.lsp.buf.code_action({
                apply = true,
                context = { only = { "refactor.extract" } },
              })
              return ""
            end
          end

          return require("refactoring").refactor("Extract Variable")
        end,
        expr = true,
        mode = { "x" },
        desc = "Extract Variable",
      },
      {
        "<leader>ri",
        function()
          return require("refactoring").refactor("Inline Variable")
        end,
        expr = true,
        mode = { "n", "x" },
        desc = "Inline Variable",
      },
      {
        "<leader>rI",
        function()
          return require("refactoring").refactor("Inline Function")
        end,
        expr = true,
        mode = { "n", "x" },
        desc = "Inline Function",
      },
      {
        "<leader>rb",
        function()
          return require("refactoring").refactor("Extract Block")
        end,
        expr = true,
        mode = { "n" },
        desc = "Extract Block",
      },
      {
        "<leader>rB",
        function()
          return require("refactoring").refactor("Extract Block To File")
        end,
        expr = true,
        mode = { "n" },
        desc = "Extract Block To File",
      },
      {
        "<leader>rp",
        function()
          require("refactoring").debug.printf({ below = false })
        end,
        mode = { "n", "x" },
        desc = "Debug Printf",
      },
      {
        "<leader>rP",
        function()
          require("refactoring").debug.print_var({ normal = true })
        end,
        mode = { "n" },
        desc = "Debug Print Var",
      },
      {
        "<leader>rc",
        function()
          require("refactoring").debug.cleanup({})
        end,
        mode = { "n" },
        desc = "Debug Cleanup",
      },
    },
  },
}
