# Go-to-Definition Design

**Date:** 2026-01-22
**Status:** Ready for implementation
**Phase:** 3 (Lua Integration)

## Overview

Implement workspace-wide go-to-definition for TCL files in Neovim. Users can jump to the definition of procs, namespaces, and variables using the standard `gd` keybinding.

## Goals

- Workspace-wide symbol lookup (not just current file)
- Scope-aware resolution (handles TCL's namespace/upvar/global semantics)
- Non-blocking background indexing
- Immediate usability (single-file fallback while indexing)

## Architecture

```
User triggers "go to definition" (gd)
    → Get word under cursor + current scope context
    → Resolver builds qualified name candidates
    → Query index for matches
    → Return location(s) to Neovim LSP
```

### Components

| Component | File | Responsibility |
|-----------|------|----------------|
| Symbol Index | `analyzer/index.lua` | In-memory symbol storage and lookup |
| Background Indexer | `analyzer/indexer.lua` | Non-blocking workspace scanner |
| Scope Resolver | `analyzer/scope.lua` | Extract scope context from AST |
| Definition Resolver | `analyzer/definitions.lua` | Find definition for symbol at cursor |
| LSP Handler | `features/definition.lua` | Neovim LSP integration |

## Symbol Index

Dual-indexed structure for fast lookups and efficient updates:

```lua
M.symbols = {
  -- Primary index: qualified name → symbol
  ["::math::add"] = {
    type = "proc",
    name = "add",
    qualified_name = "::math::add",
    file = "/project/lib/math.tcl",
    range = { start = {line=10, col=1}, end_pos = {line=25, col=1} },
    params = { {name="a"}, {name="b"} },
    scope = "::",
  },
}

-- Secondary index: file → symbol names (for invalidation)
M.files = {
  ["/project/lib/math.tcl"] = { "::math::add", "::math::subtract" },
}
```

### Operations

- `add_symbol(symbol)` - Add/update a symbol
- `remove_file(filepath)` - Remove all symbols from a file
- `find(name, scope_context)` - Lookup with scope resolution
- `find_all(pattern)` - Prefix search (for future completion support)

## Background Indexer

Scans workspace without blocking the editor:

```lua
M.state = {
  status = "idle",     -- idle | scanning | ready
  queued = {},         -- files waiting to be indexed
  total_files = 0,
  indexed_count = 0,
}
```

### Process

1. On startup, find all `.tcl` and `.rvt` files in workspace
2. Process files in batches of 5
3. Use `vim.defer_fn` to yield between batches
4. Update state for progress reporting

### File Change Handling

- `BufWritePost` triggers re-index of modified file
- Remove old symbols, parse fresh, add new symbols
- Mark file as dirty for lazy re-indexing on next lookup

## Scope Resolution

TCL scoping requires context-aware resolution. Build scope context by walking the AST:

```lua
context = {
  namespace = "::",     -- current namespace
  proc = nil,           -- inside a proc?
  locals = {},          -- local variables in scope
  globals = {},         -- declared globals
  upvars = {},          -- upvar bindings
}
```

### Resolution Order

When looking up symbol `foo`:

1. Local variables (proc params, `set` in same proc)
2. `upvar` bindings → follow to original
3. `global` declarations → look in `::`
4. Current namespace → `::current::foo`
5. Global namespace → `::foo`

## Definition Resolver

```lua
function M.find_definition(bufnr, line, col)
  -- 1. Get word under cursor
  -- 2. Parse current buffer for AST
  -- 3. Build scope context at cursor position
  -- 4. Generate qualified name candidates
  -- 5. Query index for each candidate
  -- 6. Fallback: search current file AST directly
end
```

### Fallback Strategy

If index not ready, search current file's AST directly. Users get immediate single-file support while background indexing completes.

## Neovim LSP Integration

Register handler for `textDocument/definition`:

```lua
vim.lsp.handlers["textDocument/definition"] = function(_, result, ctx)
  local definition = definitions.find_definition(bufnr, line, col)
  if definition then
    vim.lsp.util.jump_to_location(definition, "utf-8")
  else
    vim.notify("No definition found", vim.log.levels.INFO)
  end
end
```

Works with standard `gd` keybinding via Neovim's LSP infrastructure.

## Error Handling

| Case | Handling |
|------|----------|
| Parser failure | Log warning, return nil, show "No definition found" |
| Index not ready | Fall back to current file search |
| Cursor on `$varname` | Strip leading `$` before lookup |
| Cursor on `::ns::proc` | Parse as qualified name, skip resolution |
| Cursor on `[command]` | Strip brackets, resolve command name |
| Multiple definitions | Return most recent (last in file order) |
| Circular `upvar` chains | Limit resolution depth to 10 |
| File deleted while indexing | Catch error, skip file, continue |
| Binary/non-UTF8 files | Skip files that fail to decode |
| Symlinked files | Resolve to canonical path |

## Files to Create/Modify

### New Files

- `lua/tcl-lsp/analyzer/index.lua`
- `lua/tcl-lsp/analyzer/indexer.lua`
- `lua/tcl-lsp/analyzer/scope.lua`
- `lua/tcl-lsp/analyzer/definitions.lua` (replace stub)
- `lua/tcl-lsp/features/definition.lua`

### Modified Files

- `lua/tcl-lsp/init.lua` - Start indexer on setup
- `lua/tcl-lsp/server.lua` - Wire up LSP handlers

## Testing Strategy

1. Unit tests for each component (index, scope, resolver)
2. Integration tests with sample TCL files
3. Edge case tests (qualified names, upvar chains, etc.)

## Future Extensions

- **Completion:** Reuse index for autocomplete suggestions
- **Hover:** Show proc signature and docstring on hover
- **References:** Find all usages of a symbol
- **Rename:** Rename symbol across workspace
