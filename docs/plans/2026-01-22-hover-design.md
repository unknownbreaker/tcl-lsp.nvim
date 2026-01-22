# Hover Feature Design

## Overview

Show rich information about TCL symbols (procs, variables) in a floating window when user presses `K`.

## Data Flow

```
User presses K on symbol
    ↓
Get word under cursor + parse buffer to AST
    ↓
Find symbol in index (cross-file) or AST (current file)
    ↓
Extract additional info:
  - For procs: params, preceding comments
  - For variables: initial value from `set` node
    ↓
Format as markdown
    ↓
Display in floating window via vim.lsp.util.open_floating_preview()
```

## Reuses Existing Infrastructure

- `tcl-lsp.parser` for AST parsing
- `tcl-lsp.parser.scope` for context
- `tcl-lsp.analyzer.definitions` for symbol lookup
- `tcl-lsp.analyzer.extractor` for symbol extraction

## New Modules

- `lua/tcl-lsp/features/hover.lua` - Feature entry point, keymap setup
- `lua/tcl-lsp/analyzer/docs.lua` - Comment extraction logic

## Markdown Output Format

### For Procedures

```markdown
```tcl
proc ::namespace::proc_name {arg1 arg2 {optional default}}
```

Description extracted from comments above the proc definition.
More comment lines if present.

**Location:** `lib/utils.tcl:42`
**Namespace:** `::namespace`
```

### For Variables

```markdown
```tcl
set ::config::timeout 30
```

**Type:** namespace variable
**Location:** `lib/config.tcl:15`
**Scope:** `::config`
```

### For Variables Without Initial Value

```markdown
**Variable:** `::config::debug_mode`

**Type:** namespace variable
**Location:** `lib/config.tcl:8`
```

### Scope Types

- "local variable" - inside a proc, not declared global/upvar
- "global variable" - declared with `global` command
- "namespace variable" - declared at namespace level or with `variable` command

## Comment Extraction Algorithm

1. Given a symbol's range (start line), walk backwards from `line - 1`
2. Collect consecutive lines that start with `#` (after trimming whitespace)
3. Stop when hitting a non-comment line or blank line
4. Reverse collected lines to restore original order
5. Strip leading `# ` from each line, join with newlines

### Example

```tcl
# This formats a date string according to the
# specified format. Returns empty string on error.
#
# Note: timezone is always UTC
proc format_date {date_str format} {
```

Extracts as:
```
This formats a date string according to the
specified format. Returns empty string on error.

Note: timezone is always UTC
```

### Edge Cases

- No comments above → show hover without description section
- Comments separated by blank line → only grab the contiguous block immediately above
- Inline comment on same line as proc → ignore (not a doc comment)

## Module API

### `lua/tcl-lsp/features/hover.lua`

```lua
M.handle_hover(bufnr, line, col) → string|nil  -- Returns markdown or nil
M.setup()                                       -- Registers keymap and command
```

### `lua/tcl-lsp/analyzer/docs.lua`

```lua
M.extract_comments(lines, end_line) → string|nil  -- Extract comment block above line
M.get_initial_value(ast, var_name) → string|nil   -- Find value from set node
```

## Integration

In `init.lua` setup():
```lua
require("tcl-lsp.features.hover").setup()
```

## Keymap & Command

- `K` mapped for `tcl` and `rvt` filetypes via FileType autocmd
- `:TclHover` command for discoverability
- Falls back gracefully if no symbol found

## Tests

### Unit Tests (`tests/lua/hover_spec.lua`)

- `extract_comments` returns nil for no comments
- `extract_comments` handles single-line comment
- `extract_comments` handles multi-line contiguous block
- `extract_comments` stops at blank line
- `get_initial_value` extracts value from `set var value`
- `get_initial_value` returns nil when variable not set
- `handle_hover` returns correct markdown for proc
- `handle_hover` returns correct markdown for variable
- `handle_hover` returns nil for unknown symbol

### Manual Testing Scenarios

1. Hover on proc with comments → shows signature + docs + location
2. Hover on proc without comments → shows signature + location (no description)
3. Hover on namespace variable → shows value + scope + location
4. Hover on local variable inside proc → shows "local variable"
5. Hover on unknown word → shows "No hover information"
