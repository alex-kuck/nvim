-- Returns true only for real Go test buffers (used by smart test runners).
local function is_go_test_buffer()
  local filepath = vim.api.nvim_buf_get_name(0)
  return vim.bo.filetype == "go" and filepath ~= "" and vim.endswith(filepath, "_test.go")
end

-- Walks upward from the cursor to find the surrounding `func Test...` /
-- `func Example...` declaration. This lets us run one test when nearest test
-- discovery fails but we are clearly inside a test function.
local function current_go_test_name()
  if not is_go_test_buffer() then
    return nil
  end

  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  for lnum = row, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
    local name = line:match("^%s*func%s+([%w_]+)%s*%(")
    if name then
      if vim.startswith(name, "Test") or vim.startswith(name, "Example") then
        return name
      end
      return nil
    end
  end

  return nil
end

-- Smart Go runner used by both custom (<leader>G*) and default-like
-- (<leader>t*) keymaps:
-- - non-Go buffers: fall back to plain neotest behavior
-- - Go test buffers: run the file and, when possible, narrow to one test
--   with `-run ^TestName$`
-- This keeps execution reliable even when nearest-position detection is flaky.
local function run_go_smart(opts)
  local neotest = require("neotest")
  opts = opts or {}

  if not is_go_test_buffer() then
    if next(opts) == nil then
      neotest.run.run()
    else
      neotest.run.run(opts)
    end
    return
  end

  local file = vim.fn.expand("%:p")
  local test_name = current_go_test_name()
  local args = { file }
  if test_name then
    args.extra_args = { "-run", "^" .. vim.pesc(test_name) .. "$" }
  end

  args = vim.tbl_extend("force", args, opts)
  neotest.run.run(args)
end

-- Explicitly run all tests in the current Go test file.
local function run_go_file()
  require("neotest").run.run(vim.fn.expand("%:p"))
end

-- Always show output from the latest run. Using `last_run` avoids cursor/
-- nearest-position ambiguity and works well with smart run fallbacks.
local function open_last_output()
  require("neotest").output.open({ enter = true, auto_close = true, last_run = true })
end

-- Small UX helper so it is obvious whether one test or a whole file is run.
local function notify_nearest_info()
  if not is_go_test_buffer() then
    return
  end
  local test_name = current_go_test_name()
  if test_name then
    vim.notify("Running test: " .. test_name, vim.log.levels.INFO, { title = "Go Neotest" })
  else
    vim.notify("Running current test file", vim.log.levels.INFO, { title = "Go Neotest" })
  end
end

