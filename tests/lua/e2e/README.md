# E2E Adversarial Tests README

## Overview

This directory contains end-to-end adversarial tests for tcl-lsp.nvim using the petshop test fixture. The goal is to **break the LSP** by testing edge cases that naive implementations fail on.

## Files

- `petshop_spec.lua` - Main test suite (37 tests, 802 lines)
- `ATTACK_REPORT.md` - Detailed vulnerability report from test run
- `README.md` - This file

## Quick Start

### Run All E2E Tests
```bash
make test  # Runs all tests including e2e
```

### Run Only Petshop E2E Tests
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/e2e/', {minimal_init = 'tests/minimal_init.lua', filter = 'petshop'})" \
  -c "qa!"
```

### Run Specific Test Category
```bash
# Go-to-definition tests only
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/e2e/', {minimal_init = 'tests/minimal_init.lua', filter = 'Go-to-Definition'})" \
  -c "qa!"

# Diagnostics tests only
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/e2e/', {minimal_init = 'tests/minimal_init.lua', filter = 'Diagnostics'})" \
  -c "qa!"
```

### Run Single Test
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/e2e/', {minimal_init = 'tests/minimal_init.lua', filter = 'should find definition of proc'})" \
  -c "qa!"
```

## Test Fixture: Petshop

Location: `tests/fixtures/petshop/`

A deliberately complex TCL package designed to stress-test the LSP with edge cases:

### File Structure
```
petshop/
├── petshop.tcl          # Main entry, namespace ensemble
├── pkgIndex.tcl         # Package index with apply lambda
├── models/
│   ├── pet.tcl          # Nested procs, coroutines, interp alias
│   ├── customer.tcl     # upvar at levels 1 and 2, uplevel
│   └── inventory.tcl    # Variable traces, dynamic variables
├── services/
│   ├── events.tcl       # Callbacks, uplevel #0, {*} expansion
│   ├── pricing.tcl      # Nested expr, ternary, subst, eval
│   └── transactions.tcl # Cross-namespace calls
├── utils/
│   ├── config.tcl       # Multi-line strings, line continuations
│   └── logging.tcl      # Format strings, escapes
└── views/
    ├── pets/
    │   ├── list.rvt     # RVT with loops, conditionals
    │   └── detail.rvt   # RVT with embedded procs
    └── *.rvt            # More RVT templates
```

### Edge Cases Covered

**Namespace Complexity:**
- Fully-qualified names: `::petshop::models::pet::get`
- Namespace ensemble patterns
- Import/export chains

**Scoping:**
- upvar at levels 1 and 2
- uplevel with script execution
- Nested proc definitions

**Dynamic Code:**
- `set $varname` indirection
- eval and subst metaprogramming
- apply lambdas

**Advanced TCL:**
- Coroutines (yield, info coroutine)
- {*} expansion operator
- dict for loops
- Variable traces

**Multi-File:**
- Cross-file proc calls
- RVT templates
- Package index patterns

## Test Categories

### 1. Go-to-Definition (7 tests)
Tests ability to jump to symbol definitions across:
- Cross-namespace boundaries
- Nested scopes
- Name collisions
- Dynamic references

**Key Tests:**
- Cross-file fully-qualified namespace calls
- Ensemble subcommand resolution
- Nested proc definitions
- Variable/proc name collisions

### 2. Find-References (5 tests)
Tests ability to find all usages of a symbol:
- Cross-file references
- upvar contexts
- Namespace-scoped references
- RVT template references

### 3. Hover (4 tests)
Tests hover information quality:
- Default arguments
- Varargs parameters
- Namespace context
- Traced variables

### 4. Diagnostics (9 tests)
Tests for false positive errors on valid TCL:
- Multi-line strings
- Line continuations
- Ternary operators
- apply lambdas
- {*} expansion
- uplevel #0
- RVT syntax
- Coroutines

### 5. Rename (4 tests)
Tests symbol renaming across:
- Multiple files
- Namespace boundaries
- Name collisions
- upvar aliases

### 6. Performance (2 tests)
Ensures features complete in reasonable time:
- Go-to-definition < 1s
- Find-references < 2s

### 7. Regression (7 tests)
Parser robustness on known edge cases:
- namespace ensemble create
- dict for
- coroutines
- upvar 2
- subst/eval
- trace

## Understanding Test Output

### Success Example
```
[32mSuccess[0m || Test description
```

### Failure with Warning
```
[20:48:22] WARN: CRITICAL: Failed to resolve ::petshop::models::pet::get across files
[32mSuccess[0m || Test description
```
Note: Test passes but logs a warning about expected behavior not working.

### Actual Failure
```
[31mFail[0m || Test description
    Error message
    stack traceback:
```

### Severity Levels in Warnings
- **CRITICAL** - Blocks core functionality
- **HIGH** - Serious UX degradation
- **MEDIUM** - Feature limitation
- **LOW** - Nice-to-have

## Adding New Tests

### Test Structure
```lua
it("should [expected behavior]", function()
  -- Attack: [what edge case you're testing]
  -- [Why this is tricky/expected to fail]

  -- Index relevant files if needed
  index_files({ "models/pet.tcl", "services/transactions.tcl" })

  -- Open test file
  local file = petshop_dir .. "/path/to/file.tcl"
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  local bufnr = vim.api.nvim_get_current_buf()

  -- Call LSP feature
  local result = feature.handle_something(bufnr, line, col)

  -- Assert or warn
  if result then
    assert.is_not_nil(result.expected_field)
  else
    helpers.warn("CRITICAL: Feature failed on edge case X")
  end
end)
```

### Guidelines
1. **Name tests after the attack**, not the feature: "should handle X edge case"
2. **Document the attack** with comments explaining what makes it tricky
3. **Use warnings for soft failures** - let tests pass but log issues
4. **Test one edge case per test** - makes debugging easier
5. **Add comments with line numbers** from fixture files for reference

## Interpreting Results

### When Tests Pass But Warn
The feature exists but doesn't handle the edge case. This is expected - we're finding the limits of the implementation.

### When Tests Fail
The feature is broken or the API has changed. Check:
1. Is the API method still named the same?
2. Did the test fixture change?
3. Is this a new bug introduced by recent changes?

### When Tests Error
Infrastructure issue:
- Missing module
- Invalid API call
- Test harness problem

## Contributing

When adding LSP features:
1. Add adversarial tests FIRST
2. Run tests to see them fail
3. Implement feature
4. Run tests to see them pass
5. Add more edge case tests

## Troubleshooting

### Tests Hang
- Check if indexer is stuck
- Reduce timeout in `vim.wait()` calls
- Use `timeout` command when running tests

### Tests Crash
- Check for nil API calls
- Verify fixture files exist
- Check Neovim version (need 0.8+)

### False Failures
- Verify petshop fixture hasn't been modified
- Check if LSP API changed
- Review recent commits for breaking changes

## Performance Notes

Current baseline (should not regress):
- Go-to-definition: < 1000ms
- Find-references: < 2000ms
- Parser per file: < 100ms

If tests become slower, investigate:
- Indexer performance
- Parser caching
- Reference extraction optimization

## See Also

- `tests/fixtures/petshop/` - Test fixture source
- `ATTACK_REPORT.md` - Detailed vulnerability findings
- Main test suite: `tests/lua/`
- TCL parser tests: `tests/tcl/core/ast/`
