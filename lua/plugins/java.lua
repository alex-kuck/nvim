local function mason_ensure(opts, packages)
  opts.ensure_installed = opts.ensure_installed or {}
  for _, pkg in ipairs(packages) do
    if not vim.tbl_contains(opts.ensure_installed, pkg) then
      table.insert(opts.ensure_installed, pkg)
    end
  end
end

local function repo_root()
  local file = vim.api.nvim_buf_get_name(0)
  local path = file ~= "" and file or vim.fn.getcwd()
  local git_dir = vim.fs.find({ ".git" }, { upward = true, path = path })[1]
  return git_dir and vim.fs.dirname(git_dir) or vim.fn.getcwd()
end

local function service_root()
  -- Supports your repo layout: <repo>/service + <repo>/ui.
  local root = repo_root()
  local service = root .. "/service"
  if vim.uv.fs_stat(service) then
    return service
  end
  return root
end

-- Timestamp marker used to prefer fresh Gradle XML reports from the current run.
-- This avoids stale failures from prior runs leaking into neotest state.
local kotlin_last_run_start_ms = 0

local function run_gradle(args, title)
  local overseer = require("overseer")
  local root = service_root()
  local gradlew = vim.uv.fs_stat(root .. "/gradlew") and "./gradlew" or "gradle"
  overseer.new_task({
    name = title,
    cmd = vim.list_extend({ gradlew }, args),
    cwd = root,
    components = { "default" },
  }):start()
  overseer.open({ direction = "right", enter = false })
end

local function open_neotest_run_ui()
  local ok, neotest = pcall(require, "neotest")
  if ok and neotest.summary and neotest.summary.open then
    -- Keep summary visible for pass/fail tree on adapter-backed runs.
    neotest.summary.open()
  end
  local ok_overseer, overseer = pcall(require, "overseer")
  if ok_overseer then
    overseer.open({ direction = "right", enter = false })
  end
end

local function run_kotlin_with_neotest(args)
  local ok, neotest = pcall(require, "neotest")
  if not ok then
    return false
  end
  -- Record run start so report selection can ignore older files.
  kotlin_last_run_start_ms = vim.uv.now()
  open_neotest_run_ui()

  -- Prefer overseer strategy so run output is shown in Overseer windows.
  if neotest.overseer and neotest.overseer.run then
    local ran_ok = pcall(neotest.overseer.run, args)
    if ran_ok then
      return true
    end
  end

  if neotest.run and neotest.run.run then
    local ran_ok = pcall(neotest.run.run, args)
    if ran_ok then
      return true
    end
  end

  return false
end

local function has_adapter(adapters, name)
  for _, adapter in ipairs(adapters) do
    if type(adapter) == "table" and adapter.name == name then
      return true
    end
  end
  return false
end

