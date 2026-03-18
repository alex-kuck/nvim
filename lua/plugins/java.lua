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

return {
  {
    "mfussenegger/nvim-jdtls",
    enabled = false,
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
        "kotlin-language-server",
        "ktlint",
      })
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Kotlin LSP for controllers/services when editing under /service.
        kotlin_language_server = {
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
    -- Load for Kotlin too so shared Java/Spring keymaps are available
    -- when editing Kotlin controllers in mixed projects.
    ft = { "java", "kotlin" },
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
          run_gradle({ "bootTestRun" }, "Spring Boot Test Run")
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
