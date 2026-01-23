# Rename Feature Design

## Overview

The rename feature allows users to rename any TCL symbol (procedures, variables, namespaces) across all files in the workspace. It builds on the existing find-references infrastructure.

## Core Flow

```
User triggers rename → Prompt for new name → Validate new name
→ Find all references → Apply edits to all locations
```

## Files

**New Files:**
- `lua/tcl-lsp/features/rename.lua` - Main rename logic

**Modified Files:**
- `lua/tcl-lsp/init.lua` - Register `:TclLspRename` command and LSP handler

**Dependencies:**
- Reuses `features/references.lua` for finding all symbol occurrences
- Reuses `parser/bridge.lua` for AST access

## Validation & Conflict Detection

### New Name Validation (in order)

1. **Empty check** - Reject empty or whitespace-only names
2. **Character validation** - TCL identifiers allow alphanumeric + underscore; namespaces allow `::`
3. **Conflict detection** - Search AST for existing symbol with the new name in the same scope

### Conflict Detection Logic

```
Get current symbol's scope (global, namespace, or proc-local)
→ Query AST for symbols with new name in that scope
→ If found, show warning: "Symbol 'newName' already exists in this scope. Continue? (y/n)"
```

### Scope Rules

- **Proc-local variables** - Check within the same proc body
- **Namespace procs/vars** - Check within the same namespace
- **Global symbols** - Check global namespace

User can override the warning and proceed (it's a warning, not a hard block).

## Find-References Integration

### Reusing find-references (safely)

The rename module calls the existing references API but doesn't modify it:

```lua
-- rename.lua
local references = require("tcl-lsp.features.references")

local function get_all_occurrences(bufnr, position)
  -- Calls existing public API - no changes to references.lua
  return references.find_references(bufnr, position, { include_declaration = true })
end
```

### Applying Edits

Uses Neovim's built-in workspace edit API for atomic multi-file changes:

```lua
vim.lsp.util.apply_workspace_edit(workspace_edit, "utf-8")
```

This handles:
- Undo as a single operation
- Multiple buffers (open and unopened files)
- Proper cursor positioning after edit

### Regression Protection

Add tests that verify find-references behavior is unchanged after rename is added - same inputs produce same outputs.

## User Interface

### Command

```vim
:TclLspRename [newname]
```
- With argument: Skip prompt, rename directly to `newname`
- Without argument: Prompt via `vim.ui.input`

### LSP Handler

Register `textDocument/rename` so standard LSP keymaps work:

```lua
-- Users' existing LSP config (e.g., <leader>rn) will just work
vim.lsp.buf.rename()
```

### Prompt Flow

```lua
vim.ui.input({ prompt = "New name: ", default = current_symbol_name }, function(new_name)
  -- validate → check conflicts → apply edits
end)
```

### Conflict Warning

```lua
vim.ui.select({ "Yes", "No" }, { prompt = "Symbol 'foo' already exists. Rename anyway?" }, ...)
```

### Success/Error Feedback

- Success: `vim.notify("Renamed 'old' to 'new' in 5 files (12 occurrences)")`
- Error: `vim.notify("Rename failed: <reason>", vim.log.levels.ERROR)`

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Cursor not on a symbol | "No symbol under cursor" |
| Symbol not found in AST | "Cannot rename this symbol" |
| New name same as old | "New name is the same as current name" |
| Invalid characters in name | "Invalid identifier: <reason>" |
| File write fails (readonly) | "Cannot write to <file>: readonly" |
| Parser timeout | "Parser timed out - file may be too large" |

## Edge Cases

1. **Unsaved buffers** - Prompt to save or use buffer content
2. **Symbol in string/comment** - Don't rename (find-references already filters these)
3. **Partial namespace match** - `::foo` vs `::foobar` must be distinct
4. **External files** - Files outside workspace are skipped with a warning

## Undo Behavior

Single `u` undoes entire rename across all affected buffers (Neovim handles this via workspace edit).

## Testing Strategy

### Unit Tests (`tests/lua/features/rename_spec.lua`)

1. **Validation tests**
   - Empty name rejected
   - Invalid characters rejected
   - Valid names accepted (including namespaced `::foo::bar`)

2. **Conflict detection tests**
   - Detects existing proc in same namespace
   - Detects existing variable in same proc
   - No false positive for same name in different scope

3. **Rename application tests**
   - Single occurrence renamed
   - Multiple occurrences in one file
   - Multiple files updated

### Regression Tests

Add explicit tests in `tests/lua/features/references_spec.lua` that lock down current behavior - run before and after rename integration.

### Integration Tests

- End-to-end: trigger `:TclLspRename`, verify all files updated
- Undo: verify single `u` reverts all changes
