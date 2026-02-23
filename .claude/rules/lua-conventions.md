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

## Lazy Loading for Circular Dependencies

When module A needs module B at runtime but B also depends on A during load, use deferred require:

```lua
-- parser/ast.lua (real example: ast needs validator, validator needs ast's types)
local validator_loaded = false
local validator = nil

local function get_validator()
  if not validator_loaded then
    validator_loaded = true
    local ok, v = pcall(require, "tcl-lsp.parser.validator")
    if ok then
      validator = v
    end
  end
  return validator
end
```

**When to use:** Only for actual circular dependency chains. If there's no cycle, use normal top-level `require`.

**Key details:**
- The `loaded` flag ensures `require` is called at most once (even if it fails)
- `pcall` prevents crashes if the dependency is missing or errors during load
- Call `get_validator()` at the point of use, not at module load time

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

Use `visitor.walk()` for AST traversal. It handles depth guards, namespace tracking, and
recursion into all body types (children, body, then_body, else_body, elseif, cases):

```lua
local visitor = require("tcl-lsp.analyzer.visitor")
local variable = require("tcl-lsp.utils.variable")

local results = {}
visitor.walk(ast, {
  set = function(node, ctx)
    -- Always type-check var_name (can be string or table)
    local var_name = variable.safe_var_name(node.var_name)
    if not var_name then return end

    table.insert(results, {
      name = var_name,
      namespace = ctx.namespace,  -- tracked automatically
      filepath = ctx.filepath,
    })
  end,
  proc = function(node, ctx)
    -- ctx.namespace is the enclosing namespace
    -- ctx.visit(sub_node) recurses into sub-nodes
  end,
}, filepath)
```

Only `semantic_tokens.lua` and `folding.lua` use custom traversal (they classify tokens
inline per-node-type rather than just collecting matches).

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
