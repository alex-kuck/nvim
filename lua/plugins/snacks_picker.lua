local function repo_root()
  local git = vim.fs.find({ ".git" }, { upward = true })[1]
  return git and vim.fs.dirname(git) or vim.fn.getcwd()
end

return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        actions = {
          toggle_cwd = function(p)
            p:set_cwd(repo_root())
            p:find()
          end,
        },
      },
    },
    keys = {
      {
        "<leader>/",
        function()
          Snacks.picker.grep({ cwd = repo_root() })
        end,
        desc = "Grep (Repo Root)",
      },
      {
        "<leader><space>",
        function()
          Snacks.picker.files({ cwd = repo_root() })
        end,
        desc = "Find Files (Repo Root)",
      },
      {
        "<leader>ff",
        function()
          Snacks.picker.files({ cwd = repo_root() })
        end,
        desc = "Find Files (Repo Root)",
      },
    },
  },
}
