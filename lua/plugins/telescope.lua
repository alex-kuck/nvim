local function repo_root()
  local git = vim.fs.find({ ".git" }, { upward = true })[1]
  return git and vim.fs.dirname(git) or vim.fn.getcwd()
end

local function set_picker_keys()
  vim.keymap.set("n", "<leader>/", function()
    Snacks.picker.grep({ cwd = repo_root() })
  end, { desc = "Grep (Repo Root)" })

  vim.keymap.set("n", "<leader><space>", function()
    Snacks.picker.files({ cwd = repo_root() })
  end, { desc = "Find Files (Repo Root)" })

  vim.keymap.set("n", "<leader>ff", function()
    Snacks.picker.files({ cwd = repo_root() })
  end, { desc = "Find Files (Repo Root)" })
end

return {
  {
    "nvim-telescope/telescope.nvim",
    version = "*",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    init = set_picker_keys,
  },
}
