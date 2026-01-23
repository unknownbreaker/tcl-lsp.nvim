# Diagnostics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Surface TCL parser syntax errors as Neovim diagnostics on file save.

**Architecture:** Parse buffer content via TCL parser, extract error nodes with ranges, convert to vim.diagnostic format, display via native Neovim diagnostic API.

**Tech Stack:** Lua, Neovim API, vim.diagnostic, plenary.nvim (tests)

---

## Task 1: Add parse_with_errors to Parser

**Files:**
- Modify: `lua/tcl-lsp/parser/ast.lua` (add function at end, before `return M`)
- Modify: `lua/tcl-lsp/parser/init.lua` (add re-export)

**Step 1: Write the failing test**

Create test in `tests/lua/parser_errors_spec.lua`:

```lua
describe("parser.parse_with_errors", function()
  local parser = require("tcl-lsp.parser")

  it("returns empty errors for valid code", function()
    local result = parser.parse_with_errors("set x 1", "test.tcl")
    assert.is_table(result)
    assert.is_table(result.errors)
    assert.equals(0, #result.errors)
    assert.is_table(result.ast)
  end)

  it("returns errors with ranges for invalid code", function()
    local result = parser.parse_with_errors("if", "test.tcl")
    assert.is_table(result)
    assert.is_table(result.errors)
    assert.is_true(#result.errors > 0)
    assert.is_string(result.errors[1].message)
  end)

  it("handles empty input", function()
    local result = parser.parse_with_errors("", "test.tcl")
    assert.is_table(result)
    assert.equals(0, #result.errors)
  end)

  it("handles whitespace-only input", function()
    local result = parser.parse_with_errors("   \n\n  ", "test.tcl")
    assert.is_table(result)
    assert.equals(0, #result.errors)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/robertyang/Documents/Repos/FlightAware/tcl-lsp.nvim/.worktrees/diagnostics
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/', {minimal_init = 'tests/minimal_init.lua', filter = 'parser_errors'})" \
  -c "qa!"
```

Expected: FAIL with "attempt to call field 'parse_with_errors' (a nil value)"

**Step 3: Write implementation in ast.lua**

Add before `return M` in `lua/tcl-lsp/parser/ast.lua`:

```lua
-- Parse TCL code and return AST with error details preserved
-- Unlike parse(), this always returns a result table, never nil
function M.parse_with_errors(code, filepath)
  -- Handle empty/whitespace input
  if not code or code == "" or code:match("^%s*$") then
    return {
      ast = {
        type = "root",
        children = {},
        range = { start = { line = 1, column = 1 }, end_pos = { line = 1, column = 1 } },
      },
      errors = {},
    }
  end

  -- Execute TCL parser
  local ast, err = execute_tcl_parser(code, filepath or "<string>")

  -- Parser execution failed (e.g., tclsh not found, timeout)
  if err then
    return { ast = nil, errors = { { message = err } } }
  end

  if not ast then
    return { ast = nil, errors = { { message = "Parser returned nil" } } }
  end

  -- Extract errors from AST if present
  local errors = {}
  if ast.had_error and (ast.had_error == 1 or ast.had_error == true) then
    if ast.errors and type(ast.errors) == "table" then
      for _, error_node in ipairs(ast.errors) do
        if type(error_node) == "table" then
          table.insert(errors, {
            message = error_node.message,
            range = error_node.range,
          })
        elseif type(error_node) == "string" then
          table.insert(errors, { message = error_node })
        end
      end
    elseif type(ast.errors) == "string" then
      table.insert(errors, { message = ast.errors })
    end
  end

  return { ast = ast, errors = errors }
end
```

**Step 4: Add re-export in init.lua**

Add to `lua/tcl-lsp/parser/init.lua` after line 14:

```lua
M.parse_with_errors = M.ast.parse_with_errors
```

**Step 5: Run test to verify it passes**

Run same command as Step 2.
Expected: PASS (all 4 tests)

**Step 6: Commit**

```bash
git add lua/tcl-lsp/parser/ast.lua lua/tcl-lsp/parser/init.lua tests/lua/parser_errors_spec.lua
git commit -m "feat(parser): add parse_with_errors for diagnostics support"
```

