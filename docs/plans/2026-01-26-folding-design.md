# Code Folding Design

**Date:** 2026-01-26
**Status:** Approved
**Phase:** 4

## Overview

AST-based code folding for TCL/RVT files using the existing parser infrastructure. The LSP provides fold ranges; Neovim controls display and initial state.

## Scope

### Foldable Constructs

| AST Node Type | Fold Kind | Notes |
|--------------|-----------|-------|
| `proc_definition` | region | Entire proc body |
| `if_statement` | region | Each branch (if/elseif/else) |
| `switch_statement` | region | Whole switch + individual cases |
| `foreach_statement` | region | Loop body |
| `for_statement` | region | Loop body |
| `while_statement` | region | Loop body |
| `namespace_eval` | region | Namespace body |
| `oo_class` | region | Class body |
| `oo_method` | region | Method body |
| `comment_block` | comment | Multi-line `#` comments |

### Out of Scope (YAGNI)

- Custom fold display text (Neovim's `foldtext` handles this)
- Auto-fold on open (Neovim's `foldlevelstart` handles this)
- Configurable fold size threshold
- Import folding (TCL doesn't have import blocks)

## Architecture

### LSP Method

`textDocument/foldingRange`

### Data Flow

```
1. Neovim sends foldingRange request with document URI
2. folding.lua receives request
3. Get cached AST (or parse if not cached)
4. Call TCL folding module to extract ranges from AST
5. Return array of FoldingRange objects to Neovim
```

### FoldingRange Structure (LSP Spec)

```lua
{
  startLine = 0,      -- 0-indexed
  startCharacter = 0, -- optional
  endLine = 10,
  endCharacter = 0,   -- optional
  kind = "region"     -- "region" | "comment" | "imports"
}
```

## Files

### New Files

| File | Purpose | Est. Lines |
|------|---------|------------|
| `lua/tcl-lsp/features/folding.lua` | LSP handler | 50-80 |
| `tcl/core/ast/folding.tcl` | AST traversal | 100-150 |
| `tests/tcl/core/ast/test_folding.tcl` | TCL unit tests | ~100 |
| `tests/lua/features/folding_spec.lua` | Lua unit tests | ~50 |
| `tests/e2e/folding_spec.lua` | E2E tests | ~50 |

### Modified Files

| File | Change |
|------|--------|
| `lua/tcl-lsp/server.lua` | Add `foldingRangeProvider = true` capability |
| `lua/tcl-lsp/init.lua` | Register `textDocument/foldingRange` handler |

## Implementation Details

### TCL Module: `tcl/core/ast/folding.tcl`

```tcl
namespace eval ::ast::folding {
    # Extract fold ranges from AST
    # Returns: list of dicts with startLine, endLine, kind
    proc extract_ranges {ast} { ... }
}
```

**Range Calculation:**
- `startLine`: Line where construct begins (the `proc`, `if`, etc.)
- `endLine`: Line containing the closing `}`
- Exclude single-line constructs

**Traversal:** Recursive walk of AST children, collecting ranges into flat list.

### Lua Module: `lua/tcl-lsp/features/folding.lua`

```lua
local M = {}

function M.setup(client)
  -- Register handler for textDocument/foldingRange
end

function M.handle(params)
  -- 1. Get document URI from params
  -- 2. Get or parse AST (via parser module)
  -- 3. Call TCL folding extractor
  -- 4. Transform to LSP FoldingRange format
  -- 5. Return ranges array
end

return M
```

**Error Handling:**
- Parse failure: Return empty array (no folds, no crash)
- Invalid AST node: Skip node, continue traversal

**Caching:**
- Reuse existing AST cache from `parser/` module
- No separate cache for fold ranges (cheap to recompute)

## Testing Strategy

### TCL Unit Tests

- Each node type produces correct ranges
- Nested constructs (proc inside namespace)
- Single-line constructs excluded
- Multi-line comment blocks

### Lua Unit Tests

- Handler returns valid FoldingRange array
- Empty file returns empty array
- Parse errors return empty array gracefully

### E2E Tests

- Open fixture file with procs/namespaces
- Request fold ranges via LSP
- Verify expected ranges returned

### Test Fixture Requirements

- Nested structures (namespace containing procs)
- Control flow examples (if/switch/foreach)
- Multi-line comments
- Single-line constructs (verify exclusion)
