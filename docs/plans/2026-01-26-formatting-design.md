# TCL Code Formatting Design

**Date:** 2026-01-26
**Status:** Approved
**Phase:** 5

## Overview

Lua-based TCL code formatter that runs in-process for fast performance (<20ms). Uses the existing AST parser to understand code structure, then rebuilds with correct indentation.

## Scope

### What it formats:
- Indentation (auto-detect existing style, fallback to 4 spaces)
- Brace placement (same-line, TCL conventional)
- Trailing whitespace removal

### What it doesn't do (YAGNI):
- Line wrapping / max line length
- Blank line normalization
- Operator spacing changes
- Comment reformatting

### Triggers:
- On-demand via `:TclFormat` command
- On-save (configurable, default off)

## Architecture

### Data Flow

```
Buffer text → Parse AST (existing parser) → Walk AST → Rebuild text with correct indentation → Replace buffer
```

### Files

| File | Purpose | Est. Lines |
|------|---------|------------|
| `lua/tcl-lsp/features/formatting.lua` | Formatter implementation | 150-200 |
| `tests/lua/features/formatting_spec.lua` | Unit tests | 100-150 |

### Modified Files

| File | Change |
|------|--------|
| `lua/tcl-lsp/init.lua` | Register formatter, add setup call |
| `lua/tcl-lsp/config.lua` | Add formatting options |

### Public API

```lua
-- Format entire buffer
M.format_buffer(bufnr)

-- Format code string (for testing)
M.format_code(code, options)

-- Setup (registers commands, autocmds)
M.setup()
```

### Configuration

```lua
require("tcl-lsp").setup({
  formatting = {
    on_save = false,        -- Auto-format on save (default: off)
    indent_size = nil,      -- nil = auto-detect, or 2/4
    indent_style = nil,     -- nil = auto-detect, or "spaces"/"tabs"
  }
})
```

## Implementation Logic

### Indentation Detection

1. Scan first 100 lines for leading whitespace patterns
2. If tabs found → use tabs
3. If spaces found → count most common indent width (2 or 4)
4. If mixed/unclear → fall back to 4 spaces

### Formatting Algorithm

```
1. Parse code to AST (via existing parser)
2. If parse fails → return original code unchanged (don't break user's file)
3. Walk AST nodes in order:
   - Track current indent depth
   - Increase depth when entering: proc body, if/else body, loop body, namespace body
   - Decrease depth when exiting
4. Rebuild each line:
   - Strip existing leading whitespace
   - Apply correct indentation based on depth
   - Strip trailing whitespace
5. Return formatted code
```

### Edge Cases

- Syntax errors → Return original, don't format
- Empty file → Return empty
- Single-line constructs → Don't change indentation mid-line
- Continuation lines → Preserve relative indentation within multi-line strings

## Testing Strategy

### Unit Tests

- `format_code` returns empty for empty input
- `format_code` fixes incorrect proc indentation
- `format_code` fixes nested if/else indentation
- `format_code` removes trailing whitespace
- `format_code` preserves blank lines
- `format_code` handles syntax errors gracefully (returns original)
- `format_code` auto-detects 2-space indent
- `format_code` auto-detects 4-space indent
- `format_code` auto-detects tabs

### Integration Tests

- `:TclFormat` command exists and works
- Format on save (when enabled) triggers correctly
- Buffer is unchanged if already formatted

### Test Fixtures

- Badly indented proc
- Nested control flow
- Mixed indentation file
- File with trailing whitespace
- File with syntax error

## Performance

**Target:** <20ms for typical files

**Why it's fast:**
- Runs in Neovim's Lua runtime (no subprocess for formatting)
- AST parsing is the only subprocess call (already required)
- String manipulation in Lua is efficient
