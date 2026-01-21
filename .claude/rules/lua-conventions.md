# Lua/Neovim Conventions

## Module Pattern

```lua
local M = {}

-- Private functions (local)
local function helper() end

-- Public functions
function M.public_function() end

return M
```

## Plugin Entry

- `init.lua` creates user commands and autocommands
- `config.lua` handles all configuration with defaults
- `server.lua` manages LSP server lifecycle

## Testing with Plenary

- Test files end with `_spec.lua`
- Use `describe` and `it` blocks
- Mock vim APIs when needed
- Run via `make test-unit`

## Neovim API Usage

- Use `vim.api.nvim_*` for buffer/window operations
- Use `vim.notify` for user messages
- Use `vim.schedule` or `vim.defer_fn` for async operations
- Handle errors gracefully, never crash the editor

## Filetypes

Support both `.tcl` and `.rvt` (Rivet templates)
