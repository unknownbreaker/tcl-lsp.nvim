# Rename Feature Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement multi-file symbol rename for TCL LSP, supporting procedures, variables, and namespaces.

**Architecture:** Build on existing find-references infrastructure. New `rename.lua` module handles validation, conflict detection, and workspace edit generation. Integrates with `init.lua` for command registration.

**Tech Stack:** Lua, Neovim API, plenary.nvim for testing

---

## Task 1: Add Regression Tests for Find-References

Lock down existing behavior before adding rename functionality.

**Files:**
- Modify: `tests/lua/features/references_spec.lua`

**Step 1: Add regression test for find_references API**

Add this test at the end of the `describe("integration"` block (before the closing `end)`):

```lua
    it("should return consistent structure for regression", function()
      -- This test locks down the API contract
      vim.cmd("edit " .. main_file)
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_win_set_cursor(0, { 1, 5 }) -- On "hello" proc definition

      local refs = references_feature.handle_references(bufnr, 0, 5)

      -- If refs returned, verify structure
      if refs and #refs > 0 then
        local ref = refs[1]
        assert.is_not_nil(ref.type, "Reference should have type")
        assert.is_not_nil(ref.file, "Reference should have file")
        assert.is_not_nil(ref.range, "Reference should have range")
        assert.is_not_nil(ref.range.start, "Range should have start")
        assert.is_not_nil(ref.range.start.line, "Range start should have line")
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
```

**Step 2: Run test to verify it passes**

Run:
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/features/', {minimal_init = 'tests/minimal_init.lua', filter = 'references'})" \
  -c "qa!"
```

Expected: PASS

**Step 3: Commit**

```bash
git add tests/lua/features/references_spec.lua
git commit -m "test(references): add regression tests for API contract"
```

---

## Task 2: Create Rename Module with Validation

**Files:**
- Create: `lua/tcl-lsp/features/rename.lua`
- Create: `tests/lua/features/rename_spec.lua`

**Step 1: Write failing test for validation**

Create `tests/lua/features/rename_spec.lua`:

```lua
-- tests/lua/features/rename_spec.lua
-- Tests for rename feature

