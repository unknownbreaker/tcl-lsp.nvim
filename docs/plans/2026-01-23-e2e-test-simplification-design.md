# E2E Test Simplification Design

**Date:** 2026-01-23
**Status:** Ready for implementation

## Problem

The current e2e tests in `tests/lua/e2e/petshop_spec.lua` are:
- Too adversarial (869 lines, 38 tests targeting edge cases)
- Using potentially hallucinated APIs
- Passing with warnings rather than truly validating functionality

## Goal

Replace adversarial e2e tests with simple happy-path tests that prove each LSP feature works end-to-end.

## Design

### Scope: 8 Happy-Path Tests

| Feature | Test Description |
|---------|------------------|
| goto_definition | Jump from proc call to definition in another file |
| find_references | Find all usages of a proc across 2 files |
| hover | Show signature for a proc |
| rename | Rename a proc and verify changes in 2 files |
| diagnostics | Parse a valid file with no errors |
| completion | Get proc name completions at a trigger point |
| formatting | Format and verify indentation is correct |
| workspace | Index a directory and find symbols |

### Fixture: Minimal 2-File Setup

```tcl
# tests/fixtures/simple/math.tcl
proc add {a b} { return [expr {$a + $b}] }
proc subtract {a b} { return [expr {$a - $b}] }
```

```tcl
# tests/fixtures/simple/main.tcl
source math.tcl
set result [add 1 2]
puts $result
```

### Test File Structure

```lua
-- tests/lua/e2e/lsp_spec.lua (~150 lines)

describe("LSP E2E: Happy Path", function()
  local definition_feature, references_feature, hover_feature
  local diagnostics_feature, rename_feature, completion_feature
  local formatting_feature, indexer, index_store
  local fixture_dir

  before_each(function()
    -- Load features fresh
    -- Point to simple fixture
    -- Clear and rebuild index
  end)

  after_each(function()
    -- Clean up buffers
  end)

  it("goto_definition: jumps to proc in another file", function()
    -- Open main.tcl, position on "add" in line 2
    -- Call handle_definition
    -- Assert: returns URI to math.tcl, line 1
  end)

  it("find_references: finds usages across files", function()
    -- Open math.tcl, position on "add" definition
    -- Call handle_references
    -- Assert: returns 2+ locations
  end)

  it("hover: shows proc signature", function()
    -- Open main.tcl, position on "add" call
    -- Call handle_hover
    -- Assert: result contains "proc add {a b}"
  end)

  it("rename: updates proc name in all files", function()
    -- Open math.tcl, position on "add" definition
    -- Call handle_rename with "sum"
    -- Assert: returns edits for both files
  end)

  it("diagnostics: no errors on valid file", function()
    -- Open main.tcl
    -- Call check_buffer
    -- Assert: vim.diagnostic.get() has no errors
  end)

  it("completion: suggests proc names", function()
    -- Open main.tcl, position after "["
    -- Call handle_completion
    -- Assert: results include "add" and "subtract"
  end)

  it("formatting: indents correctly", function()
    -- Create buffer with bad indentation
    -- Call handle_formatting
    -- Assert: edits fix indentation
  end)

  it("workspace: indexes directory", function()
    -- Call indexer.start(fixture_dir)
    -- Wait for completion
    -- Assert: index contains "add" and "subtract" symbols
  end)
end)
```

### Key Principles

1. **No warnings** — Tests either pass or fail
2. **No edge cases** — Just prove the feature works
3. **No performance assertions** — Separate concern
4. **Only verified APIs** — Use existing feature module methods

## File Changes

### Delete
- `tests/lua/e2e/petshop_spec.lua` (869 lines)
- `tests/lua/e2e/ATTACK_REPORT.md`

### Keep
- `tests/fixtures/petshop/` — Useful for future adversarial work
- `tests/lua/features/adversarial_hover_spec.lua` — Good unit-level tests
- `tests/lua/e2e/README.md` — Update to reflect new approach

### Create
- `tests/fixtures/simple/main.tcl`
- `tests/fixtures/simple/math.tcl`
- `tests/lua/e2e/lsp_spec.lua` (~150 lines)

### Update
- `tests/lua/e2e/README.md` — Document happy-path philosophy

## Comparison

| Aspect | Before | After |
|--------|--------|-------|
| Test count | 38 adversarial | 8 happy-path |
| Lines of code | ~900 | ~150 |
| Fixture complexity | Multi-file package | 2 simple files |
| Pass criteria | Pass with warnings | Pass or fail |
| API risk | Potentially hallucinated | Only verified APIs |

## Implementation Steps

1. Create `tests/fixtures/simple/` with math.tcl and main.tcl
2. Create `tests/lua/e2e/lsp_spec.lua` with 8 tests
3. Run tests to verify they pass
4. Delete `petshop_spec.lua` and `ATTACK_REPORT.md`
5. Update `README.md` with new philosophy
