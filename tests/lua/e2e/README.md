# E2E Tests

End-to-end tests that verify the full LSP pipeline works.

## Philosophy

These tests are **happy-path only**:
- One test per implemented feature
- Minimal fixture (2 TCL files)
- Tests pass or fail cleanly (no warnings)
- Only use verified APIs

For edge case and adversarial testing, see unit tests in `tests/lua/features/`.

## Running Tests

```bash
make test-unit
```

Or run e2e tests specifically:

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/e2e/', {minimal_init = 'tests/minimal_init.lua'})" \
  -c "qa!"
```

## Test Coverage

| Feature | Test |
|---------|------|
| goto_definition | Jump from call to definition across files |
| find_references | Find all usages of a proc |
| hover | Show proc signature |
| rename | Rename proc across files |
| diagnostics | Valid file has no errors |
| workspace | Index directory and find symbols |

## Fixture

Tests use `tests/fixtures/simple/`:
- `math.tcl` - Defines `add` and `subtract` procs
- `main.tcl` - Uses the procs

This minimal fixture proves the full pipeline works without the complexity of edge cases.

## Adding Tests

When adding a new LSP feature:
1. Add a happy-path test here that proves the feature works
2. Add adversarial/edge-case tests in `tests/lua/features/`