---

## Task 2: Create Diagnostics Module

**Files:**
- Create: `lua/tcl-lsp/features/diagnostics.lua`
- Test: `tests/lua/diagnostics_spec.lua` (adversarial tester creates this)

**Step 1: Write basic failing test**

The adversarial-tester agent is creating comprehensive tests. For TDD, add this minimal test to start:

```lua
-- tests/lua/diagnostics_spec.lua (append if file exists, create if not)
describe("diagnostics", function()
  local diagnostics

  before_each(function()
    package.loaded["tcl-lsp.features.diagnostics"] = nil
    diagnostics = require("tcl-lsp.features.diagnostics")
  end)

  describe("module structure", function()
    it("exports setup function", function()
      assert.is_function(diagnostics.setup)
    end)

    it("exports check_buffer function", function()
      assert.is_function(diagnostics.check_buffer)
    end)

    it("exports clear function", function()
      assert.is_function(diagnostics.clear)
    end)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run:
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/', {minimal_init = 'tests/minimal_init.lua', filter = 'diagnostics'})" \
  -c "qa!"
```

Expected: FAIL with module not found

**Step 3: Write minimal diagnostics.lua**

Create `lua/tcl-lsp/features/diagnostics.lua`:

```lua
-- lua/tcl-lsp/features/diagnostics.lua
-- Diagnostics feature - surfaces parser syntax errors

local parser = require("tcl-lsp.parser")

local M = {}

-- Diagnostic namespace (created in setup)
local ns = nil

-- Setup diagnostics feature
function M.setup()
  ns = vim.api.nvim_create_namespace("tcl-lsp")

  -- Configure diagnostic display
  vim.diagnostic.config({
    virtual_text = { source = "if_many" },
    signs = true,
    underline = true,
  }, ns)

  -- Register autocmd for on-save diagnostics
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("TclLspDiagnostics", { clear = true }),
    pattern = { "*.tcl", "*.rvt" },
    callback = function(args)
      M.check_buffer(args.buf)
    end,
  })
end

-- Check buffer for syntax errors and publish diagnostics
function M.check_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Ensure namespace exists
  if not ns then
    ns = vim.api.nvim_create_namespace("tcl-lsp")
  end

  -- Get buffer content
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok then
    return
  end

  local content = table.concat(lines, "\n")
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  -- Parse and get errors
  local result = parser.parse_with_errors(content, filepath)
  local diagnostics = {}

  for _, err in ipairs(result.errors or {}) do
    -- Convert 1-indexed parser lines to 0-indexed diagnostic lines
    local start_line = (err.range and err.range.start_line or 1) - 1
    local start_col = (err.range and err.range.start_col or 1) - 1
    local end_line = (err.range and err.range.end_line or err.range and err.range.start_line or 1) - 1
    local end_col = (err.range and err.range.end_col or err.range and err.range.start_col or 1) - 1

    -- Clamp to valid values
    start_line = math.max(0, start_line)
    start_col = math.max(0, start_col)
    end_line = math.max(0, end_line)
    end_col = math.max(0, end_col)

    table.insert(diagnostics, {
      lnum = start_line,
      col = start_col,
      end_lnum = end_line,
      end_col = end_col,
      message = err.message or "Syntax error",
      severity = vim.diagnostic.severity.ERROR,
      source = "tcl-lsp",
    })
  end

  vim.diagnostic.set(ns, bufnr, diagnostics)
end

-- Clear diagnostics for a buffer
function M.clear(bufnr)
  if ns then
    vim.diagnostic.reset(ns, bufnr)
  end
end

-- Get the namespace (for testing)
function M.get_namespace()
  return ns
end

return M
```

**Step 4: Run test to verify it passes**