describe("Rename Feature", function()
  local rename

  before_each(function()
    package.loaded["tcl-lsp.features.rename"] = nil
    rename = require("tcl-lsp.features.rename")
  end)

  describe("validate_name", function()
    it("should reject empty names", function()
      local ok, err = rename.validate_name("")
      assert.is_false(ok)
      assert.matches("empty", err)
    end)

    it("should reject whitespace-only names", function()
      local ok, err = rename.validate_name("   ")
      assert.is_false(ok)
      assert.matches("empty", err)
    end)

    it("should reject names with spaces", function()
      local ok, err = rename.validate_name("my proc")
      assert.is_false(ok)
      assert.matches("invalid", err:lower())
    end)

    it("should accept valid identifier", function()
      local ok, err = rename.validate_name("myProc")
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("should accept underscores", function()
      local ok, err = rename.validate_name("my_proc_name")
      assert.is_true(ok)
    end)

    it("should accept namespaced names", function()
      local ok, err = rename.validate_name("::utils::helper")
      assert.is_true(ok)
    end)

    it("should reject special characters", function()
      local ok, err = rename.validate_name("proc@name")
      assert.is_false(ok)
    end)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run:
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/features/', {minimal_init = 'tests/minimal_init.lua', filter = 'rename'})" \
  -c "qa!"
```

Expected: FAIL (module not found)

**Step 3: Write minimal implementation**

Create `lua/tcl-lsp/features/rename.lua`:

```lua
-- lua/tcl-lsp/features/rename.lua
-- Rename feature for TCL LSP

local M = {}

--- Validate a new symbol name
---@param name string The proposed new name
---@return boolean ok True if valid
---@return string|nil error Error message if invalid
function M.validate_name(name)
  -- Check empty
  if not name or name:match("^%s*$") then
    return false, "Name cannot be empty"
  end

  -- Trim whitespace
  name = name:gsub("^%s+", ""):gsub("%s+$", "")

  -- TCL identifiers: alphanumeric, underscore, and :: for namespaces
  -- Pattern: start with letter/underscore, then alphanumeric/underscore/::
  if not name:match("^[%a_:][%w_:]*$") then
    return false, "Invalid identifier: must contain only letters, numbers, underscores, and :: for namespaces"
  end

  -- Check for invalid :: usage (not at boundaries)
  if name:match("[^:]::[^:]") == nil and name:match(":::") then
    return false, "Invalid namespace separator"
  end

  return true, nil
end

return M
```

**Step 4: Run test to verify it passes**

Run:
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/features/', {minimal_init = 'tests/minimal_init.lua', filter = 'rename'})" \
  -c "qa!"
```

Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/rename.lua tests/lua/features/rename_spec.lua
git commit -m "feat(rename): add rename module with name validation"
```

---

## Task 3: Add Conflict Detection

**Files:**
- Modify: `lua/tcl-lsp/features/rename.lua`
- Modify: `tests/lua/features/rename_spec.lua`

**Step 1: Write failing test for conflict detection**

Add to `tests/lua/features/rename_spec.lua` after the `validate_name` describe block:

```lua
  describe("check_conflicts", function()
    local index

    before_each(function()
      package.loaded["tcl-lsp.analyzer.index"] = nil
      index = require("tcl-lsp.analyzer.index")
      index.clear()
    end)

    it("should detect conflict when name exists in same scope", function()
      -- Add existing symbol
      index.add_symbol({
        qualified_name = "::existingProc",
        name = "existingProc",
        type = "proc",
        file = "/test.tcl",
        scope = "::",
      })

      local has_conflict, msg = rename.check_conflicts("newName", "::", "existingProc")
      assert.is_false(has_conflict) -- No conflict with different name

      has_conflict, msg = rename.check_conflicts("existingProc", "::", "oldName")
      assert.is_true(has_conflict)
      assert.matches("existingProc", msg)
    end)

    it("should not conflict with same name in different scope", function()
      index.add_symbol({
        qualified_name = "::other::existingProc",
        name = "existingProc",
        type = "proc",
        file = "/test.tcl",
        scope = "::other",
      })

      local has_conflict = rename.check_conflicts("existingProc", "::", "oldName")
      assert.is_false(has_conflict)
    end)

    it("should not conflict when renaming to same name", function()
      index.add_symbol({
        qualified_name = "::myProc",
        name = "myProc",
        type = "proc",
        file = "/test.tcl",
        scope = "::",
      })

      -- Renaming myProc to myProc (same name) - current symbol itself
      local has_conflict = rename.check_conflicts("myProc", "::", "myProc")
      assert.is_false(has_conflict)
    end)
  end)
```

**Step 2: Run test to verify it fails**

Run:
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/features/', {minimal_init = 'tests/minimal_init.lua', filter = 'rename'})" \
  -c "qa!"
```

Expected: FAIL (check_conflicts not defined)

**Step 3: Implement conflict detection**

Add to `lua/tcl-lsp/features/rename.lua` before `return M`:

```lua
local index = require("tcl-lsp.analyzer.index")

--- Check if new name conflicts with existing symbols in scope
---@param new_name string The proposed new name
---@param scope string The scope to check (e.g., "::" or "::namespace")
---@param current_name string The current symbol name (to exclude from conflict check)
---@return boolean has_conflict True if conflict exists
---@return string|nil message Conflict description
function M.check_conflicts(new_name, scope, current_name)
  -- If renaming to same name, no conflict
  if new_name == current_name then
    return false, nil
  end

  -- Build qualified name to check
  local qualified_to_check
  if scope == "::" then
    qualified_to_check = "::" .. new_name
  else
    qualified_to_check = scope .. "::" .. new_name
  end

  -- Check if symbol exists
  local existing = index.find(qualified_to_check)
  if existing then
    return true, string.format("Symbol '%s' already exists in scope %s", new_name, scope)
  end

  return false, nil
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/features/', {minimal_init = 'tests/minimal_init.lua', filter = 'rename'})" \
  -c "qa!"
```

Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/rename.lua tests/lua/features/rename_spec.lua
git commit -m "feat(rename): add conflict detection for existing symbols"
```

---

## Task 4: Implement Core Rename Logic

**Files:**
- Modify: `lua/tcl-lsp/features/rename.lua`
- Modify: `tests/lua/features/rename_spec.lua`

**Step 1: Write failing test for rename execution**

Add to `tests/lua/features/rename_spec.lua`:

```lua
  describe("prepare_workspace_edit", function()
    it("should generate workspace edit from references", function()
      local refs = {
        {
          type = "definition",
          file = "/project/utils.tcl",
          range = { start = { line = 5, col = 6 }, end_pos = { line = 5, col = 11 } },
          text = "proc hello",
        },
        {
          type = "call",
          file = "/project/main.tcl",
          range = { start = { line = 10, col = 4 }, end_pos = { line = 10, col = 9 } },
          text = "hello",
        },
      }

      local edit = rename.prepare_workspace_edit(refs, "hello", "greet")

      assert.is_not_nil(edit)
      assert.is_not_nil(edit.changes)
      assert.equals(2, vim.tbl_count(edit.changes)) -- 2 files
    end)

    it("should handle empty references", function()
      local edit = rename.prepare_workspace_edit({}, "old", "new")
      assert.is_not_nil(edit)
      assert.equals(0, vim.tbl_count(edit.changes or {}))
    end)

    it("should calculate correct text edit ranges", function()
      local refs = {
        {
          type = "definition",
          file = "/test.tcl",
          range = { start = { line = 1, col = 6 }, end_pos = { line = 1, col = 11 } },
          text = "proc hello",
        },
      }

      local edit = rename.prepare_workspace_edit(refs, "hello", "world")
      local file_edits = edit.changes[vim.uri_from_fname("/test.tcl")]

      assert.is_not_nil(file_edits)
      assert.equals(1, #file_edits)
      assert.equals("world", file_edits[1].newText)
    end)
  end)
```

**Step 2: Run test to verify it fails**

Run:
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/features/', {minimal_init = 'tests/minimal_init.lua', filter = 'rename'})" \
  -c "qa!"
```

Expected: FAIL (prepare_workspace_edit not defined)

**Step 3: Implement workspace edit generation**

Add to `lua/tcl-lsp/features/rename.lua` before `return M`:

```lua
--- Prepare workspace edit from references
---@param refs table List of references from find-references
---@param old_name string The current symbol name
---@param new_name string The new symbol name
---@return table workspace_edit LSP WorkspaceEdit structure
function M.prepare_workspace_edit(refs, old_name, new_name)
  local changes = {}

  for _, ref in ipairs(refs) do
    local uri = vim.uri_from_fname(ref.file)

    if not changes[uri] then
      changes[uri] = {}
    end

    -- Calculate the edit range
    -- Range is 0-indexed for LSP, but our refs use 1-indexed lines
    local start_line = (ref.range and ref.range.start and ref.range.start.line or 1) - 1
    local start_col = ref.range and ref.range.start and (ref.range.start.col or ref.range.start.column or 1) or 1

    -- Find where the symbol name starts in the text
    local text = ref.text or ""
    local name_start = text:find(old_name, 1, true)
    if name_start then
      start_col = start_col + name_start - 1
    end

    local end_col = start_col + #old_name

    table.insert(changes[uri], {
      range = {
        start = { line = start_line, character = start_col - 1 },
        ["end"] = { line = start_line, character = end_col - 1 },
      },
      newText = new_name,
    })
  end

  return { changes = changes }
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/features/', {minimal_init = 'tests/minimal_init.lua', filter = 'rename'})" \
  -c "qa!"
```

Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/rename.lua tests/lua/features/rename_spec.lua
git commit -m "feat(rename): add workspace edit generation from references"
```

---

## Task 5: Implement Handle Rename (Main Entry Point)

**Files:**
- Modify: `lua/tcl-lsp/features/rename.lua`
- Modify: `tests/lua/features/rename_spec.lua`

**Step 1: Write failing test for handle_rename**

Add to `tests/lua/features/rename_spec.lua`:

```lua
  describe("handle_rename", function()
    local helpers = require("tests.spec.test_helpers")
    local temp_dir
    local main_file

    before_each(function()
      package.loaded["tcl-lsp.analyzer.index"] = nil
      local idx = require("tcl-lsp.analyzer.index")
      idx.clear()

      temp_dir = helpers.create_temp_dir("rename_test")
      main_file = temp_dir .. "/main.tcl"
      helpers.write_file(main_file, [[
proc hello {} {
    puts "Hello"
}

hello
]])
    end)

    after_each(function()
      helpers.cleanup_temp_dir(temp_dir)
    end)

    it("should return error for invalid new name", function()
      vim.cmd("edit " .. main_file)
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_win_set_cursor(0, { 1, 5 })

      local result = rename.handle_rename(bufnr, 0, 5, "invalid name")

      assert.is_not_nil(result.error)
      assert.matches("invalid", result.error:lower())

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should return error when not on a symbol", function()
      vim.cmd("edit " .. main_file)
      local bufnr = vim.api.nvim_get_current_buf()

      -- Position on empty/whitespace
      local result = rename.handle_rename(bufnr, 2, 0, "newName")

      -- Should handle gracefully
      assert.is_table(result)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
```

**Step 2: Run test to verify it fails**

Run:
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/features/', {minimal_init = 'tests/minimal_init.lua', filter = 'rename'})" \
  -c "qa!"
```

Expected: FAIL (handle_rename not defined)

**Step 3: Implement handle_rename**

Add to `lua/tcl-lsp/features/rename.lua` before `return M`:

```lua
local references_feature = require("tcl-lsp.features.references")

--- Handle rename request
---@param bufnr number Buffer number
---@param line number Line number (0-indexed)
---@param col number Column number (0-indexed)
---@param new_name string The new name for the symbol
---@return table result Contains either workspace_edit or error
function M.handle_rename(bufnr, line, col, new_name)
  -- Validate new name
  local valid, err = M.validate_name(new_name)
  if not valid then
    return { error = err }
  end

  -- Get current word
  local word = vim.fn.expand("<cword>")
  if not word or word == "" then
    return { error = "No symbol under cursor" }
  end

  -- Strip $ prefix from variables
  if word:sub(1, 1) == "$" then
    word = word:sub(2)
  end

  -- Check if new name is same as old
  if word == new_name then
    return { error = "New name is the same as current name" }
  end

  -- Get all references using existing infrastructure
  local refs = references_feature.handle_references(bufnr, line, col)
  if not refs or #refs == 0 then
    return { error = "Cannot rename: no references found for symbol '" .. word .. "'" }
  end

  -- Check for conflicts (get scope from first reference which is the definition)
  local scope = "::" -- Default to global scope
  -- TODO: Extract actual scope from symbol context

  local has_conflict, conflict_msg = M.check_conflicts(new_name, scope, word)
  if has_conflict then
    return { error = conflict_msg, conflict = true }
  end

  -- Generate workspace edit
  local workspace_edit = M.prepare_workspace_edit(refs, word, new_name)

  return {
    workspace_edit = workspace_edit,
    old_name = word,
    new_name = new_name,
    count = #refs,
  }
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/features/', {minimal_init = 'tests/minimal_init.lua', filter = 'rename'})" \
  -c "qa!"
```

Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/rename.lua tests/lua/features/rename_spec.lua
git commit -m "feat(rename): add handle_rename entry point"
```

---

## Task 6: Add Setup and User Command

**Files:**
- Modify: `lua/tcl-lsp/features/rename.lua`
- Modify: `lua/tcl-lsp/init.lua`
- Modify: `tests/lua/features/rename_spec.lua`

**Step 1: Write failing test for setup**

Add to `tests/lua/features/rename_spec.lua` at the beginning (after the `before_each`):

```lua
  describe("setup", function()
    it("should register without error", function()
      local success = pcall(rename.setup)
      assert.is_true(success)
    end)

    it("should create TclLspRename user command", function()
      rename.setup()

      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands.TclLspRename, "TclLspRename command should be registered")
    end)
  end)
```

**Step 2: Run test to verify it fails**

Run:
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/features/', {minimal_init = 'tests/minimal_init.lua', filter = 'rename'})" \
  -c "qa!"
```

Expected: FAIL (setup not defined)

**Step 3: Implement setup with user command**

Add to `lua/tcl-lsp/features/rename.lua` before `return M`:

```lua
--- Execute rename with UI
---@param new_name string|nil Optional new name (prompts if nil)
local function execute_rename(new_name)
  local bufnr = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = pos[1] - 1 -- Convert to 0-indexed
  local col = pos[2]
  local old_word = vim.fn.expand("<cword>")

  local function do_rename(name)
    if not name or name == "" then
      return
    end

    local result = M.handle_rename(bufnr, line, col, name)

    if result.error then
      if result.conflict then
        -- Ask user to confirm despite conflict
        vim.ui.select({ "Yes", "No" }, {
          prompt = result.error .. ". Rename anyway?",
        }, function(choice)
          if choice == "Yes" then
            -- Force rename by bypassing conflict check
            local refs = require("tcl-lsp.features.references").handle_references(bufnr, line, col)
            if refs then
              local edit = M.prepare_workspace_edit(refs, old_word, name)
              vim.lsp.util.apply_workspace_edit(edit, "utf-8")
              vim.notify(string.format("Renamed '%s' to '%s'", old_word, name), vim.log.levels.INFO)
            end
          end
        end)
      else
        vim.notify("Rename failed: " .. result.error, vim.log.levels.ERROR)
      end
      return
    end

    -- Apply the workspace edit
    vim.lsp.util.apply_workspace_edit(result.workspace_edit, "utf-8")

    -- Count affected files
    local file_count = vim.tbl_count(result.workspace_edit.changes or {})
    vim.notify(
      string.format("Renamed '%s' to '%s' in %d files (%d occurrences)",
        result.old_name, result.new_name, file_count, result.count),
      vim.log.levels.INFO
    )
  end

  if new_name then
    do_rename(new_name)
  else
    vim.ui.input({
      prompt = "New name: ",
      default = old_word,
    }, do_rename)
  end
end

--- Set up rename feature
function M.setup()
  -- Create user command
  vim.api.nvim_create_user_command("TclLspRename", function(opts)
    local new_name = opts.args ~= "" and opts.args or nil
    execute_rename(new_name)
  end, {
    nargs = "?",
    desc = "Rename TCL symbol",
  })

  -- Set up keymap for TCL files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tcl", "rvt" },
    callback = function(args)
      vim.keymap.set("n", "<leader>rn", function()
        execute_rename()
      end, {
        buffer = args.buf,
        desc = "Rename symbol",
      })
    end,
  })
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_directory('tests/lua/features/', {minimal_init = 'tests/minimal_init.lua', filter = 'rename'})" \
  -c "qa!"
```

Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/rename.lua tests/lua/features/rename_spec.lua
git commit -m "feat(rename): add setup with TclLspRename command and keymap"
```

---

## Task 7: Register Rename in Plugin Init

**Files:**
- Modify: `lua/tcl-lsp/init.lua`

**Step 1: Add rename require and setup call**

In `lua/tcl-lsp/init.lua`, add the require at the top with other features:

```lua
local rename = require "tcl-lsp.features.rename"
```

And add the setup call in `M.setup()` after `diagnostics.setup()`:

```lua
  -- Set up rename feature
  rename.setup()
```

**Step 2: Run all tests to verify nothing broke**

Run:
```bash
make test-unit
```

Expected: All tests pass

**Step 3: Commit**

```bash
git add lua/tcl-lsp/init.lua
git commit -m "feat(init): register rename feature in plugin setup"
```

---

## Task 8: Run Full Test Suite and Verify

**Step 1: Run full test suite**

Run:
```bash
make test
```

Expected: All tests pass (TCL + Lua)

**Step 2: Run linting**

Run:
```bash
make lint
```

Expected: No errors

**Step 3: Manual verification (optional)**

Open a TCL file in Neovim, position cursor on a proc name, run `:TclLspRename newName` and verify it works.

**Step 4: Final commit if any fixes needed**

If fixes were needed:
```bash
git add -A
git commit -m "fix(rename): address test/lint issues"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Regression tests for find-references | `tests/lua/features/references_spec.lua` |
| 2 | Rename module with validation | `lua/tcl-lsp/features/rename.lua`, `tests/lua/features/rename_spec.lua` |
| 3 | Conflict detection | Same files |
| 4 | Workspace edit generation | Same files |
| 5 | Handle rename entry point | Same files |
| 6 | Setup with user command | Same files |
| 7 | Register in plugin init | `lua/tcl-lsp/init.lua` |
| 8 | Full test suite verification | N/A |

**Total estimated commits:** 8
