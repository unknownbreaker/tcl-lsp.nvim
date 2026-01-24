# Semantic Highlighting Design

**Date**: 2026-01-23
**Status**: Approved
**Feature**: Full semantic token support for TCL/RVT files

## Overview

Implement LSP semantic tokens to provide rich, meaning-based syntax highlighting for TCL and RVT files. Unlike regex-based highlighting, semantic tokens understand what code elements *are* — distinguishing user procs from builtins, tracking variable scope, and showing namespace context.

## Goals

1. **Distinguish variable types** — Locals vs globals vs upvars vs namespace variables
2. **Highlight proc calls** — Differentiate user procs from built-in commands
3. **Show scope visually** — Make namespace context clear
4. **Catch errors early** — Undefined symbols handled by diagnostics (separation of concerns)

## Architecture

### Components

```
lua/tcl-lsp/
├── features/
│   └── highlights.lua           # LSP handlers, setup, buffer management
├── analyzer/
│   └── semantic_tokens.lua      # Token extraction, type resolution
└── parser/
    └── rvt.lua                  # RVT block detection, HTML tokenization
```

### Data Flow

1. Editor requests semantic tokens via `textDocument/semanticTokens/full` or `/delta`
2. `highlights.lua` checks cached AST and index status
3. `semantic_tokens.lua` walks AST, extracting tokens with types and modifiers
4. For RVT files, `rvt.lua` identifies TCL blocks, delegates to token extractor
5. Tokens encoded in LSP format (relative positions, packed integers)
6. On edits, compute deltas against previous token set

### Hybrid Mode

**Immediate mode** (always available):
- Proc definitions, parameters, local variables
- Built-in commands, literals, syntax elements
- No cross-file awareness

**Enhanced mode** (when index ready):
- Cross-file proc call resolution
- Namespace variable tracking
- Global/upvar target resolution
- Exported proc detection

## Token Types

### Standard LSP Types (9)

| Type | TCL Usage | Example |
|------|-----------|---------|
| `function` | Proc definitions and calls | `proc foo {}`, `foo arg` |
| `variable` | Variable references | `$name`, `set name` |
| `namespace` | Namespace identifiers | `::myns`, `namespace eval myns` |
| `parameter` | Proc parameters | `proc foo {a b}` |
| `keyword` | TCL built-in commands | `if`, `set`, `proc`, `return` |
| `string` | String literals | `"hello"`, `{literal}` |
| `number` | Numeric literals | `42`, `3.14` |
| `comment` | Comments | `# this is a comment` |
| `operator` | Expr operators | `+`, `-`, `==`, `&&` |

### Custom Types (2)

| Type | TCL Usage | Example |
|------|-----------|---------|
| `macro` | Command substitution | `[expr 1+1]` — the brackets |
| `decorator` | Export declarations | `namespace export foo` |

### Custom Variable Sub-types

```
variable.local      # Default proc-local
variable.global     # Declared with 'global'
variable.upvar      # Declared with 'upvar'
variable.namespace  # Declared with 'variable' in namespace
variable.array      # Array element access $arr(key)
```

## Modifiers

| Modifier | Applied When |
|----------|--------------|
| `definition` | `proc foo {}` — foo is a definition |
| `declaration` | `variable x`, `global y`, `upvar z` |
| `defaultLibrary` | Built-in commands: `if`, `set`, `puts` |
| `modification` | `set x 5` — x is being modified |
| `readonly` | Loop variables in `foreach` |
| `deprecated` | Future: procs with `# @deprecated` comment |
| `async` | `coroutine`, `yield`, `yieldto` |

## Performance

### Delta Computation

```
State per buffer:
├── previous_tokens[]     # Last computed token list
├── previous_result_id    # Version identifier
└── ast_version           # Tracks when AST was last parsed
```

**Update flow**:
1. On edit: Buffer changes, AST re-parsed
2. On delta request: Compare new tokens against `previous_tokens`
3. Diff: Find changed region, return `deleteCount` + `insertedTokens`
4. Cache new state, increment `result_id`

### Debouncing

```lua
local DEBOUNCE_MS = 150  -- Wait 150ms after last keystroke
```

### Large File Handling

For files over 1000 lines:
- Parse in chunks using existing AST infrastructure
- Prioritize visible viewport region
- Background-compute tokens outside viewport

## RVT Template Support

### Block Types

| Syntax | Purpose | Highlighting |
|--------|---------|--------------|
| `<? ... ?>` | TCL code block | Full semantic tokens |
| `<?= ... ?>` | Output expression | Expression tokens |
| Outside blocks | HTML content | Basic HTML tokens |

### Processing Pipeline

1. `rvt.lua` scans for block boundaries
2. For each TCL block: extract, parse AST, run token extractor, offset positions
3. For HTML regions: simple regex tokenization (tag, attribute, string)
4. Merge all tokens, sort by position

### Variable Interpolation

Track `$var`, `${var}`, `$arr(key)` syntax across entire file, including within HTML regions and `<?= ?>` blocks.

## Index Integration

```lua
local function resolve_call(name, namespace)
  if indexer.get_status().status ~= "ready" then
    return nil  -- Fall back to immediate mode
  end
  return index.find(namespace .. "::" .. name)
end
```

### Graceful Degradation

| Index Status | Behavior |
|--------------|----------|
| `idle` | Immediate mode only |
| `scanning` | Immediate mode, queue refresh when ready |
| `ready` | Full enhanced mode |

When index transitions to `ready`, trigger full token refresh for open buffers.

## File Structure

### New Files

```
lua/tcl-lsp/
├── features/highlights.lua
├── analyzer/semantic_tokens.lua
└── parser/rvt.lua

tests/lua/
├── semantic_tokens_spec.lua
├── rvt_parser_spec.lua
└── highlights_integration_spec.lua

tests/fixtures/semantic/
├── simple_proc.tcl
├── namespaces.tcl
├── variable_types.tcl
└── template.rvt
```

### Testing Strategy

1. **Unit tests**: Token extraction returns correct types/modifiers per AST node
2. **Snapshot tests**: Known TCL files produce expected token sequences
3. **Integration tests**: Full LSP request/response with petshop fixtures
4. **Performance tests**: 1000+ line files complete under 100ms

## Configuration

```lua
require("tcl-lsp").setup({
  semantic_tokens = {
    enabled = true,
    debounce_ms = 150,
    large_file_threshold = 1000,
  }
})
```

## Implementation Order

1. `semantic_tokens.lua` — Core token extraction (immediate mode)
2. `highlights.lua` — LSP handlers and buffer management
3. Index integration — Enhanced mode with cross-file resolution
4. `rvt.lua` — RVT template support
5. Delta computation — Performance optimization
6. Large file handling — Viewport prioritization
