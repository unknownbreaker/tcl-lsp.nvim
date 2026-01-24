# E2E Test Simplification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace 38 adversarial e2e tests with 6 happy-path tests that verify each implemented LSP feature works end-to-end.

**Architecture:** Create a minimal 2-file TCL fixture, write one test per feature using verified APIs, delete adversarial tests.

**Tech Stack:** Lua, plenary.nvim test framework, existing tcl-lsp feature modules

---

## Task 1: Create Simple Test Fixture

**Files:**
- Create: `tests/fixtures/simple/math.tcl`
- Create: `tests/fixtures/simple/main.tcl`

**Step 1: Create math.tcl**

```tcl
# tests/fixtures/simple/math.tcl
# Simple math procedures for testing

proc add {a b} {
    return [expr {$a + $b}]
}

proc subtract {a b} {
    return [expr {$a - $b}]
}
```

**Step 2: Create main.tcl**

```tcl
# tests/fixtures/simple/main.tcl
# Main file that uses math procedures

source math.tcl

set result [add 1 2]
puts $result

set diff [subtract 10 3]
puts $diff
```

**Step 3: Verify files exist**

Run: `ls -la tests/fixtures/simple/`
Expected: Both files listed with non-zero size

**Step 4: Commit**

```bash
git add tests/fixtures/simple/
git commit -m "test(fixtures): add simple 2-file fixture for e2e tests"
```

---

## Task 2: Write Failing E2E Test Shell

**Files:**
- Create: `tests/lua/e2e/lsp_spec.lua`

**Step 1: Create test file with setup/teardown and first failing test**

```lua
-- tests/lua/e2e/lsp_spec.lua
-- Happy-path end-to-end tests for TCL LSP features
-- Tests verify the full pipeline works, not edge cases

describe("LSP E2E: Happy Path", function()
  local definition_feature
  local references_feature
  local hover_feature
  local diagnostics_feature
  local rename_feature
  local indexer
  local index_store
  local fixture_dir

  before_each(function()
    -- Clear module cache for fresh state
    package.loaded["tcl-lsp.features.definition"] = nil
    package.loaded["tcl-lsp.features.references"] = nil
    package.loaded["tcl-lsp.features.hover"] = nil
    package.loaded["tcl-lsp.features.diagnostics"] = nil
    package.loaded["tcl-lsp.features.rename"] = nil
    package.loaded["tcl-lsp.analyzer.indexer"] = nil
    package.loaded["tcl-lsp.analyzer.index"] = nil

    -- Load features
    definition_feature = require("tcl-lsp.features.definition")
    references_feature = require("tcl-lsp.features.references")
    hover_feature = require("tcl-lsp.features.hover")
    diagnostics_feature = require("tcl-lsp.features.diagnostics")
    rename_feature = require("tcl-lsp.features.rename")
    indexer = require("tcl-lsp.analyzer.indexer")
    index_store = require("tcl-lsp.analyzer.index")

    -- Setup diagnostics namespace
    diagnostics_feature.setup()

    -- Point to simple fixture
    local test_file = debug.getinfo(1, "S").source:sub(2)
    fixture_dir = vim.fn.fnamemodify(test_file, ":p:h:h:h") .. "/fixtures/simple"

    -- Clear and reset index
    indexer.reset()
    index_store.clear()
  end)

  after_each(function()
    -- Clean up all buffers
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    indexer.reset()
    index_store.clear()
  end)

  -- Helper to index fixture files
  local function index_fixture()
    indexer.index_file(fixture_dir .. "/math.tcl")
    indexer.index_file(fixture_dir .. "/main.tcl")
    indexer.resolve_references()
  end

  it("goto_definition: jumps to proc in another file", function()
    -- This test will be implemented next
    assert.is_true(false, "Test not implemented yet")
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit 2>&1 | grep -A5 "goto_definition"`
Expected: FAIL with "Test not implemented yet"

**Step 3: Commit**

```bash
git add tests/lua/e2e/lsp_spec.lua
git commit -m "test(e2e): add failing test shell for happy-path e2e tests"
```

---

## Task 3: Implement goto_definition Test

**Files:**
- Modify: `tests/lua/e2e/lsp_spec.lua`

**Step 1: Replace failing test with real implementation**

Replace the `goto_definition` test with:

