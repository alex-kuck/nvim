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
  -- Prefer project wrapper for consistent JVM/Gradle toolchain.
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

  -- Heuristic fallback only; neotest node resolution is still preferred first.
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

local function code_action_with_kind(kind)
  return function()
    local opts = {}
    if kind then
      opts.context = { only = { kind } }
    end
    vim.lsp.buf.code_action(opts)
  end
end

local function show_kotlin_code_action_capabilities(bufnr)
  local lines = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client.name == "kotlin_lsp" or client.name == "kotlin_language_server" then
      local provider = client.server_capabilities.codeActionProvider
      if provider == nil then
        table.insert(lines, string.format("%s: code actions not supported", client.name))
      elseif provider == true then
        table.insert(lines, string.format("%s: code actions supported (no kind list advertised)", client.name))
      elseif type(provider) == "table" then
        local kinds = provider.codeActionKinds or {}
        if #kinds == 0 then
          table.insert(lines, string.format("%s: code actions supported (empty kind list)", client.name))
        else
          table.insert(lines, string.format("%s: code action kinds: %s", client.name, table.concat(kinds, ", ")))
        end
      end
    end
  end

  if #lines == 0 then
    vim.notify("No Kotlin LSP client attached to this buffer", vim.log.levels.WARN)
    return
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Kotlin LSP Capabilities" })
end

local function escape_lua_pattern(text)
  return (text:gsub("([^%w])", "%%%1"))
end

local function find_kotlin_import_for_symbol(bufnr, symbol)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local matches = {}

  for idx, line in ipairs(lines) do
    local import_path, alias = line:match("^%s*import%s+([%w_%.`]+)%s+as%s+([%w_`]+)%s*$")
    if not import_path then
      import_path = line:match("^%s*import%s+([%w_%.`]+)%s*$")
    end

    if import_path then
      local imported_name = import_path:match("([%w_`]+)$")
      if imported_name == symbol then
        table.insert(matches, {
          line_idx = idx - 1,
          path = import_path,
          alias = alias,
        })
      end
    end
  end

  if #matches == 1 then
    return matches[1]
  end

  if #matches > 1 then
    vim.notify(
      "Multiple imports found for '" .. symbol .. "'. Place cursor on the import you want to alias.",
      vim.log.levels.WARN
    )
  end

  return nil
end

local function add_kotlin_import_alias()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "kotlin" then
    vim.notify("Add import alias is only available in Kotlin buffers", vim.log.levels.WARN)
    return
  end

  local symbol = vim.fn.expand("<cword>")
  if not symbol or symbol == "" then
    vim.notify("No symbol under cursor", vim.log.levels.WARN)
    return
  end

  local import_data = find_kotlin_import_for_symbol(bufnr, symbol)
  if not import_data then
    vim.notify(
      "No matching import found for '" .. symbol .. "'. Import the symbol first, then run alias action.",
      vim.log.levels.WARN
    )
    return
  end

  local current_name = import_data.alias or symbol
  local alias = vim.fn.input("Import alias: ", current_name)
  if not alias or alias == "" then
    return
  end

  if alias == current_name and import_data.alias then
    vim.notify("Import alias unchanged", vim.log.levels.INFO)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  lines[import_data.line_idx + 1] = string.format("import %s as %s", import_data.path, alias)

  local escaped_current = escape_lua_pattern(current_name)
  local pattern = string.format("%%f[%%w_]%s%%f[^%%w_]", escaped_current)
  local replacements = 0

  for idx, line in ipairs(lines) do
    if idx - 1 ~= import_data.line_idx and not line:match("^%s*import%s+") then
      local updated, count = line:gsub(pattern, alias)
      if count > 0 then
        lines[idx] = updated
        replacements = replacements + count
      end
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.notify(
    string.format("Aliased %s as %s and updated %d usage(s)", current_name, alias, replacements),
    vim.log.levels.INFO
  )
end

local function add_candidate_path(candidates, seen, path)
  if not path or seen[path] then
    return
  end
  if vim.uv.fs_stat(path) then
    seen[path] = true
    table.insert(candidates, path)
  end
end

