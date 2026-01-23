# Diagnostics Feature Design

**Date:** 2026-01-22
**Status:** Approved
**Scope:** Surface parser syntax errors as Neovim diagnostics on save

## Overview

Add LSP-style diagnostics that show parser errors in the editor. Diagnostics update when TCL/RVT files are saved.

## Architecture

```
BufWritePost event
       │
       ▼
diagnostics.check_buffer(bufnr)
       │
       ▼
parser.parse_with_errors(content, filepath)
       │
       ▼
Convert errors to vim.diagnostic format
       │
       ▼
vim.diagnostic.set(namespace, bufnr, diagnostics)
```

## File Changes

### New: `lua/tcl-lsp/features/diagnostics.lua`

```lua
local M = {}

local parser = require("tcl-lsp.parser")
local ns = nil  -- diagnostic namespace

function M.setup()
  ns = vim.api.nvim_create_namespace("tcl-lsp")

  -- Configure diagnostic display
  vim.diagnostic.config({
    virtual_text = { source = "if_many" },
    signs = true,
    underline = true,
  }, ns)

  -- Register autocmd
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("TclLspDiagnostics", { clear = true }),
    pattern = { "*.tcl", "*.rvt" },
    callback = function(args)
      M.check_buffer(args.buf)
    end,
  })
end

function M.check_buffer(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  local result = parser.parse_with_errors(content, filepath)
  local diagnostics = {}

  for _, err in ipairs(result.errors or {}) do
    table.insert(diagnostics, {
      lnum = (err.range and err.range.start_line or 1) - 1,  -- 0-indexed
      col = (err.range and err.range.start_col or 1) - 1,
      end_lnum = (err.range and err.range.end_line or 1) - 1,
      end_col = (err.range and err.range.end_col or 1) - 1,
      message = err.message or "Syntax error",
      severity = vim.diagnostic.severity.ERROR,
      source = "tcl-lsp",
    })
  end

  vim.diagnostic.set(ns, bufnr, diagnostics)
end

function M.clear(bufnr)
  if ns then
    vim.diagnostic.reset(ns, bufnr)
  end
end

return M
```

### Modified: `lua/tcl-lsp/parser/ast.lua`

Add new function that preserves error details:

```lua
function M.parse_with_errors(code, filepath)
  -- Handle empty/whitespace input
  if not code or code == "" or code:match("^%s*$") then
    return { ast = { type = "root", children = {} }, errors = {} }
  end

  local ast, err = execute_tcl_parser(code, filepath or "<string>")

  -- Parser execution failed
  if err then
    return { ast = nil, errors = {{ message = err }} }
  end

  -- Extract errors from AST if present
  local errors = {}
  if ast and ast.had_error then
    if ast.errors and type(ast.errors) == "table" then
      for _, error_node in ipairs(ast.errors) do
        if type(error_node) == "table" then
          table.insert(errors, {
            message = error_node.message,
            range = error_node.range,
          })
        end
      end
    end
  end

  return { ast = ast, errors = errors }
end
```

### Modified: `lua/tcl-lsp/init.lua`

```lua
-- Add require at top
local diagnostics = require "tcl-lsp.features.diagnostics"

-- In setup(), after hover.setup():
diagnostics.setup()
```

### Modified: `lua/tcl-lsp/parser/init.lua`

```lua
-- Add re-export
M.parse_with_errors = M.ast.parse_with_errors
```

## Error Format

**Parser error node:**
```lua
{
  type = "error",
  message = "Invalid if: expected 'if condition body'",
  range = { start_line = 5, start_col = 1, end_line = 5, end_col = 15 }
}
```

**Neovim diagnostic:**
```lua
{
  lnum = 4,           -- 0-indexed (parser line 5 → diagnostic line 4)
  col = 0,            -- 0-indexed
  end_lnum = 4,
  end_col = 14,
  message = "Invalid if: expected 'if condition body'",
  severity = vim.diagnostic.severity.ERROR,
  source = "tcl-lsp",
}
```

## User Experience

- Save `.tcl` or `.rvt` file → diagnostics appear
- Virtual text shows error message inline
- Signs appear in sign column
- Standard navigation: `]d` next, `[d` prev
- Float details: `vim.diagnostic.open_float()`
- Quickfix list: `:lua vim.diagnostic.setqflist()`

## Testing

Create `tests/lua/diagnostics_spec.lua`:
- Test error parsing and conversion
- Test clear functionality
- Test multiple errors in same file
- Test files with no errors (diagnostics cleared)

## Future Extensions

Not in scope but natural next steps:
- Undefined variable warnings (requires symbol analysis)
- Wrong argument count warnings (requires proc signature tracking)
- Real-time diagnostics on change (debounced)