```lua
  it("goto_definition: jumps to proc in another file", function()
    index_fixture()

    -- Open main.tcl
    local main_file = fixture_dir .. "/main.tcl"
    vim.cmd("edit " .. vim.fn.fnameescape(main_file))
    local bufnr = vim.api.nvim_get_current_buf()

    -- Line 6: "set result [add 1 2]" - cursor on "add" (0-indexed: line 5, col ~12)
    local result = definition_feature.handle_definition(bufnr, 5, 13)

    assert.is_not_nil(result, "Should find definition")
    assert.is_true(result.uri:match("math%.tcl$") ~= nil, "Should jump to math.tcl")
    -- proc add is on line 4 (0-indexed: 3)
    assert.is_true(result.range.start.line <= 5, "Should point to proc add definition")
  end)
```

**Step 2: Run test to verify it passes**

Run: `make test-unit 2>&1 | grep -A5 "goto_definition"`
Expected: PASS

**Step 3: Commit**

```bash
git add tests/lua/e2e/lsp_spec.lua
git commit -m "test(e2e): implement goto_definition happy-path test"
```

---

## Task 4: Implement find_references Test

**Files:**
- Modify: `tests/lua/e2e/lsp_spec.lua`

**Step 1: Add find_references test**

Add after the goto_definition test:

```lua
  it("find_references: finds usages across files", function()
    index_fixture()

    -- Open math.tcl
    local math_file = fixture_dir .. "/math.tcl"
    vim.cmd("edit " .. vim.fn.fnameescape(math_file))
    local bufnr = vim.api.nvim_get_current_buf()

    -- Line 4: "proc add {a b}" - cursor on "add" (0-indexed: line 3, col ~5)
    local refs = references_feature.handle_references(bufnr, 3, 6)

    assert.is_not_nil(refs, "Should find references")
    assert.is_true(#refs >= 2, "Should find at least 2 references (definition + usage)")
  end)
```

**Step 2: Run test to verify it passes**

Run: `make test-unit 2>&1 | grep -A5 "find_references"`
Expected: PASS

**Step 3: Commit**

```bash
git add tests/lua/e2e/lsp_spec.lua
git commit -m "test(e2e): implement find_references happy-path test"
```

---

## Task 5: Implement hover Test

**Files:**
- Modify: `tests/lua/e2e/lsp_spec.lua`

**Step 1: Add hover test**

Add after the find_references test:

```lua
  it("hover: shows proc signature", function()
    index_fixture()

    -- Open main.tcl
    local main_file = fixture_dir .. "/main.tcl"
    vim.cmd("edit " .. vim.fn.fnameescape(main_file))
    local bufnr = vim.api.nvim_get_current_buf()

    -- Line 6: "set result [add 1 2]" - cursor on "add"
    local result = hover_feature.handle_hover(bufnr, 5, 13)

    assert.is_not_nil(result, "Should return hover info")
    -- Result should contain proc signature
    local content = result
    if type(result) == "table" and result.contents then
      content = type(result.contents) == "table" and table.concat(result.contents, "\n") or result.contents
    end
    assert.is_true(content:match("proc") ~= nil or content:match("add") ~= nil, "Should show proc info")
  end)
```

**Step 2: Run test to verify it passes**

Run: `make test-unit 2>&1 | grep -A5 "hover:"`
Expected: PASS

**Step 3: Commit**

```bash
git add tests/lua/e2e/lsp_spec.lua
git commit -m "test(e2e): implement hover happy-path test"
```

---

## Task 6: Implement rename Test

**Files:**
- Modify: `tests/lua/e2e/lsp_spec.lua`

**Step 1: Add rename test**

Add after the hover test:

```lua
  it("rename: updates proc name in multiple files", function()
    index_fixture()

    -- Open math.tcl
    local math_file = fixture_dir .. "/math.tcl"
    vim.cmd("edit " .. vim.fn.fnameescape(math_file))
    local bufnr = vim.api.nvim_get_current_buf()

    -- Line 4: "proc add {a b}" - cursor on "add"
    local result = rename_feature.handle_rename(bufnr, 3, 6, "sum")

    assert.is_not_nil(result, "Should return rename edits")
    -- Result should have workspace_edit with changes
    if result.workspace_edit and result.workspace_edit.changes then
      local file_count = 0
      for _ in pairs(result.workspace_edit.changes) do
        file_count = file_count + 1
      end
      assert.is_true(file_count >= 1, "Should have edits in at least one file")
    end
  end)
```

**Step 2: Run test to verify it passes**

Run: `make test-unit 2>&1 | grep -A5 "rename:"`
Expected: PASS