return {
  -- Ensure core Go tools are installed and managed via Mason.
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "gopls",
        "delve",
        "goimports",
        "gofumpt",
        "golangci-lint",
      })
    end,
  },

  -- gopls tuning to mirror more IDE-like Go behavior.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        gopls = {
          settings = {
            gopls = {
              gofumpt = true,
              staticcheck = true,
              usePlaceholders = true,
              hints = {
                assignVariableTypes = true,
                compositeLiteralFields = true,
                compositeLiteralTypes = true,
                constantValues = true,
                functionTypeParameters = true,
                parameterNames = true,
                rangeVariableTypes = true,
              },
              codelenses = {
                gc_details = false,
                generate = true,
                regenerate_cgo = true,
                run_govulncheck = true,
                test = true,
                tidy = true,
                upgrade_dependency = true,
                vendor = true,
              },
              analyses = {
                fieldalignment = true,
                nilness = true,
                shadow = true,
                unusedparams = true,
                unusedwrite = true,
                useany = true,
              },
            },
          },
        },
      },
      setup = {
        -- Enable inlay hints only when gopls is attached.
        gopls = function(_, _)
          Snacks.util.lsp.on({ name = "gopls" }, function(buffer, _)
            vim.lsp.inlay_hint.enable(true, { bufnr = buffer })
          end)
          return false
        end,
      },
    },
  },

  -- Format Go with import organization first, then style normalization.
  {
    "stevearc/conform.nvim",
    opts = {
      async = true,
      lsp_fallback = true,
      formatters_by_ft = {
        go = { "goimports", "gofumpt" },
      },
    },
  },

  -- IDE-like diagnostics from golangci-lint inside Neovim.
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        go = { "golangcilint" },
      },
    },
  },

  -- Delve-powered debugging for Go tests.
  {
    "leoluz/nvim-dap-go",
    ft = "go",
    dependencies = {
      "mfussenegger/nvim-dap",
    },
    config = function()
      require("dap-go").setup()
    end,
    keys = {
      {
        "<leader>dgt",
        function()
          require("dap-go").debug_test()
        end,
        desc = "Debug Go Test",
      },
      {
        "<leader>dgT",
        function()
          require("dap-go").debug_last_test()
        end,
        desc = "Debug Last Go Test",
      },
    },
  },

  -- Neotest core + Go adapter and Go-specific behavior overrides.
  {
    "nvim-neotest/neotest",
    optional = true,
    dependencies = {
      "fredrikaverpil/neotest-golang",
    },
    opts = {
      adapters = {
        -- neotest-golang is currently more stable than neotest-go in this setup.
        ["neotest-golang"] = {
          go_test_args = { "-v" },
          dap_go_enabled = true,
        },
      },
      summary = {
        -- Show per-adapter test counts and expand failures for quick triage.
        count = true,
        expand_errors = true,
      },
    },
    init = function()
      -- Diagnostic helper for adapter/root/position state while troubleshooting.
      vim.api.nvim_create_user_command("GoNeotestDebugInfo", function()
        local buf = vim.api.nvim_get_current_buf()
        local filepath = vim.api.nvim_buf_get_name(0)
        local row = vim.api.nvim_win_get_cursor(0)[1] - 1

        local ok, neotest = pcall(require, "neotest")
        if not ok then
          vim.notify("neotest is not available", vim.log.levels.ERROR)
          return
        end

        local nio = require("nio")
        nio.run(function()
          local adapters = neotest.state.adapter_ids()
          local lines = {
            "[GoNeotestDebugInfo]",
            "cwd=" .. vim.loop.cwd(),
            "file=" .. filepath,
            "row=" .. tostring(row + 1),
            "adapters=" .. vim.inspect(adapters),
          }

          for _, adapter_id in ipairs(adapters) do
            local root_tree = neotest.state.positions(adapter_id)
            local file_tree = neotest.state.positions(adapter_id, { buffer = buf })
            local nearest_tree = neotest.run.get_tree_from_args({ adapter = adapter_id }, false)

            table.insert(lines, "adapter=" .. adapter_id)
            table.insert(lines, "  root_tree=" .. tostring(root_tree and root_tree:data().id or nil))
            table.insert(lines, "  file_tree=" .. tostring(file_tree and file_tree:data().id or nil))
            table.insert(lines, "  nearest_tree=" .. tostring(nearest_tree and nearest_tree:data().id or nil))
          end

          vim.schedule(function()
            vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Go Neotest" })
          end)
        end)
      end, { desc = "Print Neotest state for current Go file" })

      -- Manual refresh hook for stale discovery state in the current file.
      vim.api.nvim_create_user_command("GoNeotestRefreshFile", function()
        if vim.bo.filetype ~= "go" then
          vim.notify("current buffer is not a Go file", vim.log.levels.WARN)
          return
        end

        vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0, modeline = false })
        vim.api.nvim_exec_autocmds("BufWritePost", { buffer = 0, modeline = false })
        vim.notify("triggered Neotest discovery autocmds for current file", vim.log.levels.INFO)
      end, { desc = "Force refresh Neotest positions for current file" })
    end,
    keys = {
      -- Go-focused aliases under <leader>G.
      {
        "<leader>Gt",
        function()
          notify_nearest_info()
          run_go_smart()
        end,
        desc = "Run Smart Test",
      },
      {
        "<leader>GT",
        run_go_file,
        desc = "Run Test File",
      },
      {
        "<leader>Gd",
        function()
          notify_nearest_info()
          run_go_smart({ strategy = "dap" })
        end,
        desc = "Debug Smart Test",
      },
      {
        "<leader>Go",
        function()
          open_last_output()
        end,
        desc = "Open Last Test Output",
      },
      {
        "<leader>Gs",
        function()
          require("neotest").summary.toggle()
        end,
        desc = "Toggle Test Summary",
      },

      -- Override default-like neotest mappings with Go-smart behavior.
      {
        "<leader>tt",
        run_go_file,
        desc = "Run File (Neotest)",
      },
      {
        "<leader>tT",
        function()
          require("neotest").run.run(vim.uv.cwd())
        end,
        desc = "Run All Test Files (Neotest)",
      },
      {
        "<leader>tr",
        function()
          notify_nearest_info()
          run_go_smart()
        end,
        desc = "Run Smart Nearest (Neotest)",
      },
      {
        "<leader>td",
        function()
          notify_nearest_info()
          run_go_smart({ strategy = "dap" })
        end,
        desc = "Debug Smart Test (Neotest)",
      },
      {
        "<leader>to",
        open_last_output,
        desc = "Show Last Output (Neotest)",
      },
      {
        "<leader>ts",
        function()
          require("neotest").summary.toggle()
        end,
        desc = "Toggle Summary (Neotest)",
      },
    },
  },

  -- Common Go code generation helpers (tags/tests).
  {
    "olexsmir/gopher.nvim",
    ft = "go",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    opts = { timeout = 120000 },
    keys = {
      {
        "<leader>Gcj",
        "<cmd>GoTagAdd json<cr>",
        desc = "Add JSON Tags",
      },
      {
        "<leader>Gcy",
        "<cmd>GoTagAdd yaml<cr>",
        desc = "Add YAML Tags",
      },
      {
        "<leader>Gcr",
        "<cmd>GoTagRm<cr>",
        desc = "Remove Struct Tags",
      },
      {
        "<leader>Gct",
        "<cmd>GoTestAdd<cr>",
        desc = "Generate Tests",
      },
    },
  },

  -- Generate interface implementations quickly.
  {
    "fang2hou/go-impl.nvim",
    ft = "go",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
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
  },
}
