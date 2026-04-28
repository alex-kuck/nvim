return {
  {
    -- Base24 Spacedust so Neovim matches Ghostty Spacedust palette.
    "tinted-theming/tinted-vim",
    name = "tinted-vim",
    lazy = false,
    priority = 1000,
  },
  {
    "projekt0n/github-nvim-theme",
    name = "github-theme",
    lazy = false, -- make sure we load this during startup if it is your main colorscheme
    priority = 1000, -- make sure to load this before all the other start plugins
    config = function()
      require("github-theme").setup({
        -- ...
        options = {
          transparent = true,
          dim_inactive = true,
        },
      })

      vim.cmd("colorscheme base24-spacedust")

      -- Keep Spacedust but restore transparent backgrounds and improve Snacks readability.
      -- This avoids the muddy brown panel fill while preserving the palette's foreground colors.
      local function set_spacedust_ui_hl()
        local fg = "#ecf0c1"
        local fg_muted = "#a8b9a8"
        local accent = "#67a0cd"
        local cursorline = "#1b3e4b"
        local active_surface = "#205064"

        -- Restore transparent editor and float surfaces similar to previous github-theme behavior.
        for _, group in ipairs({
          "Normal",
          "NormalNC",
          "NormalFloat",
          "FloatBorder",
          "SignColumn",
          "EndOfBuffer",
        }) do
          vim.api.nvim_set_hl(0, group, { bg = "NONE", ctermbg = "NONE" })
        end

        -- Active line contrast: use a cooler blue-teal shade instead of muddy brown.
        vim.api.nvim_set_hl(0, "CursorLine", { bg = cursorline })
        vim.api.nvim_set_hl(0, "CursorColumn", { bg = cursorline })
        vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#d9e6b8", bg = cursorline, bold = true })

        -- Snacks picker/explorer/list/preview: keep text contrast high on transparent backgrounds.
        vim.api.nvim_set_hl(0, "SnacksPickerNormal", { fg = fg, bg = "NONE" })
        vim.api.nvim_set_hl(0, "SnacksPickerBorder", { fg = accent, bg = "NONE" })
        vim.api.nvim_set_hl(0, "SnacksPickerTitle", { fg = accent, bg = "NONE", bold = true })
        vim.api.nvim_set_hl(0, "SnacksPickerListNormal", { fg = fg, bg = "NONE" })
        vim.api.nvim_set_hl(0, "SnacksPickerListBorder", { fg = accent, bg = "NONE" })
        vim.api.nvim_set_hl(0, "SnacksPickerListTitle", { fg = accent, bg = "NONE", bold = true })
        vim.api.nvim_set_hl(0, "SnacksPickerInputNormal", { fg = fg, bg = "NONE" })
        vim.api.nvim_set_hl(0, "SnacksPickerInputBorder", { fg = accent, bg = "NONE" })
        vim.api.nvim_set_hl(0, "SnacksPickerInputTitle", { fg = accent, bg = "NONE", bold = true })
        vim.api.nvim_set_hl(0, "SnacksPickerPreviewNormal", { fg = fg, bg = "NONE" })
        vim.api.nvim_set_hl(0, "SnacksPickerPreviewBorder", { fg = accent, bg = "NONE" })
        vim.api.nvim_set_hl(0, "SnacksPickerPreviewTitle", { fg = accent, bg = "NONE", bold = true })
        vim.api.nvim_set_hl(0, "SnacksPickerListCursorLine", { fg = fg, bg = cursorline })
        vim.api.nvim_set_hl(0, "SnacksPickerPreviewCursorLine", { fg = fg, bg = cursorline })

        -- File-tree specific contrast tweaks for explorer nodes.
        vim.api.nvim_set_hl(0, "SnacksPickerDirectory", { fg = accent, bg = "NONE", bold = true })
        vim.api.nvim_set_hl(0, "SnacksPickerFile", { fg = fg, bg = "NONE" })
        vim.api.nvim_set_hl(0, "SnacksPickerDir", { fg = fg_muted, bg = "NONE" })
        vim.api.nvim_set_hl(0, "SnacksPickerTree", { fg = "#8f9b8f", bg = "NONE" })
        vim.api.nvim_set_hl(0, "SnacksPickerPathHidden", { fg = "#8b9a87", bg = "NONE" })
        vim.api.nvim_set_hl(0, "SnacksPickerPathIgnored", { fg = "#6f7b70", bg = "NONE" })

        -- Keep tabline/statusline/winbar transparent to remove the brown strip effect.
        vim.api.nvim_set_hl(0, "StatusLine", { fg = fg, bg = "NONE" })
        vim.api.nvim_set_hl(0, "StatusLineNC", { fg = fg_muted, bg = "NONE" })
        vim.api.nvim_set_hl(0, "TabLine", { fg = fg_muted, bg = "NONE" })
        vim.api.nvim_set_hl(0, "TabLineFill", { fg = fg_muted, bg = "NONE" })
        vim.api.nvim_set_hl(0, "TabLineSel", { fg = "#fefff0", bg = active_surface, bold = true })
        vim.api.nvim_set_hl(0, "WinBar", { fg = "#fefff0", bg = active_surface, bold = true })
        vim.api.nvim_set_hl(0, "WinBarNC", { fg = fg_muted, bg = "NONE" })

        -- Bufferline + breadcrumbs: preserve readability with transparent backgrounds.
        vim.api.nvim_set_hl(0, "BufferLineFill", { bg = "NONE" })
        vim.api.nvim_set_hl(0, "BufferLineBackground", { fg = "#829082", bg = "NONE" })
        vim.api.nvim_set_hl(0, "BufferLineBufferVisible", { fg = fg_muted, bg = "NONE" })
        vim.api.nvim_set_hl(0, "BufferLineBufferSelected", { fg = "#fefff0", bg = active_surface, bold = true, italic = false })
        vim.api.nvim_set_hl(0, "BufferLineTab", { fg = fg_muted, bg = "NONE" })
        vim.api.nvim_set_hl(0, "BufferLineTabSelected", { fg = "#fefff0", bg = active_surface, bold = true })
        vim.api.nvim_set_hl(0, "BufferLineSeparator", { fg = "#3b5964", bg = "NONE" })
        vim.api.nvim_set_hl(0, "BufferLineSeparatorSelected", { fg = active_surface, bg = "NONE" })
        vim.api.nvim_set_hl(0, "BufferLineIndicatorSelected", { fg = "#e3cd7b", bg = active_surface, bold = true })
        vim.api.nvim_set_hl(0, "BufferLineModifiedSelected", { fg = "#ffc777", bg = active_surface, bold = true })
        vim.api.nvim_set_hl(0, "BufferLineCloseButtonSelected", { fg = "#ff8a39", bg = active_surface, bold = true })

        -- Normalize TSX icon colors in bufferline so they don't stay bright blue.
        -- This keeps React buffers visually consistent with the active/inactive tab contrast.
        vim.api.nvim_set_hl(0, "BufferLineDevIconTsx", { fg = "#adcab8", bg = "NONE" })
        vim.api.nvim_set_hl(0, "BufferLineDevIconTsxVisible", { fg = "#adcab8", bg = "NONE" })
        vim.api.nvim_set_hl(0, "BufferLineDevIconTsxInactive", { fg = "#8b9a87", bg = "NONE" })
        vim.api.nvim_set_hl(0, "BufferLineDevIconTsxSelected", { fg = "#fefff0", bg = active_surface, bold = true })
        vim.api.nvim_set_hl(0, "BufferLineDevIconTypeScriptReact", { fg = "#adcab8", bg = "NONE" })
        vim.api.nvim_set_hl(0, "BufferLineDevIconTypeScriptReactSelected", { fg = "#fefff0", bg = active_surface, bold = true })

        vim.api.nvim_set_hl(0, "NavicText", { fg = fg_muted, bg = "NONE" })
        vim.api.nvim_set_hl(0, "NavicSeparator", { fg = "#7e8f82", bg = "NONE" })
        vim.api.nvim_set_hl(0, "NavicIconsFile", { fg = fg_muted, bg = "NONE" })
        vim.api.nvim_set_hl(0, "NavicIconsModule", { fg = accent, bg = "NONE" })
        vim.api.nvim_set_hl(0, "NavicIconsNamespace", { fg = accent, bg = "NONE" })
        vim.api.nvim_set_hl(0, "NavicIconsPackage", { fg = accent, bg = "NONE" })
        vim.api.nvim_set_hl(0, "NavicIconsClass", { fg = "#e3cd7b", bg = "NONE" })
        vim.api.nvim_set_hl(0, "NavicIconsMethod", { fg = accent, bg = "NONE" })
        vim.api.nvim_set_hl(0, "NavicIconsProperty", { fg = "#adcab8", bg = "NONE" })
        vim.api.nvim_set_hl(0, "NavicIconsFunction", { fg = accent, bg = "NONE" })
        vim.api.nvim_set_hl(0, "NavicIconsVariable", { fg = fg_muted, bg = "NONE" })

        -- TSX/JSX readability: increase contrast for component/tag heavy files.
        vim.api.nvim_set_hl(0, "@tag", { fg = "#67a0cd", bold = true })
        vim.api.nvim_set_hl(0, "@tag.delimiter", { fg = "#adcab8" })
        vim.api.nvim_set_hl(0, "@tag.attribute", { fg = "#e3cd7b" })
        vim.api.nvim_set_hl(0, "@constructor", { fg = "#83a6b3", bold = true })
        vim.api.nvim_set_hl(0, "tsxTagName", { fg = "#67a0cd", bold = true })
        vim.api.nvim_set_hl(0, "tsxComponentName", { fg = "#83a6b3", bold = true })
        vim.api.nvim_set_hl(0, "jsxTagName", { fg = "#67a0cd", bold = true })
        vim.api.nvim_set_hl(0, "jsxComponentName", { fg = "#83a6b3", bold = true })

        -- Word/reference highlighting: make under-cursor symbol references obvious.
        vim.api.nvim_set_hl(0, "LspReferenceText", { fg = "#fefff0", bg = "#2a4e5d", bold = true })
        vim.api.nvim_set_hl(0, "LspReferenceRead", { fg = "#fefff0", bg = "#2a4e5d", bold = true })
        vim.api.nvim_set_hl(0, "LspReferenceWrite", { fg = "#fefff0", bg = "#3a5f2f", bold = true })
        vim.api.nvim_set_hl(0, "MatchWord", { fg = "#fefff0", bg = "#2a4e5d", underline = true })
      end

      set_spacedust_ui_hl()
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = set_spacedust_ui_hl,
        desc = "Keep Spacedust transparent and Snacks readable",
      })

      -- Keep this override disabled so Spacedust colors stay exact.
      -- Uncomment to restore your bright-yellow active text behavior.
      -- vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
      --   callback = function()
      --     vim.api.nvim_set_hl(0, "Normal", { fg = "#ffdb00" })
      --   end,
      --   desc = "Set active buffer text to bright yellow",
      -- })
    end,
  },
  -- {
  --   "folke/tokyonight.nvim",
  --   opts = {
  --     transparent = true,
  --     styles = {
  --       sidebars = "transparent",
  --       floats = "transparent",
  --     },
  --   },
  -- },
}
