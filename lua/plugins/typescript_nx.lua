local function mason_ensure(opts, packages)
  opts.ensure_installed = opts.ensure_installed or {}
  for _, pkg in ipairs(packages) do
    if not vim.tbl_contains(opts.ensure_installed, pkg) then
      table.insert(opts.ensure_installed, pkg)
    end
  end
end

local function is_ts_like_buffer()
  local ft = vim.bo.filetype
  return ft == "typescript" or ft == "typescriptreact" or ft == "javascript" or ft == "javascriptreact"
end

local function path_exists(path)
  return path and vim.uv.fs_stat(path) ~= nil
end

local function repo_root(path)
  local git = vim.fs.find({ ".git" }, { upward = true, path = path })[1]
  return git and vim.fs.dirname(git) or vim.fn.getcwd()
end

local function nx_ui_root(path)
  -- Standard repo layout is <repo>/ui + <repo>/service; prefer /ui for TS tools.
  local root = repo_root(path)
  local ui = root .. "/ui"
  if path_exists(ui) and path_exists(ui .. "/nx.json") then
    return ui
  end
  local nx = vim.fs.find({ "nx.json" }, { upward = true, path = path })[1]
  return nx and vim.fs.dirname(nx) or root
end

local function package_has_dep(package_json_path, names)
  -- Adapter checks should be package-local to avoid noisy monorepo false positives.
  local ok_read, content = pcall(require("neotest.lib").files.read, package_json_path)
  if not ok_read then
    return false
  end
  local ok_json, pkg = pcall(vim.json.decode, content)
  if not ok_json or type(pkg) ~= "table" then
    return false
  end
  for _, field in ipairs({ "dependencies", "devDependencies" }) do
    local deps = pkg[field]
    if type(deps) == "table" then
      for _, dep in ipairs(names) do
        if deps[dep] then
          return true
        end
      end
    end
  end
  return false
end

local function open_neotest_summary(file_path)
  local ok, neotest = pcall(require, "neotest")
  if ok and neotest.summary and neotest.summary.open then
    neotest.summary.open()
    -- Expand current file to make test cases visible immediately in summary.
    if file_path and neotest.summary.expand then
      pcall(neotest.summary.expand, neotest.summary, file_path, true)
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
      opts.summary = vim.tbl_deep_extend("force", opts.summary or {}, {
        -- Match Kotlin/Go experience: visible counters + failing branch expansion.
        count = true,
        expand_errors = true,
      })

      opts.adapters = opts.adapters or {}

      -- Custom adapter objects avoid noisy root package.json checks when Neovim
      -- starts at monorepo root (without a package.json next to init cwd).
      local vitest = require("neotest-vitest")({
        cwd = function(path)
          return nx_ui_root(path or vim.api.nvim_buf_get_name(0))
        end,
        filter_dir = function(name)
          return name ~= "node_modules" and name ~= ".nx" and name ~= "dist"
        end,
      })
      vitest.is_test_file = function(file_path)
        -- Restrict discovery to actual test files with local Vitest dependency.
        if not file_path then
          return false
        end
        local is_test = file_path:match("__tests__")
          or file_path:match("%.spec%.[jt]sx?$")
          or file_path:match("%.test%.[jt]sx?$")
          or file_path:match("%.e2e%.[jt]sx?$")
        if not is_test then
          return false
        end
        local pkg_root = require("neotest.lib").files.match_root_pattern("package.json")(file_path)
        if not pkg_root then
          return false
        end
        return package_has_dep(pkg_root .. "/package.json", { "vitest", "@vitest/ui", "@vitest/coverage-v8" })
      end

      local jest = require("neotest-jest")({
        cwd = function(path)
          return nx_ui_root(path or vim.api.nvim_buf_get_name(0))
        end,
      })
      jest.is_test_file = function(file_path)
        -- Restrict discovery to Jest packages so summary trees stay accurate.
        if not file_path then
          return false
        end
        local is_test = file_path:match("__tests__")
          or file_path:match("%.spec%.[jt]sx?$")
          or file_path:match("%.test%.[jt]sx?$")
        if not is_test then
          return false
        end
        local pkg_root = require("neotest.lib").files.match_root_pattern("package.json")(file_path)
        if not pkg_root then
          return false
        end
        return package_has_dep(pkg_root .. "/package.json", { "jest" })
      end

      opts.adapters["neotest-vitest"] = nil
      opts.adapters["neotest-jest"] = nil
      table.insert(opts.adapters, vitest)
      table.insert(opts.adapters, jest)
    end,
    keys = {
      {
        "<leader>tt",
        function()
          local file = vim.fn.expand("%:p")
          if is_ts_like_buffer() then
            open_neotest_summary(file)
          end
          require("neotest").run.run(file)
        end,
        ft = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
        desc = "Run File (Neotest)",
      },
      {
        "<leader>tr",
        function()
          local file = vim.fn.expand("%:p")
          if is_ts_like_buffer() then
            open_neotest_summary(file)
          end
          local ok = pcall(require("neotest").run.run)
          if not ok then
            require("neotest").run.run(file)
          end
        end,
        ft = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
        desc = "Run Nearest (Neotest)",
      },
      {
        "<leader>tT",
        function()
          local file = vim.fn.expand("%:p")
          local root = nx_ui_root(file)
          if is_ts_like_buffer() then
            open_neotest_summary(file)
          end
          require("neotest").run.run(root)
        end,
        ft = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
        desc = "Run All Test Files (Neotest)",
      },
      {
        "<leader>ts",
        function()
          require("neotest").summary.toggle()
        end,
        ft = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
        desc = "Toggle Summary (Neotest)",
      },
    },
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
