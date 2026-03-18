local function path_exists(path)
  return path and vim.uv.fs_stat(path) ~= nil
end

local function path_join(...)
  return table.concat({ ... }, "/")
end

local function current_path()
  local file = vim.api.nvim_buf_get_name(0)
  if file ~= "" then
    return file
  end
  return vim.fn.getcwd()
end

local function project_root(markers)
  local found = vim.fs.find(markers, { upward = true, path = current_path() })[1]
  return found and vim.fs.dirname(found) or nil
end

local function service_root()
  -- Prefer <repo>/service when it exists so run/test works from repo root.
  local repo = project_root({ ".git" }) or vim.fn.getcwd()
  local service = path_join(repo, "service")
  if path_exists(service) then
    local found = vim.fs.find(
      { "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts" },
      { upward = true, path = service }
    )[1]
    if found then
      return vim.fs.dirname(found)
    end
  end

  return project_root({ "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts" })
end

local function gradle_cmd(root)
  -- Wrapper in repo is preferred; fallback to system gradle if needed.
  return path_exists(path_join(root, "gradlew")) and "./gradlew" or "gradle"
end

local function ui_root()
  -- Prefer <repo>/ui for your monorepo layout; fallback to nearest nx root.
  local repo = project_root({ ".git" }) or vim.fn.getcwd()
  local ui = path_join(repo, "ui")
  if path_exists(ui) and path_exists(path_join(ui, "nx.json")) then
    return ui
  end

  local found = vim.fs.find({ "nx.json" }, { upward = true, path = current_path() })[1]
  return found and vim.fs.dirname(found) or nil
end

local function decode_json(file)
  if not path_exists(file) then
    return nil
  end
  local ok_read, lines = pcall(vim.fn.readfile, file)
  if not ok_read then
    return nil
  end
  local ok_json, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if ok_json then
    return data
  end
  return nil
end

