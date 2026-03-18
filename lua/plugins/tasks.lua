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
          local overseer = require("overseer")
          local root = service_root()
          if not root then
            vim.notify("No Gradle root found", vim.log.levels.WARN)
            return
          end
          overseer.new_task({
            name = "Spring Boot Run",
            cmd = { gradle_cmd(root), "bootRun" },
            cwd = root,
            components = { "default" },
          }):start()
        end,
        desc = "Spring Boot Run",
      },
      {
        "<leader>sB",
        function()
          local overseer = require("overseer")
          local root = service_root()
          if not root then
            vim.notify("No Gradle root found", vim.log.levels.WARN)
            return
          end
          overseer.new_task({
            name = "Spring Boot Test",
            cmd = { gradle_cmd(root), "test" },
            cwd = root,
            components = { "default" },
          }):start()
        end,
        desc = "Spring Boot Test",
      },
      {
        "<leader>sl",
        function()
          local overseer = require("overseer")
          local root = service_root()
          if not root then
            vim.notify("No Gradle root found", vim.log.levels.WARN)
            return
          end
          overseer.new_task({
            name = "Spring Boot Test Run",
            cmd = { gradle_cmd(root), "bootTestRun" },
            cwd = root,
            components = { "default" },
          }):start()
        end,
        desc = "Spring Boot Test Run",
      },
      {
        "<leader>ns",
        function()
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
      task_list = {
        direction = "right",
      },
    },
  },
}
