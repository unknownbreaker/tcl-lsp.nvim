# TCL Completion Design

**Date:** 2026-01-26
**Status:** Approved
**Phase:** 6

## Overview

Context-aware autocompletion for TCL/RVT files, triggered after typing 2+ characters. Completes procedures, variables, TCL builtins, namespace-qualified names, and package names.

## Scope

### What gets completed:
- Procedures (user-defined and from project)
- Variables (`$varname`)
- TCL builtin commands (`puts`, `set`, `if`, `foreach`, etc.)
- Namespace-qualified names (`::namespace::proc`)
- Package commands (from `package require`)

### Completion item format:
- Name + type label (e.g., `format_date` with label "proc")
- No signature or documentation in completion list (keeps it fast/clean)

### Context-aware filtering:
| Pattern | Context | Complete with |
|---------|---------|---------------|
| `$` or `$foo` | Variable | Variables only |
| `::` or `::ns::` | Namespace | Namespace-qualified procs |
| `package require ` | Package | Package names only |
| `[command ` | Command arg | Variables, procs |
| Default | Command position | Procs, builtins, commands |

### Trigger:
After typing 2+ characters (configurable via `completion.trigger_length`)

### Not in scope (YAGNI):
- Signature preview in completion
- Documentation snippets
- Fuzzy matching (use Neovim's built-in)
- Auto-import on complete

## Architecture

### Data Sources

| Source | Items | How |
|--------|-------|-----|
| Current file | Procs, variables | Parse AST on each completion request |
| Project index | Procs from other files | Use existing analyzer/indexer |
| Builtins | TCL commands | Static list (~80 commands) |
| Packages | Package names | Static list of common packages |

### Files

| File | Purpose | Est. Lines |
|------|---------|------------|
| `lua/tcl-lsp/features/completion.lua` | Main completion logic | 150-200 |
| `lua/tcl-lsp/data/builtins.lua` | Static TCL builtin list | ~100 |
| `lua/tcl-lsp/data/packages.lua` | Static package list | ~30 |
| `tests/lua/features/completion_spec.lua` | Tests | 100-150 |

### Modified Files

| File | Change |
|------|--------|
| `lua/tcl-lsp/init.lua` | Register completion, add setup call |
| `lua/tcl-lsp/config.lua` | Add completion config options |

### Public API

```lua
M.get_completions(bufnr, line, col)  -- Returns completion items
M.setup()                             -- Registers omnifunc for TCL files
```

### Data Flow

```
User types → Detect context → Gather candidates from sources → Filter by context → Return items
```

## Implementation Details

### Context Detection

```lua
local function detect_context(line_text, col)
  local before_cursor = line_text:sub(1, col)

  -- Check for variable context
  if before_cursor:match("%$[%w_]*$") then
    return "variable"
  end

  -- Check for namespace context
  if before_cursor:match("::[%w_:]*$") then
    return "namespace"
  end

  -- Check for package require context
  if before_cursor:match("package%s+require%s+[%w_]*$") then
    return "package"
  end

  return "command"
end
```

### Gathering Items

**From current file:**
- Parse buffer with existing parser
- Extract proc names from AST nodes
- Extract variable names from `set` and `variable` commands

**From project index:**
- Use existing `analyzer/indexer` module
- Get all indexed procs via `indexer.get_all_symbols()`

**From builtins:**
```lua
-- lua/tcl-lsp/data/builtins.lua
return {
  { name = "puts", type = "builtin" },
  { name = "set", type = "builtin" },
  { name = "if", type = "builtin" },
  -- ~80 total common TCL commands
}
```

**From packages:**
```lua
-- lua/tcl-lsp/data/packages.lua
return {
  "Tcl", "Tk", "http", "tls", "json", "sqlite3", "tdbc", ...
}
```

### Completion Item Format

```lua
{
  label = "format_date",      -- What user sees
  kind = "Function",          -- LSP CompletionItemKind
  detail = "proc",            -- Type label
  insertText = "format_date", -- What gets inserted
}
```

## Configuration

```lua
require("tcl-lsp").setup({
  completion = {
    enabled = true,
    trigger_length = 2,  -- Characters before triggering
  }
})
```

## Testing Strategy

### Unit Tests

- `get_completions` returns empty for empty buffer
- `get_completions` returns procs from current file
- `get_completions` returns variables after `$`
- `get_completions` filters to variables only in variable context
- `get_completions` filters to packages after `package require`
- `get_completions` includes builtins in command context
- `detect_context` identifies variable context
- `detect_context` identifies namespace context
- `detect_context` identifies package context
- Completion items have required fields

### Test Fixtures

- File with multiple procs and variables
- File using namespaces
- File with `package require` statements