Run same command as Step 2.
Expected: PASS (3 tests)

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/diagnostics.lua tests/lua/diagnostics_spec.lua
git commit -m "feat(diagnostics): add diagnostics module with on-save checking"
```

---

## Task 3: Register Diagnostics in Plugin Init

**Files:**
- Modify: `lua/tcl-lsp/init.lua`

**Step 1: Write failing test**

Add to a test file or use manual verification:

```lua
describe("tcl-lsp init", function()
  it("registers diagnostics feature", function()
    -- Reset
    package.loaded["tcl-lsp"] = nil
    package.loaded["tcl-lsp.features.diagnostics"] = nil

    local tcl_lsp = require("tcl-lsp")
    -- After setup, the diagnostics augroup should exist
    tcl_lsp.setup({})

    local augroups = vim.api.nvim_get_autocmds({ group = "TclLspDiagnostics" })
    assert.is_true(#augroups > 0, "TclLspDiagnostics augroup should exist")
  end)
end)
```

**Step 2: Verify it fails**

Run test - should fail because diagnostics.setup() isn't called yet.

**Step 3: Modify init.lua**

Add require at top (after line 8):

```lua
local diagnostics = require "tcl-lsp.features.diagnostics"
```

Add setup call in `M.setup()` function (after line 97, after `hover.setup()`):

```lua
  -- Set up diagnostics feature
  diagnostics.setup()
```

**Step 4: Verify it passes**

Run test - should pass.

**Step 5: Run full test suite**

```bash
make test
```

Expected: All tests pass.

**Step 6: Commit**

```bash
git add lua/tcl-lsp/init.lua
git commit -m "feat(init): register diagnostics feature in plugin setup"
```

---

## Task 4: Merge Adversarial Tests

**Files:**
- Modify: `tests/lua/diagnostics_spec.lua` (merge adversarial tests)

**Step 1: Review adversarial test output**

Check the adversarial-tester output file for comprehensive edge case tests.

**Step 2: Merge tests into diagnostics_spec.lua**

Combine the basic structure tests with the adversarial edge cases.

**Step 3: Run all tests**

```bash
make test
```

**Step 4: Fix any failing tests**

If adversarial tests reveal bugs, fix them in diagnostics.lua.

**Step 5: Commit**

```bash
git add tests/lua/diagnostics_spec.lua lua/tcl-lsp/features/diagnostics.lua
git commit -m "test(diagnostics): add adversarial edge case tests"
```

---

## Task 5: Manual Integration Test

**Step 1: Create test file with syntax error**

Create `/tmp/test_diag.tcl`:

```tcl
# Valid code
set x 1
proc hello {name} {
    puts "Hello $name"
}

# Invalid code - incomplete if
if
```

**Step 2: Open in Neovim and trigger diagnostics**

```bash
cd .worktrees/diagnostics
nvim /tmp/test_diag.tcl
```

In Neovim:
1. `:TclLspStart` - start the plugin
2. `:w` - save to trigger diagnostics
3. Verify error appears on line 9 (the `if` line)
4. `]d` - jump to diagnostic
5. `:lua vim.diagnostic.open_float()` - see details

**Step 3: Verify diagnostics clear on fix**

Edit the file to fix the error:

```tcl
if {1} { puts "yes" }
```

Save (`:w`) - diagnostics should clear.

**Step 4: Document result**

If working, proceed. If not, debug and fix.

---

## Task 6: Final Commit and Merge Prep

**Step 1: Run full test suite**

```bash
make test
```

**Step 2: Verify clean git status**

```bash
git status
git log --oneline main..HEAD
```

**Step 3: Squash or keep commits as-is**

Review commits - if they're clean, keep separate. If messy, squash.

**Step 4: Ready for merge**

The feature branch `feature/diagnostics` is ready for review/merge into main.

---

## Summary of Files Changed

| File | Action | Purpose |
|------|--------|---------|
| `lua/tcl-lsp/parser/ast.lua` | Modify | Add `parse_with_errors()` |
| `lua/tcl-lsp/parser/init.lua` | Modify | Re-export `parse_with_errors` |
| `lua/tcl-lsp/features/diagnostics.lua` | Create | Main diagnostics module |
| `lua/tcl-lsp/init.lua` | Modify | Register diagnostics in setup |
| `tests/lua/parser_errors_spec.lua` | Create | Parser error tests |
| `tests/lua/diagnostics_spec.lua` | Create | Diagnostics tests (adversarial) |
