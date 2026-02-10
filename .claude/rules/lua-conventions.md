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

## Feature Pattern

Each feature in `features/` follows this structure:
- `M.setup()` creates user commands and FileType autocmds for `tcl`/`rvt`
- A `M.handle_<action>(bufnr, line, col)` function does the work
- Delegates to `analyzer/` modules for symbol/reference resolution
- Keymaps are buffer-local, set via FileType autocmd

```lua
-- features/definition.lua (real example)
function M.setup()
  vim.api.nvim_create_user_command("TclGoToDefinition", function()
    local result = M.handle_definition(bufnr, line, col)
    -- ... jump to result
  end, { desc = "Go to TCL definition" })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tcl", "rvt" },
    callback = function(args)
      vim.keymap.set("n", "gd", "<cmd>TclGoToDefinition<cr>", { buffer = args.buf })
    end,
  })
end
```

## AST Traversal Pattern

Analyzer modules use a recursive `visit_node` pattern with namespace tracking:

```lua
local function visit_node(node, results, filepath, current_namespace, depth)
  if not node then return end
  depth = depth or 0
  if depth > MAX_DEPTH then return end  -- REQUIRED: prevent infinite recursion

  -- Type-check var_name before using as string (can be table)
  if type(node.var_name) ~= "string" then
    if type(node.var_name) == "table" and node.var_name.name then
      var_name = node.var_name.name
    else
      return
    end
  end

  -- Recurse into children AND body (procs have body.children)
  if node.children then
    for _, child in ipairs(node.children) do
      visit_node(child, results, filepath, current_namespace, depth + 1)
    end
  end
  if node.body and node.body.children then
    for _, child in ipairs(node.body.children) do
      visit_node(child, results, filepath, current_namespace, depth + 1)
    end
  end
end
```

## Indexer Lifecycle

The background indexer (`analyzer/indexer.lua`) has strict lifecycle rules:
- **States:** `idle` -> `scanning` -> `ready`
- **Two-pass indexing:** First pass extracts symbols, second pass resolves references
- **Parallel parsing:** Up to `PARALLEL_JOBS` (6) concurrent parse jobs
- **Cleanup ordering:** On `VimLeavePre`, stop indexer FIRST (sets `shutting_down = true`), THEN stop parser. Reversing this order causes hangs.
- **Disabled by default:** `config.indexer.enabled` must be explicitly set. Background processing causes UI lag if not throttled.

## Plugin Entry

- `init.lua` creates user commands, autocommands, and calls `feature.setup()` for each feature
- `config.lua` handles all configuration with defaults
- `server.lua` manages LSP server lifecycle, conditionally starts indexer

## Testing with Plenary

- Test files end with `_spec.lua`
- Use `describe` and `it` blocks
- Mock vim APIs when needed
- Run via `make test-unit`

## Neovim API Usage

- Use `vim.api.nvim_*` for buffer/window operations
- Use `vim.notify` for user messages
- Use `vim.schedule` for callbacks from async operations (required to avoid fast-event errors)
- Use `vim.defer_fn` for delayed operations (e.g., server restart uses 200ms delay)
- Handle errors gracefully, never crash the editor

## Filetypes

Support both `.tcl` and `.rvt` (Rivet templates)