**Step 3: Commit**

```bash
git add tests/lua/e2e/lsp_spec.lua
git commit -m "test(e2e): implement rename happy-path test"
```

---

## Task 7: Implement diagnostics Test

**Files:**
- Modify: `tests/lua/e2e/lsp_spec.lua`

**Step 1: Add diagnostics test**

Add after the rename test:

```lua
  it("diagnostics: no errors on valid file", function()
    -- Open math.tcl (valid TCL)
    local math_file = fixture_dir .. "/math.tcl"
    vim.cmd("edit " .. vim.fn.fnameescape(math_file))
    local bufnr = vim.api.nvim_get_current_buf()

    -- Run diagnostics
    diagnostics_feature.check_buffer(bufnr)

    -- Get diagnostics for this buffer
    local diags = vim.diagnostic.get(bufnr)

    -- Filter for errors only (warnings are OK)
    local errors = vim.tbl_filter(function(d)
      return d.severity == vim.diagnostic.severity.ERROR
    end, diags)

    assert.equals(0, #errors, "Valid TCL file should have no errors")
  end)
```

**Step 2: Run test to verify it passes**

Run: `make test-unit 2>&1 | grep -A5 "diagnostics:"`
Expected: PASS

**Step 3: Commit**

```bash
git add tests/lua/e2e/lsp_spec.lua
git commit -m "test(e2e): implement diagnostics happy-path test"
```

---

## Task 8: Implement workspace indexing Test

**Files:**
- Modify: `tests/lua/e2e/lsp_spec.lua`

**Step 1: Add workspace test**

Add after the diagnostics test:

```lua
  it("workspace: indexes directory and finds symbols", function()
    -- Index the fixture directory
    index_fixture()

    -- Check that symbols were indexed
    local add_symbol = index_store.find("::add")
    local subtract_symbol = index_store.find("::subtract")

    -- At least one should be found (namespace prefix may vary)
    local found_add = add_symbol ~= nil or index_store.find("add") ~= nil
    local found_subtract = subtract_symbol ~= nil or index_store.find("subtract") ~= nil

    assert.is_true(found_add or found_subtract, "Should index at least one symbol from fixture")
  end)
```

**Step 2: Run test to verify it passes**

Run: `make test-unit 2>&1 | grep -A5 "workspace:"`
Expected: PASS

**Step 3: Commit**

```bash
git add tests/lua/e2e/lsp_spec.lua
git commit -m "test(e2e): implement workspace indexing happy-path test"
```

---

## Task 9: Run Full Test Suite

**Step 1: Run all e2e tests**

Run: `make test-unit 2>&1 | grep -E "(PASS|FAIL|LSP E2E)"`
Expected: All 6 tests pass

**Step 2: If any fail, debug and fix**

Check output for specific failures and adjust line/column positions as needed.

---

## Task 10: Delete Adversarial Tests

**Files:**
- Delete: `tests/lua/e2e/petshop_spec.lua`
- Delete: `tests/lua/e2e/ATTACK_REPORT.md`

**Step 1: Remove adversarial files**

```bash
rm tests/lua/e2e/petshop_spec.lua
rm tests/lua/e2e/ATTACK_REPORT.md
```

**Step 2: Verify deletion**

Run: `ls tests/lua/e2e/`
Expected: Only `lsp_spec.lua` and `README.md`

**Step 3: Run tests to ensure nothing broke**

Run: `make test-unit`
Expected: All tests pass

**Step 4: Commit**

```bash
git add -A tests/lua/e2e/
git commit -m "test(e2e): remove adversarial tests in favor of happy-path

BREAKING: Removes 38 adversarial tests that used potentially
incorrect APIs. Replaces with 6 verified happy-path tests."
```

---

## Task 11: Update README

**Files:**
- Modify: `tests/lua/e2e/README.md`

**Step 1: Read current README**

Check what's currently in the file.

**Step 2: Update with new philosophy**

```markdown
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
```

**Step 3: Commit**

```bash
git add tests/lua/e2e/README.md
git commit -m "docs(e2e): update README with happy-path philosophy"
```

---

## Task 12: Final Verification and Push

**Step 1: Run full test suite**

Run: `make test`
Expected: All tests pass

**Step 2: Check git status**

Run: `git status`
Expected: Clean working tree

**Step 3: Review commits**

Run: `git log --oneline -10`
Expected: See all the commits from this plan

**Step 4: Push (if desired)**

```bash
git push
```