local function patch_neotest_kotlin_report_path()
  local ok, parser = pcall(require, "neotest-kotlin.result_parsers.surefire-parser")
  if not ok or type(parser.parse_report) ~= "function" or parser._path_patch_applied then
    return
  end

  local original = parser.parse_report
  local lib = require("neotest.lib")

  local function parse_xml(path)
    local ok_read, xml = pcall(lib.files.read, path)
    if not ok_read then
      return nil
    end
    -- Strip UTF-8 BOM when present.
    if xml:byte(1) == 239 and xml:byte(2) == 187 and xml:byte(3) == 191 then
      xml = xml:sub(4)
    end
    local ok_parse, parsed = pcall(lib.xml.parse, xml)
    if ok_parse then
      return parsed
    end
    return nil
  end

  local function collect_candidates(output_file)
    local dir = output_file:match("^(.*)/[^/]+$")
    local filename = output_file:match("([^/]+)$")
    if not dir or not filename then
      return {}
    end

    local class_base = filename:match("^TEST%-(.+)%.xml$")
    if not class_base then
      return {}
    end

    -- Gradle often writes nested test suite reports as TEST-<Class>$<Nested>.xml.
    local pattern = dir .. "/TEST-" .. class_base .. "*.xml"
    local files = vim.fn.glob(pattern, false, true)
    -- Filter candidates to files touched during the current run first.
    local recent = {}
    for _, file in ipairs(files) do
      local stat = vim.uv.fs_stat(file)
      local mtime_ms = stat and stat.mtime and (stat.mtime.sec * 1000 + math.floor((stat.mtime.nsec or 0) / 1000000)) or 0
      if kotlin_last_run_start_ms == 0 or mtime_ms >= (kotlin_last_run_start_ms - 2000) then
        table.insert(recent, file)
      end
    end
    files = (#recent > 0) and recent or files
    table.sort(files)
    return files
  end

  local function merge_reports(files)
    local merged = { testsuite = { testcase = {} } }
    for _, file in ipairs(files) do
      local parsed = parse_xml(file)
      local testcase = parsed and parsed.testsuite and parsed.testsuite.testcase
      if testcase then
        if testcase[1] ~= nil then
          for _, tc in ipairs(testcase) do
            table.insert(merged.testsuite.testcase, tc)
          end
        else
          table.insert(merged.testsuite.testcase, testcase)
        end
      end
    end
    if #merged.testsuite.testcase > 0 then
      return merged
    end
    return nil
  end

  parser.parse_report = function(output_file)
    -- Upstream adapter currently builds gradle report path as .../testTEST-*.xml.
    if output_file and vim.uv.fs_stat(output_file) == nil then
      local fixed = output_file:gsub("/build/test%-results/testTEST%-", "/build/test-results/test/TEST-")
      if fixed ~= output_file then
        output_file = fixed
      end

      -- If exact report does not exist, merge nested suite reports.
      -- Spring/Kotlin nested classes often emit TEST-<Class>$<Nested>.xml files.
      if vim.uv.fs_stat(output_file) == nil then
        local candidates = collect_candidates(output_file)
        local merged = merge_reports(candidates)
        if merged then
          return merged
        end
      end
    end
    return original(output_file)
  end

  local function normalize_name(name)
    if not name then
      return nil
    end
    return name:gsub("^%s*`", ""):gsub("`%s*$", ""):gsub("%s+", " "):gsub("%(%)$", "")
  end

  parser.convert_intermediate_results = function(intermediate_results, test_nodes)
    -- Upstream matching is substring-based and can over-match, marking unrelated
    -- tests as failed. Match by normalized test name to keep per-test status precise.
    local by_name = {}
    for _, res in ipairs(intermediate_results or {}) do
      local key = normalize_name(res.test_name)
      if key then
        by_name[key] = res
      end
    end

    local neotest_results = {}
    for _, node in ipairs(test_nodes or {}) do
      local node_data = node:data()
      local key = normalize_name(node_data.name)
      local result = by_name[key] or by_name[key .. "()"]
      if result then
        neotest_results[node_data.id] = {
          status = result.status,
          short = node_data.name .. ":" .. result.status,
          errors = {},
        }
        if result.error_info then
          table.insert(neotest_results[node_data.id].errors, { message = result.error_info })
        end
      end
    end
    return neotest_results
  end

  parser._path_patch_applied = true
end

local function java_or_gradle(java_cmd, gradle_args, title)
  -- Java buffer => use nvim-java command.
  -- Kotlin/Spring buffer => fallback to Gradle so workflows still work.
  if vim.bo.filetype == "java" then
    vim.cmd(java_cmd)
    return
  end
  run_gradle(gradle_args, title)
end

local function kotlin_nearest_test_spec()
  if vim.bo.filetype ~= "kotlin" then
    return nil
  end
  local file = vim.fn.expand("%:p")
  if file == "" then
    return nil
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local buf = vim.api.nvim_get_current_buf()
  local class_name
  local method_name

  for lnum = row, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
    if not class_name then
      class_name = line:match("^%s*class%s+([%w_]+)")
    end
    if not method_name then
      method_name = line:match('^%s*fun%s+([%w_]+)%s*%(')
      if not method_name then
        method_name = line:match('^%s*fun%s+`([^`]+)`%s*%(')
      end
    end
    if class_name and method_name then
      break
    end
  end

  if class_name and method_name then
    return file .. "::" .. class_name .. "::" .. method_name
  end
  return file
end

return {
  {
    "mfussenegger/nvim-jdtls",
    enabled = false,
  },

  {
    -- Kotlin tests are handled via Gradle because dedicated adapter support is still limited.
    "nvim-neotest/neotest",
    optional = true,
    dependencies = {
      "Mgenuit/neotest-kotlin",
      "stevearc/overseer.nvim",
    },
    opts = function(_, opts)
      opts.consumers = opts.consumers or {}
      opts.consumers.overseer = require("neotest.consumers.overseer")
      opts.overseer = vim.tbl_deep_extend("force", opts.overseer or {}, {
        enabled = true,
        force_default = true,
      })

      opts.adapters = opts.adapters or {}
      -- LazyVim expects keyed adapters to be setup tables, not adapter instances.
      -- Add Kotlin adapter as a list entry to avoid setup() errors.
      local kotlin_adapter = require("neotest-kotlin").Adapter
      if not has_adapter(opts.adapters, kotlin_adapter.name) then
        table.insert(opts.adapters, kotlin_adapter)
      end

      patch_neotest_kotlin_report_path()
    end,
    keys = {
      {
        "<leader>tt",
        function()
          if vim.bo.filetype == "kotlin" then
            if not run_kotlin_with_neotest(vim.fn.expand("%:p")) then
              run_gradle({ "test" }, "Spring Boot Test")
            end
            return
          end
          open_neotest_run_ui()
          require("neotest").run.run(vim.fn.expand("%:p"))
        end,
        desc = "Run File (Neotest)",
      },
      {
        "<leader>tr",
        function()
          if vim.bo.filetype == "kotlin" then
            local spec = kotlin_nearest_test_spec()
            if not run_kotlin_with_neotest(spec) then
              if spec then
                run_gradle({ "test", "--tests", spec }, "Spring Boot Test")
                return
              end
              run_gradle({ "test" }, "Spring Boot Test")
            end
            return
          end
          open_neotest_run_ui()
          require("neotest").run.run()
        end,
        desc = "Run Nearest (Neotest)",
      },
      {
        "<leader>td",
        function()
          if vim.bo.filetype == "kotlin" then
            local spec = kotlin_nearest_test_spec()
            if spec then
              run_gradle({ "test", "--debug-jvm", "--tests", spec }, "Spring Boot Debug Tests")
              return
            end
            run_gradle({ "test", "--debug-jvm" }, "Spring Boot Debug Tests")
            return
          end
          open_neotest_run_ui()
          require("neotest").run.run({ strategy = "dap" })
        end,
        desc = "Debug Nearest (Neotest)",
      },
    },
  },

  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      -- Install Java/Kotlin toolchain pieces once; Mason keeps them updated.
      mason_ensure(opts, {
        "jdtls",
        "java-debug-adapter",
        "java-test",
        "google-java-format",
        -- JetBrains kotlin-lsp tracks modern Kotlin metadata versions better.
        "kotlin-lsp",
        "ktlint",
      })
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Disable fwcd server: it often lags Kotlin metadata compatibility.
        kotlin_language_server = false,
        -- Kotlin LSP for controllers/services when editing under /service.
        kotlin_lsp = {
          -- Keep root detection Gradle-first so /ui is not indexed with /service.
          root_markers = {
            "settings.gradle.kts",
            "settings.gradle",
            "build.gradle.kts",
            "build.gradle",
            "gradle.properties",
            ".git",
          },
          single_file_support = false,
          settings = {
            kotlin = {
              inlayHints = {
                typeHints = true,
                parameterHints = true,
              },
            },
          },
        },
      },
    },
  },

  {
    -- Kotlin formatting so Spring Kotlin files feel IDE-like.
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.kotlin = { "ktlint" }
    end,
  },

  {
    "nvim-java/nvim-java",
    -- Restrict to Java buffers; loading this on Kotlin adds startup overhead.
    ft = { "java" },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "mfussenegger/nvim-dap",
      "MunifTanjim/nui.nvim",
    },
    init = function()
      -- JDTLS tuning for IntelliJ-like navigation and code lenses.
      vim.lsp.config("jdtls", {
        settings = {
          java = {
            configuration = {
              updateBuildConfiguration = "interactive",
              runtimes = {
                {
                  name = "JavaSE-21",
                  default = true,
                },
              },
            },
            eclipse = {
              downloadSources = true,
            },
            references = {
              includeDecompiledSources = true,
            },
            implementationsCodeLens = {
              enabled = true,
            },
            referencesCodeLens = {
              enabled = true,
            },
            inlayHints = {
              parameterNames = {
                enabled = "all",
              },
            },
            format = {
              enabled = true,
            },
          },
        },
      })
    end,
    config = function()
      -- nvim-java orchestrates jdtls + java-test + debug adapter.
      require("java").setup({
        jdk = {
          auto_install = true,
          version = "21",
        },
        spring_boot_tools = {
          enable = true,
        },
      })
      vim.lsp.enable("jdtls")
    end,
    keys = {
      {
        "<leader>jR",
        function()
          java_or_gradle("JavaRunnerRunMain", { "bootRun" }, "Spring Boot Run")
        end,
        desc = "Java/Spring Run Main",
      },
      {
        "<leader>jS",
        function()
          if vim.bo.filetype == "java" then
            vim.cmd("JavaRunnerStopMain")
            return
          end
          vim.notify("Stop task from Overseer list (<leader>ot)", vim.log.levels.INFO)
        end,
        desc = "Java Runner Stop",
      },
      {
        "<leader>jL",
        function()
          if vim.bo.filetype == "java" then
            vim.cmd("JavaRunnerToggleLogs")
            return
          end
          vim.cmd("OverseerToggle")
        end,
        desc = "Java/Spring Logs",
      },
      {
        -- Custom Spring task for local test profile execution.
        "<leader>jl",
        function()
          run_gradle({ "bootTestRun", "--continuous" }, "Spring Boot Test Run")
        end,
        desc = "Spring Boot Test Run",
      },
      {
        "<leader>jt",
        function()
          java_or_gradle("JavaTestRunCurrentMethod", { "test" }, "Spring Boot Test")
        end,
        desc = "Java Test Method",
      },
      {
        "<leader>jT",
        function()
          java_or_gradle("JavaTestRunCurrentClass", { "test" }, "Spring Boot Test")
        end,
        desc = "Java Test Class",
      },
      {
        "<leader>jd",
        function()
          java_or_gradle("JavaTestDebugCurrentMethod", { "test", "--debug-jvm" }, "Spring Boot Debug Tests")
        end,
        desc = "Java Debug Method",
      },
      {
        "<leader>jD",
        function()
          java_or_gradle("JavaTestDebugCurrentClass", { "test", "--debug-jvm" }, "Spring Boot Debug Tests")
        end,
        desc = "Java Debug Class",
      },
      {
        "<leader>jp",
        "<cmd>JavaProfile<cr>",
        desc = "Java Profiles",
        ft = "java",
      },
      {
        "<leader>jb",
        function()
          java_or_gradle("JavaBuildBuildWorkspace", { "build" }, "Spring Boot Build")
        end,
        desc = "Java Build Workspace",
      },
      {
        "<leader>jc",
        function()
          java_or_gradle("JavaBuildCleanWorkspace", { "clean" }, "Spring Boot Clean")
        end,
        desc = "Java Clean Workspace",
      },
      {
        "<leader>jr",
        "<cmd>JavaSettingsChangeRuntime<cr>",
        desc = "Java Change Runtime",
        ft = { "java", "kotlin" },
      },
    },
  },
}
