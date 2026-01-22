# Find References Design

**Date:** 2026-01-22
**Status:** Approved
**Feature:** LSP Find References for TCL

## Overview

From any proc, namespace, or variable, find all references grouped by type: definition, exports, and call sites.

### User Experience

- Press `gr` on a symbol in a TCL/RVT file
- Telescope picker opens (or quickfix if Telescope unavailable)
- Results grouped and labeled:
  ```
  [def]    utils.tcl:15      proc ::utils::formatDate {date} {
  [export] utils.tcl:42      namespace export formatDate
  [call]   main.tcl:78       set result [::utils::formatDate $today]
  [call]   report.tcl:23     ::utils::formatDate [clock seconds]
  ```
- Select an entry to jump to that location
- Preview pane shows surrounding context

### Supported Reference Types

1. **Definition** - `proc`, `variable`, `namespace eval`
2. **Exports** - `namespace export`, `interp alias`
3. **Calls** - Direct invocations, command references in brackets

### Out of Scope (v1)

- Dynamic references (`$cmd` where cmd holds a proc name)
- References in strings (`"formatDate"`)
- Cross-project references (only indexed files)
- `rename oldProc newProc` (aliasing)
- `trace add command` (observers)
- Variable references via `upvar`/`global`

## Architecture

### New Components

```
lua/tcl-lsp/
├── analyzer/
│   └── references.lua    # Reference finder, queries symbol index
└── features/
    └── references.lua    # Keymap, command, Telescope/quickfix UI
```

### Data Flow

1. User presses `gr` → `features/references.lua` captures cursor position
2. Gets word under cursor, calls `analyzer/references.find_references(bufnr, line, col)`
3. Analyzer queries the symbol index for:
   - Definition (already tracked by existing `definitions.lua`)
   - Exports (scan for `namespace export` containing the symbol)
   - Calls (scan for symbol invocations across indexed files)
4. Results returned as list with `type`, `uri`, `range`, `text` fields
5. Sorted by type (def → export → call), then by file/line within each group
6. Displayed via Telescope if available, otherwise quickfix

### Extending the Symbol Index

The existing symbol index tracks definitions. We add:
- `references` field: list of `{type, uri, range}` for each symbol
- Populated during background indexing (same pass that finds definitions)

References are pre-computed, so `gr` is instant—no scanning at request time.

## Reference Detection

### Definitions (already implemented)

- `proc ::name` → procedure definition
- `variable name` → variable in namespace/proc scope
- `namespace eval ::name` → namespace definition

### Exports (new detection)

```tcl
namespace export formatDate validateInput  # space-separated list
namespace export *                         # wildcard (skip, too broad)
interp alias {} ::shortName {} ::full::name
```

- Parse `namespace export` arguments, match against symbol name
- Parse `interp alias` target (4th argument) for aliased procs

### Calls (new detection)

```tcl
::utils::formatDate $arg           # fully qualified
formatDate $arg                    # after namespace import
[formatDate $arg]                  # nested in brackets
set cmd formatDate; $cmd $arg      # skip (dynamic, out of scope for v1)
```

- Scan for symbol as first word of a command
- Handle both qualified (`::ns::proc`) and unqualified (`proc`) forms
- Match unqualified calls only when in same namespace or after `namespace import`

## Display & UI

### Telescope Picker

```lua
-- Entry format with type prefix and syntax highlighting
{
  display = "[def]    utils.tcl:15    proc ::utils::formatDate {date} {",
  ordinal = "utils.tcl formatDate",  -- for fuzzy search
  filename = "utils.tcl",
  lnum = 15,
  col = 0,
  type = "definition",  -- for grouping/highlighting
}
```

- Type prefix colored: `[def]` green, `[export]` yellow, `[call]` blue
- Preview pane shows file context around the reference
- Results pre-sorted (definition → exports → calls)

### Quickfix Fallback

```vim
utils.tcl|15 col 1| [def] proc ::utils::formatDate {date} {
utils.tcl|42 col 3| [export] namespace export formatDate
main.tcl|78 col 5| [call] set result [::utils::formatDate $today]
```

- Standard quickfix format, navigable with `:cnext`/`:cprev`
- Type prefix in text for visual grouping

### User Command

`:TclFindReferences` — works from command mode, same behavior as `gr`

### Empty Results

- No references found: `vim.notify("No references found", vim.log.levels.INFO)`
- Symbol not recognized: `vim.notify("Symbol not indexed", vim.log.levels.WARN)`

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Cursor not on a word | "No symbol under cursor" notification |
| Symbol not in index | "Symbol not indexed" warning |
| No references found | "No references found" info |
| File deleted since indexing | Skip that reference, show others |
| Telescope not installed | Fall back to quickfix silently |
| Index not ready (still building) | "Indexing in progress, try again" |

All errors handled gracefully with user-friendly messages. No crashes.

## Testing Strategy

### Unit Tests (`tests/lua/analyzer/references_spec.lua`)

- `find_references` returns definition for a proc
- `find_references` returns exports for `namespace export`
- `find_references` returns call sites across multiple files
- Results sorted by type: definition → export → call
- Returns empty list for unknown symbol
- Handles qualified (`::ns::proc`) and unqualified (`proc`) names

### Integration Test (`tests/integration/references_spec.lua`)

Test fixture with multiple files:
```
test_project/
├── utils.tcl      # defines ::utils::formatDate, exports it
├── main.tcl       # calls ::utils::formatDate
└── report.tcl     # calls formatDate after namespace import
```

Verify `gr` on `formatDate` returns all three reference types in correct order.

### Manual Test Checklist

- [ ] `gr` on proc name opens Telescope with grouped results
- [ ] Selecting entry jumps to correct location
- [ ] Works without Telescope (falls back to quickfix)
- [ ] `gr` on undefined symbol shows "not indexed" message
- [ ] Works in both `.tcl` and `.rvt` files

## Summary

| Aspect | Decision |
|--------|----------|
| Scope | Definitions + exports + calls |
| Ordering | By type (def → export → call) |
| Keymap | `gr` |
| Display | Telescope with quickfix fallback |
| Detection | Proc calls, namespace export, interp alias |
| Deferred | Dynamic refs, rename, upvar/global |