local function nx_target_from_context(root)
  if not root then
    return "app"
  end

  -- If we're editing inside an Nx project folder, use that exact project name.
  local file = vim.api.nvim_buf_get_name(0)
  if file ~= "" and vim.startswith(file, root .. "/") then
    local project_file = vim.fs.find({ "project.json" }, { upward = true, path = file, stop = root })[1]
    local project_data = project_file and decode_json(project_file) or nil
    if project_data and type(project_data.name) == "string" and project_data.name ~= "" then
      return project_data.name
    end

    local rel = file:sub(#root + 2)
    local app = rel:match("^apps/([^/]+)/")
    if app then
      return app
    end
    local lib = rel:match("^libs/([^/]+)/")
    if lib then
      return lib
    end
  end

  local cwd = vim.fn.getcwd()
  if vim.startswith(cwd, root .. "/") then
    local rel_cwd = cwd:sub(#root + 2)
    local app = rel_cwd:match("^apps/([^/]+)/")
    if app then
      return app
    end
    local lib = rel_cwd:match("^libs/([^/]+)/")
    if lib then
      return lib
    end
  end

  return "app"
end

local function nx_projects(root)
  -- Collect project names from project.json files in the Nx workspace.
  local projects = {}
  local seen = {}
  local files = vim.fs.find({ "project.json" }, { path = root, type = "file", limit = math.huge })
  for _, file in ipairs(files) do
    local data = decode_json(file)
    local name = data and data.name
    if type(name) == "string" and name ~= "" and not seen[name] then
      seen[name] = true
      table.insert(projects, name)
    end
  end
  table.sort(projects)
  return projects
end

local function pick_nx_target(root, on_pick)
  local items = nx_projects(root)
  if #items == 0 then
    vim.notify("No Nx projects discovered from project.json", vim.log.levels.WARN)
    return
  end
  vim.ui.select(items, { prompt = "Nx target:" }, function(choice)
    if choice then
      on_pick(choice)
    end
  end)
end

local function run_nx_task(task_name, nx_action, force_pick)
  local overseer = require("overseer")
  local root = ui_root()
  if not root then
    vim.notify("No Nx root found", vim.log.levels.WARN)
    return
  end

  local function start_with(target)
    -- Keep Nx runs rooted in /ui even when Neovim starts at repo root.
    overseer.new_task({
      name = task_name,
      cmd = { "yarn", "nx", nx_action, target },
      cwd = root,
      components = { "default" },
    }):start()
  end

  if force_pick then
    pick_nx_target(root, start_with)
    return
  end

  local target = nx_target_from_context(root)
  if target == "app" then
    -- "app" is the fallback when no project context is detected.
    pick_nx_target(root, start_with)
    return
  end
  start_with(target)
end

local function stop_all_spring_tasks()
  -- Stops running Spring/Gradle tasks started from this workspace.
  local overseer = require("overseer")
  local root = service_root() or vim.fn.getcwd()
  local stopped = 0

  for _, task in ipairs(overseer.list_tasks({})) do
    local is_running = task:is_running()
    local cwd = task.cwd
    local name = task.name or ""
    if is_running and cwd == root and name:match("^Spring Boot") then
      task:stop(true)
      stopped = stopped + 1
    end
  end

  if stopped == 0 then
    vim.notify("No running Spring tasks found", vim.log.levels.INFO)
    return
  end
  vim.notify("Stopped " .. stopped .. " Spring task(s)", vim.log.levels.INFO)
end

local function run_spring_task(task_name, gradle_args)
  local overseer = require("overseer")
  local root = service_root()
  if not root then
    vim.notify("No Gradle root found", vim.log.levels.WARN)
    return
  end
  overseer.new_task({
    name = task_name,
    cmd = vim.list_extend({ gradle_cmd(root) }, gradle_args),
    cwd = root,
    components = {
      -- IntelliJ-like run window behavior for Spring task execution.
      { "open_output", direction = "horizontal", focus = false, on_start = "always" },
      "default",
    },
  }):start()

  -- Keep task tree visible while running Spring commands.
  overseer.open({ direction = "right", enter = false })
end

local function run_custom_gradle(input)
  local overseer = require("overseer")
  local root = service_root()
  if not root then
    vim.notify("No Gradle root found", vim.log.levels.WARN)
    return
  end
  local args = vim.trim(input or "")
  if args == "" then
    return
  end
  overseer.new_task({
    name = "Gradle: " .. args,
    -- Use string command so ad-hoc flags/quoting work without extra parsing.
    cmd = gradle_cmd(root) .. " " .. args,
    cwd = root,
    components = { "default" },
  }):start()
end

local function prompt_custom_gradle()
  vim.ui.input({ prompt = "Gradle args (e.g. detekt --auto-correct): " }, function(input)
    run_custom_gradle(input)
  end)
end

local function register_spring_commands()
  -- Keep Spring entrypoints available as Ex commands in any buffer.
  local commands = {
    SpringBootRun = function()
      run_spring_task("Spring Boot Run", { "bootRun", "--continuous" })
    end,
    SpringBootTest = function()
      run_spring_task("Spring Boot Test", { "test" })
    end,
    SpringBootTestRun = function()
      run_spring_task("Spring Boot Test Run", { "bootTestRun", "--continuous" })
    end,
    SpringBootStopAll = stop_all_spring_tasks,
    SpringGradle = function(opts)
      run_custom_gradle(opts.args)
    end,
  }

  for name, fn in pairs(commands) do
    if vim.fn.exists(":" .. name) == 0 then
      local cmd_opts = { desc = name }
      if name == "SpringGradle" then
        cmd_opts.nargs = "*"
      end
      vim.api.nvim_create_user_command(name, fn, cmd_opts)
    end
  end
end

return {
  {
    "stevearc/overseer.nvim",
    cmd = { "OverseerRun", "OverseerToggle", "OverseerQuickAction", "OverseerTaskAction" },
    keys = {
      {
        "<leader>or",
        "<cmd>OverseerRun<cr>",
        desc = "Task Run",
      },
      {
        "<leader>ot",
        "<cmd>OverseerToggle<cr>",
        desc = "Task Toggle",
      },
      {
        "<leader>oa",
        "<cmd>OverseerTaskAction<cr>",
        desc = "Task Action",
      },
      {
        "<leader>ol",
        "<cmd>OverseerQuickAction restart<cr>",
        desc = "Task Restart Last",
      },
      {
        "<leader>sb",
        function()
          -- Continuous mode mirrors IDE-like auto-rebuild/restart workflow.
          run_spring_task("Spring Boot Run", { "bootRun", "--continuous" })
        end,
        desc = "Spring Boot Run",
      },
      {
        "<leader>sB",
        function()
          run_spring_task("Spring Boot Test", { "test" })
        end,
        desc = "Spring Boot Test",
      },
      {
        "<leader>sl",
        function()
          run_spring_task("Spring Boot Test Run", { "bootTestRun", "--continuous" })
        end,
        desc = "Spring Boot Test Run",
      },
      {
        "<leader>sx",
        stop_all_spring_tasks,
        desc = "Spring Stop All Tasks",
      },
      {
        "<leader>sg",
        prompt_custom_gradle,
        desc = "Spring Gradle Prompt",
      },
      {
        -- Kotlin fallback for Java-style Spring keymaps.
        "<leader>jR",
        function()
          run_spring_task("Spring Boot Run", { "bootRun", "--continuous" })
        end,
        desc = "Spring Run Main",
      },
      {
        "<leader>jl",
        function()
          run_spring_task("Spring Boot Test Run", { "bootTestRun", "--continuous" })
        end,
        desc = "Spring Boot Test Run",
      },
      {
        "<leader>jt",
        function()
          run_spring_task("Spring Boot Test", { "test" })
        end,
        desc = "Spring Test",
      },
      {
        "<leader>jb",
        function()
          run_spring_task("Spring Boot Build", { "build" })
        end,
        desc = "Spring Build",
      },
      {
        "<leader>ns",
        function()
          -- Auto-target from current file/folder, then fall back to picker.
          run_nx_task("Nx Serve", "serve", false)
        end,
        desc = "Nx Serve",
      },
      {
        "<leader>nt",
        function()
          run_nx_task("Nx Test", "test", false)
        end,
        desc = "Nx Test",
      },
      {
        "<leader>nb",
        function()
          run_nx_task("Nx Build", "build", false)
        end,
        desc = "Nx Build",
      },
      {
        "<leader>nS",
        function()
          run_nx_task("Nx Serve", "serve", true)
        end,
        desc = "Nx Serve (Pick Target)",
      },
      {
        "<leader>nT",
        function()
          run_nx_task("Nx Test", "test", true)
        end,
        desc = "Nx Test (Pick Target)",
      },
      {
        "<leader>nB",
        function()
          run_nx_task("Nx Build", "build", true)
        end,
        desc = "Nx Build (Pick Target)",
      },
    },
    opts = {
      component_aliases = {
        -- Keep neotest-overseer runs focused on the summary tree only.
        -- Output can still be opened manually via task actions if needed.
        default_neotest = {
          "default",
        },
      },
      task_list = {
        direction = "right",
      },
    },
    init = function()
      register_spring_commands()
    end,
  },
}
