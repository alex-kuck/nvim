local function mason_ensure(opts, packages)
  opts.ensure_installed = opts.ensure_installed or {}
  for _, pkg in ipairs(packages) do
    if not vim.tbl_contains(opts.ensure_installed, pkg) then
      table.insert(opts.ensure_installed, pkg)
    end
  end
end

return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      mason_ensure(opts, {
        "vtsls",
        "typescript-language-server",
        "eslint-lsp",
        "eslint_d",
        "prettier",
        "js-debug-adapter",
      })
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Use per-package ESLint roots in monorepos.
        eslint = {
          settings = {
            workingDirectory = { mode = "auto" },
            format = false,
          },
        },
        -- vtsls gives better monorepo TypeScript performance than tsserver.
        vtsls = {
          settings = {
            typescript = {
              updateImportsOnFileMove = { enabled = "always" },
              inlayHints = {
                parameterNames = { enabled = "all" },
                parameterTypes = { enabled = true },
                variableTypes = { enabled = true },
                propertyDeclarationTypes = { enabled = true },
                functionLikeReturnTypes = { enabled = true },
                enumMemberValues = { enabled = true },
              },
            },
            javascript = {
              updateImportsOnFileMove = { enabled = "always" },
              inlayHints = {
                parameterNames = { enabled = "all" },
                parameterTypes = { enabled = true },
                variableTypes = { enabled = true },
                propertyDeclarationTypes = { enabled = true },
                functionLikeReturnTypes = { enabled = true },
                enumMemberValues = { enabled = true },
              },
            },
          },
        },
      },
    },
  },

  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      -- Prettier is the single formatter source for JS/TS stacks.
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.javascript = { "prettier" }
      opts.formatters_by_ft.javascriptreact = { "prettier" }
      opts.formatters_by_ft.typescript = { "prettier" }
      opts.formatters_by_ft.typescriptreact = { "prettier" }
      opts.formatters_by_ft.json = { "prettier" }
      opts.formatters_by_ft.css = { "prettier" }
      opts.formatters_by_ft.scss = { "prettier" }
      opts.formatters_by_ft.html = { "prettier" }
      opts.formatters_by_ft.markdown = { "prettier" }
      opts.formatters_by_ft.yaml = { "prettier" }
    end,
  },

  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      -- Keep diagnostics aligned with ESLint project rules.
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.javascript = { "eslint_d" }
      opts.linters_by_ft.javascriptreact = { "eslint_d" }
      opts.linters_by_ft.typescript = { "eslint_d" }
      opts.linters_by_ft.typescriptreact = { "eslint_d" }
    end,
  },

  {
    "nvim-neotest/neotest",
    optional = true,
    dependencies = {
      "marilari88/neotest-vitest",
      "nvim-neotest/neotest-jest",
    },
    opts = function(_, opts)
      opts.adapters = opts.adapters or {}
      -- Vitest first for your default stack.
      opts.adapters["neotest-vitest"] = {
        filter_dir = function(name)
          return name ~= "node_modules" and name ~= ".nx" and name ~= "dist"
        end,
      }
      opts.adapters["neotest-jest"] = {
        -- Jest stays available for older packages.
        cwd = function()
          return vim.fn.getcwd()
        end,
      }
    end,
  },

  {
    "mfussenegger/nvim-dap",
    dependencies = {
      {
        "mxsdev/nvim-dap-vscode-js",
        opts = {
          debugger_path = vim.fn.stdpath("data") .. "/mason/packages/js-debug-adapter",
          adapters = {
            "pwa-node",
            "pwa-chrome",
            "pwa-msedge",
            "node-terminal",
          },
        },
      },
    },
    opts = function()
      local dap = require("dap")
      local ok, js = pcall(require, "dap-vscode-js")
      if ok then
        js.setup({
          debugger_path = vim.fn.stdpath("data") .. "/mason/packages/js-debug-adapter",
          adapters = { "pwa-node", "pwa-chrome", "node-terminal" },
        })
      end

      local js_filetypes = { "typescript", "javascript", "typescriptreact", "javascriptreact" }
      for _, language in ipairs(js_filetypes) do
        dap.configurations[language] = {
          {
            type = "pwa-node",
            request = "launch",
            name = "Debug current file (Node)",
            program = "${file}",
            cwd = "${workspaceFolder}",
            sourceMaps = true,
          },
          {
            type = "pwa-chrome",
            request = "launch",
            name = "Launch Chrome against localhost",
            url = "http://localhost:4200",
            webRoot = "${workspaceFolder}",
          },
          {
            type = "pwa-node",
            request = "launch",
            name = "Vitest current file",
            -- Run file-focused test debug session quickly.
            cwd = "${workspaceFolder}",
            runtimeExecutable = "yarn",
            runtimeArgs = {
              "vitest",
              "run",
              "${file}",
            },
            console = "integratedTerminal",
            skipFiles = { "<node_internals>/**" },
          },
        }
      end
    end,
  },
}
