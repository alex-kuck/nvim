# AGENTS.md

Guidance for coding agents working in this Neovim config repo.

## Scope

- Repository: `/Users/akucksdorf/.config/nvim`
- This is a LazyVim-based Neovim configuration, not an application service.
- Most changes are Lua plugin specs under `lua/plugins/*.lua` plus config under `lua/config/*.lua`.

## Rule Sources Checked

- `.cursor/rules/`: not present
- `.cursorrules`: not present
- `.github/copilot-instructions.md`: not present

No external Cursor/Copilot rule files currently constrain this repo.

## Build / Lint / Test Commands

## 1) Fast config validation (primary)

- Start/exit Neovim headless:
  - `nvim --headless "+qa"`
- Parse a specific Lua file:
  - `luac -p "lua/plugins/java.lua"`
  - `luac -p "lua/plugins/typescript_nx.lua"`
- Validate a plugin file via Neovim runtime:
  - `nvim --headless "+lua dofile('lua/plugins/ui.lua')" +qa`

Use these after every Lua edit.

## 2) Plugin sync / lockfile

- Sync plugins:
  - `nvim --headless "+Lazy! sync" +qa`
- Reload a specific plugin during development:
  - `:Lazy reload <plugin-name>` (interactive)

Note: lockfile updates appear in `lazy-lock.json` when plugin graph changes.

## 3) Formatting

- Formatting style is defined by `stylua.toml`:
  - 2 spaces
  - max width 120
- If `stylua` is available, format repo Lua files:
  - `stylua .`

If `stylua` is unavailable in environment, keep edits manually aligned with existing style.

## 4) Repo-level tests

- There is no standalone CI test suite in this repo today.
- “Testing” means syntax/runtime checks plus targeted behavior checks in real Neovim sessions.

## 5) Single-test guidance (important)

This repo configures Neotest behavior for external projects (Go/Kotlin/TypeScript), so single-test runs are usually performed interactively in the target project:

- Go nearest test:
  - `<leader>tr` (smart nearest in Go buffers)
- Kotlin nearest test:
  - `<leader>tr` (Neotest/Overseer path, Gradle fallback)
- TS/JS nearest test (Vitest/Jest):
  - `<leader>tr`

For Spring/Kotlin Gradle fallback, single-test semantics rely on:
- `gradle test --tests <spec>`

## 6) Spring / Nx task commands exposed by this config

Interactive Ex commands (from `lua/plugins/tasks.lua`):

- `:SpringBootRun`
- `:SpringBootTest`
- `:SpringBootTestRun`
- `:SpringBootStopAll`
- `:SpringGradle <args>`

Examples:
- `:SpringGradle detekt --auto-correct`
- `:SpringGradle test --tests com.example.FooTest`

Nx task shortcuts (interactive keymaps):
- `<leader>ns` / `<leader>nS` serve
- `<leader>nt` / `<leader>nT` test
- `<leader>nb` / `<leader>nB` build

## Architecture / Important Files

- Bootstrapping:
  - `init.lua`
  - `lua/config/lazy.lua`
- Core config:
  - `lua/config/options.lua`
  - `lua/config/keymaps.lua`
  - `lua/config/autocmds.lua`
- Language/tooling plugin specs:
  - `lua/plugins/java.lua`
  - `lua/plugins/typescript_nx.lua`
  - `lua/plugins/go.lua`
  - `lua/plugins/tasks.lua`
  - `lua/plugins/ui.lua`

## Coding Style Guidelines (Lua)

## Formatting / structure

- Use 2-space indentation and 120-column width.
- Prefer small local helper functions at top of file.
- Keep plugin specs returned as Lua table arrays (`return { ... }`).
- Keep comments brief and only for non-obvious logic.
- Whenever editing plugins, keybindings, commands, or workflow wiring, add a brief colocated comment that explains purpose, intended usage, and why the behavior is needed.

## Naming

- Helper functions: `snake_case` (`service_root`, `run_spring_task`).
- Prefer descriptive names over abbreviations in cross-file logic.
- Use consistent prefixes for related helpers (`nx_*`, `kotlin_*`, `run_*`).

## Imports / requires

- Require modules close to where they are used unless shared by many helpers.
- Use `pcall(require, ...)` for optional integrations to avoid hard failures.
- Avoid global state; if needed, keep file-local (`local foo = ...`) and documented.

## Types / defensive coding

- Guard optional tables before mutation:
  - `opts.adapters = opts.adapters or {}`
  - `opts.formatters_by_ft = opts.formatters_by_ft or {}`
- Check buffer/filetype/path before acting.
- Prefer early returns for invalid context.

## Error handling

- Use `vim.notify(..., vim.log.levels.WARN/INFO/ERROR)` for user-facing failures.
- Use graceful fallbacks (example: `./gradlew` -> `gradle`).
- For optional feature paths, degrade behavior rather than throwing.

## Plugin configuration patterns used in this repo

- Mason packages are appended via helper (`mason_ensure`).
- LSP config extends `neovim/nvim-lspconfig` with `opts.servers`.
- Neotest adapters may be configured as adapter objects (not only keyed tables) when required by adapter behavior.
- Keep monorepo root detection explicit (`service` and `ui` assumptions are intentional).

## Neotest / test UX conventions

- Prefer opening summary tree for test runs (`summary.open`) where relevant.
- For Kotlin + Spring, Gradle/Overseer fallbacks are expected for unsupported adapter cases.
- Preserve fixes for neotest-kotlin report parsing unless replaced with upstream-compatible solution.

## Git / change management

- Do not revert unrelated user changes.
- Keep commits focused and small.
- Commit messages in this repo are imperative and concise:
  - `Improve Kotlin neotest stability and Spring task UX`
  - `Improve Nx neotest tree visibility and adapter roots`

## Agent workflow checklist

1. Read relevant file(s) fully before editing.
2. Make minimal, localized edits.
3. Run `luac -p` on changed Lua files.
4. Run `nvim --headless "+qa"`.
5. If plugin graph changed, sync and verify `lazy-lock.json`.
6. Summarize behavior impact and any manual verification steps.

## Notes for future contributors

- This config is optimized for a split monorepo layout (`/service` + `/ui`) and IntelliJ-like workflows.
- If changing root detection logic, validate both trees from repository root startup.
- If changing test adapters, verify:
  - nearest test
  - file test
  - “run all” behavior
  - summary status transitions (pass -> fail -> pass).