local function kotlin_source_test_context(file)
  local module_root, scope, lang, rest = file:match("^(.*)/src/([^/]+)/([^/]+)/(.*)$")
  if not module_root or not scope or not lang or not rest then
    return nil
  end

  local scope_lc = scope:lower()
  local is_test_scope = scope_lc:find("test", 1, true) ~= nil

  local dir = rest:match("^(.*)/[^/]+$") or ""
  local base, ext = rest:match("([^/]+)%.([^.]+)$")
  if not base or not ext then
    return nil
  end

  return {
    module_root = module_root,
    scope = scope,
    is_test_scope = is_test_scope,
    lang = lang,
    rest = rest,
    dir = dir,
    base = base,
    ext = ext,
  }
end

local function kotlin_counterpart_names(is_test_scope, base)
  local names = {}
  local seen_names = {}

  local function add_name(name)
    if name and name ~= "" and not seen_names[name] then
      seen_names[name] = true
      table.insert(names, name)
    end
  end

  if not is_test_scope then
    for _, suffix in ipairs({ "Test", "Tests", "IT", "IntegrationTest", "Spec" }) do
      add_name(base .. suffix)
    end
  else
    add_name(base)
    for _, suffix in ipairs({ "IntegrationTest", "Tests", "Test", "IT", "Spec" }) do
      if #base > #suffix and base:sub(-#suffix) == suffix then
        add_name(base:sub(1, #base - #suffix))
      end
    end
  end

  return names
end

local function build_kotlin_alternate_candidates(file)
  local ctx = kotlin_source_test_context(file)
  if not ctx then
    return {}
  end

  local names = kotlin_counterpart_names(ctx.is_test_scope, ctx.base)
  local target_scopes = ctx.is_test_scope and { "main" } or { "test", "integrationTest", "intTest" }
  local alt_lang = ctx.lang == "kotlin" and "java" or "kotlin"
  local langs = { ctx.lang, alt_lang }
  local ext_by_lang = { kotlin = "kt", java = "java" }
  local dir_prefix = ctx.dir ~= "" and (ctx.dir .. "/") or ""

  local candidates = {}
  local seen_paths = {}

  for _, target_scope in ipairs(target_scopes) do
    for _, target_lang in ipairs(langs) do
      local target_ext = ext_by_lang[target_lang]
      for _, name in ipairs(names) do
        local exact =
          string.format("%s/src/%s/%s/%s%s.%s", ctx.module_root, target_scope, target_lang, dir_prefix, name, target_ext)
        add_candidate_path(candidates, seen_paths, exact)
      end
    end
  end

  -- Fallback for monorepos where tests are grouped in different subfolders.
  for _, target_scope in ipairs(target_scopes) do
    for _, target_lang in ipairs(langs) do
      local target_ext = ext_by_lang[target_lang]
      for _, name in ipairs(names) do
        local pattern =
          string.format("%s/src/%s/%s/**/%s.%s", ctx.module_root, target_scope, target_lang, name, target_ext)
        for _, match in ipairs(vim.fn.glob(pattern, false, true)) do
          add_candidate_path(candidates, seen_paths, match)
        end
      end
    end
  end

  table.sort(candidates)
  return candidates
end

local function default_kotlin_counterpart_path(file)
  local ctx = kotlin_source_test_context(file)
  if not ctx then
    return nil
  end

  local target_scope = ctx.is_test_scope and "main" or "test"
  local target_lang = ctx.lang
  local target_ext = target_lang == "kotlin" and "kt" or "java"
  local names = kotlin_counterpart_names(ctx.is_test_scope, ctx.base)
  local primary_name = names[1]
  if not primary_name then
    return nil
  end

  local dir_prefix = ctx.dir ~= "" and (ctx.dir .. "/") or ""
  return string.format("%s/src/%s/%s/%s%s.%s", ctx.module_root, target_scope, target_lang, dir_prefix, primary_name, target_ext)
end

local function create_kotlin_counterpart_file(current_file)
  local target_path = default_kotlin_counterpart_path(current_file)
  if not target_path then
    vim.notify("Current file is not under a supported src/<scope>/<lang> path", vim.log.levels.WARN)
    return
  end

  if vim.uv.fs_stat(target_path) then
    vim.cmd.edit(vim.fn.fnameescape(target_path))
    return
  end

  local dir = target_path:match("^(.*)/[^/]+$")
  if dir then
    vim.fn.mkdir(dir, "p")
  end

  local package_path = target_path:match("/src/[^/]+/[^/]+/(.*)/[^/]+$")
  local class_name = target_path:match("/([^/]+)%.%w+$")
  local package_name = package_path and package_path:gsub("/", ".") or nil

  local lines = {}
  if package_name and package_name ~= "" then
    table.insert(lines, "package " .. package_name)
    table.insert(lines, "")
  end
  table.insert(lines, "class " .. (class_name or "NewClass") .. " {")
  table.insert(lines, "}")

  vim.fn.writefile(lines, target_path)
  vim.cmd.edit(vim.fn.fnameescape(target_path))
  vim.notify("Created counterpart file: " .. vim.fn.fnamemodify(target_path, ":~:."), vim.log.levels.INFO)
end

local function jump_between_kotlin_source_and_test()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "kotlin" then
    vim.notify("Source/test jump is only available in Kotlin buffers", vim.log.levels.WARN)
    return
  end

  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" then
    vim.notify("Save the buffer before jumping between source and test", vim.log.levels.WARN)
    return
  end

  local matches = build_kotlin_alternate_candidates(file)
  if #matches == 0 then
    local choice = vim.fn.confirm("No corresponding source/test file found. Create one?", "&Yes\n&No", 1)
    if choice == 1 then
      create_kotlin_counterpart_file(file)
    end
    return
  end

  if #matches == 1 then
    vim.cmd.edit(vim.fn.fnameescape(matches[1]))
    return
  end

  local items = {}
  for _, path in ipairs(matches) do
    table.insert(items, {
      label = vim.fn.fnamemodify(path, ":~:."),
      path = path,
    })
  end

  vim.ui.select(items, {
    prompt = "Choose corresponding source/test file",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice and choice.path then
      vim.cmd.edit(vim.fn.fnameescape(choice.path))
    end
  end)
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
            -- Let neotest resolve the nearest node from cursor/context.
            -- Passing handcrafted IDs is fragile with nested Kotlin classes.
            if not run_kotlin_with_neotest() then
              local spec = kotlin_nearest_test_spec()
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
        "<leader>tT",
        function()
          if vim.bo.filetype == "kotlin" then
            -- neotest-kotlin does not implement directory/suite runs reliably.
            -- Use Gradle directly for "run all" semantics in Kotlin projects.
            run_gradle({ "test" }, "Spring Boot Test")
            return
          end
          open_neotest_run_ui()
          require("neotest").run.run(vim.uv.cwd())
        end,
        desc = "Run All Test Files (Neotest)",
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
          on_attach = function(_, bufnr)
            local map = function(mode, lhs, rhs, desc)
              vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
            end

            -- Kotlin-focused code action entry points for quick refactor/quickfix discovery.
            map({ "n", "x" }, "<leader>ca", code_action_with_kind(nil), "Code Action")
            map({ "n", "x" }, "<leader>cR", code_action_with_kind("refactor"), "Refactor Actions")
            map({ "n", "x" }, "<leader>cQ", code_action_with_kind("quickfix"), "Quick Fix Actions")
            map({ "n", "x" }, "<leader>cS", code_action_with_kind("source"), "Source Actions")
            -- Keep this outside <leader>ca* so it does not conflict with code-action mappings.
            map("n", "<leader>ck", add_kotlin_import_alias, "Kotlin Add Import Alias")
            -- IntelliJ-like jump between implementation and related test files.
            map("n", "<leader>ct", jump_between_kotlin_source_and_test, "Kotlin Toggle Test File")

            -- Kotlin capability probe to verify what action kinds the server advertises.
            if not vim.b[bufnr].kotlin_lsp_commands_registered then
              vim.api.nvim_buf_create_user_command(bufnr, "KotlinLspCodeActionsInfo", function()
                show_kotlin_code_action_capabilities(bufnr)
              end, {
                desc = "Show Kotlin LSP code action capabilities",
              })
              vim.api.nvim_buf_create_user_command(bufnr, "KotlinAddImportAlias", function()
                add_kotlin_import_alias()
              end, {
                desc = "Add alias to Kotlin import and rewrite file usages",
              })
              vim.api.nvim_buf_create_user_command(bufnr, "KotlinToggleTestFile", function()
                jump_between_kotlin_source_and_test()
              end, {
                desc = "Jump between Kotlin source and corresponding test files",
              })
              vim.b[bufnr].kotlin_lsp_commands_registered = true
            end

            map("n", "<leader>cI", function()
              show_kotlin_code_action_capabilities(bufnr)
            end, "Kotlin Code Action Info")
          end,
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
          -- Continuous mode supports fast edit/run loops for Spring integration checks.
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
