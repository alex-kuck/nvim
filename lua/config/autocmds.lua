-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

local yaml_group = vim.api.nvim_create_augroup("yaml_local_indent", { clear = true })

local function normalize_yaml_tabs(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    local leading_tabs = line:match("^(\t+)")
    if leading_tabs then
      local spaces = string.rep("  ", #leading_tabs)
      lines[i] = line:gsub("^\t+", spaces, 1)
    end
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

vim.api.nvim_create_autocmd("FileType", {
  group = yaml_group,
  pattern = { "yaml" },
  callback = function(args)
    -- YAML indentation must be spaces; keep width aligned with project conventions.
    vim.opt_local.expandtab = true
    vim.opt_local.tabstop = 2
    vim.opt_local.softtabstop = 2
    vim.opt_local.shiftwidth = 2
    normalize_yaml_tabs(args.buf)
  end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
  group = yaml_group,
  pattern = { "*.yml", "*.yaml" },
  callback = function(args)
    normalize_yaml_tabs(args.buf)
  end,
})
