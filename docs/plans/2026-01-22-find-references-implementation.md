# Find References Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement LSP find-references for TCL, showing definitions, exports, and call sites grouped by type.

**Architecture:** Extend the existing symbol index to track references during indexing. Create `analyzer/references.lua` to query references and `features/references.lua` for the `gr` keymap and Telescope/quickfix UI.

**Tech Stack:** Lua, plenary.nvim (testing), telescope.nvim (optional UI)

---

## Task 1: Add Reference Tracking to Symbol Index

**Files:**
- Modify: `lua/tcl-lsp/analyzer/index.lua`
- Test: `tests/lua/analyzer/index_spec.lua`

**Step 1: Write the failing test**

Add to `tests/lua/analyzer/index_spec.lua`:

```lua
describe("reference tracking", function()
  it("should add references to a symbol", function()
    index.add_symbol({
      type = "proc",
      name = "helper",
      qualified_name = "::utils::helper",
      file = "/project/utils.tcl",
      range = { start = { line = 5, col = 1 }, end_pos = { line = 10, col = 1 } },
      scope = "::utils",
    })

    index.add_reference("::utils::helper", {
      type = "call",
      file = "/project/main.tcl",
      range = { start = { line = 20, col = 5 }, end_pos = { line = 20, col = 11 } },
      text = "helper $arg",
    })

    local refs = index.get_references("::utils::helper")
    assert.equals(1, #refs)
    assert.equals("call", refs[1].type)
    assert.equals("/project/main.tcl", refs[1].file)
  end)

  it("should return empty list for symbol with no references", function()
    index.add_symbol({
      type = "proc",
      name = "unused",
      qualified_name = "::unused",
      file = "/project/lib.tcl",
      range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
      scope = "::",
    })

    local refs = index.get_references("::unused")
    assert.is_table(refs)
    assert.equals(0, #refs)
  end)

  it("should remove references when file is removed", function()
    index.add_symbol({
      type = "proc",
      name = "target",
      qualified_name = "::target",
      file = "/project/target.tcl",
      range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
      scope = "::",
    })

    index.add_reference("::target", {
      type = "call",
      file = "/project/caller.tcl",
      range = { start = { line = 10, col = 1 }, end_pos = { line = 10, col = 7 } },
      text = "target",
    })

    index.remove_file("/project/caller.tcl")

    local refs = index.get_references("::target")
    assert.equals(0, #refs)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL with "attempt to call a nil value (field 'add_reference')"

**Step 3: Write minimal implementation**

Update `lua/tcl-lsp/analyzer/index.lua`:

```lua
-- lua/tcl-lsp/analyzer/index.lua
-- Symbol Index - core data structure for storing and looking up symbol definitions

local M = {}

-- Primary index: qualified_name -> symbol
M.symbols = {}

-- Secondary index: file -> list of qualified names
M.files = {}

-- Reference index: qualified_name -> list of references
M.references = {}

-- Reverse index: file -> list of {qualified_name, ref_index} for cleanup
M.ref_files = {}

function M.clear()
  M.symbols = {}
  M.files = {}
  M.references = {}
  M.ref_files = {}
end

function M.add_symbol(symbol)
  if not symbol or not symbol.qualified_name then
    return false
  end

  M.symbols[symbol.qualified_name] = symbol

  -- Update file index
  local file = symbol.file
  if file then
    if not M.files[file] then
      M.files[file] = {}
    end
    table.insert(M.files[file], symbol.qualified_name)
  end

  return true
end

function M.find(qualified_name)
  return M.symbols[qualified_name]
end

function M.add_reference(qualified_name, ref)
  if not qualified_name or not ref then
    return false
  end

  if not M.references[qualified_name] then
    M.references[qualified_name] = {}
  end

  table.insert(M.references[qualified_name], ref)

  -- Track file -> reference mapping for cleanup
  if ref.file then
    if not M.ref_files[ref.file] then
      M.ref_files[ref.file] = {}
    end
    table.insert(M.ref_files[ref.file], {
      qualified_name = qualified_name,
      ref_index = #M.references[qualified_name],
    })
  end

  return true
end

function M.get_references(qualified_name)
  return M.references[qualified_name] or {}
end

function M.remove_file(filepath)
  -- Remove symbols defined in this file
  local symbols_in_file = M.files[filepath]
  if symbols_in_file then
    for _, qualified_name in ipairs(symbols_in_file) do
      M.symbols[qualified_name] = nil
      M.references[qualified_name] = nil
    end
  end
  M.files[filepath] = nil

  -- Remove references from this file
  local refs_in_file = M.ref_files[filepath]
  if refs_in_file then
    for _, ref_info in ipairs(refs_in_file) do
      local refs = M.references[ref_info.qualified_name]
      if refs then
        -- Filter out references from this file
        local new_refs = {}
        for _, r in ipairs(refs) do
          if r.file ~= filepath then
            table.insert(new_refs, r)
          end
        end
        M.references[ref_info.qualified_name] = new_refs
      end
    end
  end
  M.ref_files[filepath] = nil
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/analyzer/index.lua tests/lua/analyzer/index_spec.lua
git commit -m "feat(analyzer): add reference tracking to symbol index"
```

---

## Task 2: Create Reference Extractor

**Files:**
- Create: `lua/tcl-lsp/analyzer/ref_extractor.lua`
- Test: `tests/lua/analyzer/ref_extractor_spec.lua`

**Step 1: Write the failing test**

Create `tests/lua/analyzer/ref_extractor_spec.lua`:

```lua
-- tests/lua/analyzer/ref_extractor_spec.lua
-- Tests for Reference Extractor - extracts references (calls, exports) from AST

describe("Reference Extractor", function()
  local ref_extractor

  before_each(function()
    package.loaded["tcl-lsp.analyzer.ref_extractor"] = nil
    ref_extractor = require("tcl-lsp.analyzer.ref_extractor")
  end)

  describe("extract_references", function()
    it("should extract proc call references", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "command",
            name = "helper",
            args = { "$arg1", "$arg2" },
            range = { start = { line = 5, col = 1 }, end_pos = { line = 5, col = 20 } },
          },
        },
      }

      local refs = ref_extractor.extract_references(ast, "/test.tcl")

      assert.equals(1, #refs)
      assert.equals("call", refs[1].type)
      assert.equals("helper", refs[1].name)
      assert.equals("/test.tcl", refs[1].file)
    end)

    it("should extract namespace export references", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "namespace_eval",
            name = "utils",
            body = {
              children = {
                {
                  type = "namespace_export",
                  exports = { "formatDate", "validateInput" },
                  range = { start = { line = 10, col = 3 }, end_pos = { line = 10, col = 40 } },
                },
              },
            },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 20, col = 1 } },
          },
        },
      }

      local refs = ref_extractor.extract_references(ast, "/utils.tcl")

      assert.equals(2, #refs)
      assert.equals("export", refs[1].type)
      assert.equals("formatDate", refs[1].name)
      assert.equals("export", refs[2].type)
      assert.equals("validateInput", refs[2].name)
    end)

    it("should extract interp alias references", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "interp_alias",
            alias = "::shortName",
            target = "::full::longName",
            range = { start = { line = 3, col = 1 }, end_pos = { line = 3, col = 50 } },
          },
        },
      }

      local refs = ref_extractor.extract_references(ast, "/aliases.tcl")

      assert.equals(1, #refs)
      assert.equals("export", refs[1].type)
      assert.equals("::full::longName", refs[1].target)
    end)

    it("should track namespace context for unqualified calls", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "namespace_eval",
            name = "myns",
            body = {
              children = {
                {
                  type = "command",
                  name = "localProc",
                  args = {},
                  range = { start = { line = 5, col = 5 }, end_pos = { line = 5, col = 15 } },
                },
              },
            },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 10, col = 1 } },
          },
        },
      }

      local refs = ref_extractor.extract_references(ast, "/ns.tcl")

      assert.equals(1, #refs)
      assert.equals("::myns", refs[1].namespace)
    end)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL with "module 'tcl-lsp.analyzer.ref_extractor' not found"

**Step 3: Write minimal implementation**

Create `lua/tcl-lsp/analyzer/ref_extractor.lua`:

```lua
-- lua/tcl-lsp/analyzer/ref_extractor.lua
-- Reference Extractor - extracts references (calls, exports, aliases) from AST

local M = {}

-- TCL built-in commands to skip (not user-defined procs)
local BUILTINS = {
  set = true, puts = true, expr = true, if = true, else = true,
  for = true, foreach = true, while = true, switch = true,
  proc = true, return = true, break = true, continue = true,
  catch = true, try = true, throw = true, error = true,
  list = true, lindex = true, llength = true, lappend = true,
  lsort = true, lsearch = true, lrange = true, lreplace = true,
  string = true, regexp = true, regsub = true, split = true, join = true,
  array = true, dict = true, incr = true, append = true,
  open = true, close = true, read = true, gets = true, eof = true,
  file = true, glob = true, cd = true, pwd = true,
  package = true, namespace = true, variable = true, global = true, upvar = true,
  info = true, rename = true, interp = true, source = true,
  after = true, update = true, vwait = true,
}

local function visit_node(node, refs, filepath, current_namespace)
  if not node then
    return
  end

  if node.type == "namespace_eval" then
    local new_namespace = current_namespace .. "::" .. node.name
    if current_namespace == "::" then
      new_namespace = "::" .. node.name
    end

    -- Recurse with new namespace context
    if node.body and node.body.children then
      for _, child in ipairs(node.body.children) do
        visit_node(child, refs, filepath, new_namespace)
      end
    end
    return
  end

  if node.type == "namespace_export" then
    for _, export_name in ipairs(node.exports or {}) do
      if export_name ~= "*" then
        table.insert(refs, {
          type = "export",
          name = export_name,
          namespace = current_namespace,
          file = filepath,
          range = node.range,
          text = "namespace export " .. export_name,
        })
      end
    end
  end

  if node.type == "interp_alias" then
    table.insert(refs, {
      type = "export",
      name = node.alias,
      target = node.target,
      file = filepath,
      range = node.range,
      text = "interp alias " .. (node.alias or "") .. " " .. (node.target or ""),
    })
  end

  if node.type == "command" then
    local cmd_name = node.name
    if cmd_name and not BUILTINS[cmd_name] then
      table.insert(refs, {
        type = "call",
        name = cmd_name,
        namespace = current_namespace,
        file = filepath,
        range = node.range,
        text = cmd_name .. " " .. table.concat(node.args or {}, " "),
      })
    end
  end

  -- Recurse into children
  if node.children then
    for _, child in ipairs(node.children) do
      visit_node(child, refs, filepath, current_namespace)
    end
  end

  -- Recurse into body (for procs)
  if node.body and node.body.children then
    for _, child in ipairs(node.body.children) do
      visit_node(child, refs, filepath, current_namespace)
    end
  end
end

function M.extract_references(ast, filepath)
  local refs = {}
  visit_node(ast, refs, filepath, "::")
  return refs
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/analyzer/ref_extractor.lua tests/lua/analyzer/ref_extractor_spec.lua
git commit -m "feat(analyzer): add reference extractor for calls and exports"
```

---

## Task 3: Integrate Reference Extraction into Indexer

**Files:**
- Modify: `lua/tcl-lsp/analyzer/indexer.lua`
- Test: `tests/lua/analyzer/indexer_spec.lua`

**Step 1: Write the failing test**

Add to `tests/lua/analyzer/indexer_spec.lua`:

```lua
describe("reference indexing", function()
  it("should index references when indexing a file", function()
    local temp_dir = helpers.create_temp_dir("indexer_refs")
    local utils_file = temp_dir .. "/utils.tcl"
    local main_file = temp_dir .. "/main.tcl"

    helpers.write_file(utils_file, [[
proc ::utils::helper {} {
    puts "helper"
}
]])

    helpers.write_file(main_file, [[
proc main {} {
    ::utils::helper
}
]])

    indexer.start(temp_dir)

    -- Wait for indexing to complete
    helpers.wait_for(function()
      return indexer.get_status().status == "ready"
    end, 5000, "Indexer did not complete")

    local refs = index.get_references("::utils::helper")
    assert.is_true(#refs >= 1, "Should have at least one reference")

    local found_call = false
    for _, ref in ipairs(refs) do
      if ref.type == "call" and ref.file == main_file then
        found_call = true
        break
      end
    end
    assert.is_true(found_call, "Should find call reference from main.tcl")

    helpers.cleanup_temp_dir(temp_dir)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL - references not populated

**Step 3: Write minimal implementation**

Update `lua/tcl-lsp/analyzer/indexer.lua` to add reference extraction:

```lua
-- lua/tcl-lsp/analyzer/indexer.lua
-- Background Indexer - scans workspace files without blocking the editor

local parser = require("tcl-lsp.parser")
local index = require("tcl-lsp.analyzer.index")
local extractor = require("tcl-lsp.analyzer.extractor")
local ref_extractor = require("tcl-lsp.analyzer.ref_extractor")

local M = {}

local BATCH_SIZE = 5

M.state = {
  status = "idle", -- idle | scanning | ready
  queued = {},
  total_files = 0,
  indexed_count = 0,
  root_dir = nil,
  -- Store ASTs for second pass reference resolution
  pending_refs = {},
}

function M.reset()
  M.state = {
    status = "idle",
    queued = {},
    total_files = 0,
    indexed_count = 0,
    root_dir = nil,
    pending_refs = {},
  }
end

function M.get_status()
  return {
    status = M.state.status,
    total = M.state.total_files,
    indexed = M.state.indexed_count,
  }
end

function M.find_tcl_files(root_dir)
  local files = {}

  local tcl_files = vim.fn.globpath(root_dir, "**/*.tcl", false, true)
  vim.list_extend(files, tcl_files)

  local rvt_files = vim.fn.globpath(root_dir, "**/*.rvt", false, true)
  vim.list_extend(files, rvt_files)

  return files
end

function M.index_file(filepath)
  -- Remove old symbols and refs from this file
  index.remove_file(filepath)

  -- Read file content
  local f = io.open(filepath, "r")
  if not f then
    return false
  end
  local content = f:read("*all")
  f:close()

  -- Parse to AST
  local ast = parser.parse(content, filepath)
  if not ast then
    return false
  end

  -- Extract and index symbols
  local symbols = extractor.extract_symbols(ast, filepath)
  for _, symbol in ipairs(symbols) do
    index.add_symbol(symbol)
  end

  -- Store AST for reference extraction in second pass
  table.insert(M.state.pending_refs, { ast = ast, filepath = filepath })

  return true
end

function M.resolve_references()
  -- Second pass: extract and resolve references
  for _, pending in ipairs(M.state.pending_refs) do
    local refs = ref_extractor.extract_references(pending.ast, pending.filepath)
    for _, ref in ipairs(refs) do
      -- Resolve the reference to a qualified name
      local qualified_name = M.resolve_ref_target(ref)
      if qualified_name then
        index.add_reference(qualified_name, ref)
      end
    end
  end
  M.state.pending_refs = {}
end

function M.resolve_ref_target(ref)
  if ref.type == "call" then
    local name = ref.name
    -- Try fully qualified first
    if name:sub(1, 2) == "::" then
      if index.find(name) then
        return name
      end
    end
    -- Try with namespace context
    if ref.namespace and ref.namespace ~= "::" then
      local qualified = ref.namespace .. "::" .. name
      if index.find(qualified) then
        return qualified
      end
    end
    -- Try global
    local global = "::" .. name
    if index.find(global) then
      return global
    end
  elseif ref.type == "export" then
    -- Export references: resolve the exported name
    if ref.target then
      -- interp alias - target is already qualified
      return ref.target
    elseif ref.namespace and ref.name then
      -- namespace export
      return ref.namespace .. "::" .. ref.name
    end
  end
  return nil
end

function M.start(root_dir)
  M.state.root_dir = root_dir
  M.state.queued = M.find_tcl_files(root_dir)
  M.state.total_files = #M.state.queued
  M.state.indexed_count = 0
  M.state.status = "scanning"
  M.state.pending_refs = {}

  M.process_batch()
end

function M.process_batch()
  if M.state.status ~= "scanning" then
    return
  end

  for _ = 1, BATCH_SIZE do
    local file = table.remove(M.state.queued, 1)
    if not file then
      -- First pass complete, do reference resolution
      M.resolve_references()
      M.state.status = "ready"
      return
    end

    M.index_file(file)
    M.state.indexed_count = M.state.indexed_count + 1
  end

  -- Yield to editor, continue next tick
  vim.defer_fn(M.process_batch, 1)
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/analyzer/indexer.lua tests/lua/analyzer/indexer_spec.lua
git commit -m "feat(analyzer): integrate reference extraction into indexer"
```

---

## Task 4: Create References Analyzer Module

**Files:**
- Create: `lua/tcl-lsp/analyzer/references.lua` (replace empty stub)
- Test: `tests/lua/analyzer/references_spec.lua` (replace empty stub)

**Step 1: Write the failing test**

Replace `tests/lua/analyzer/references_spec.lua`:

```lua
-- tests/lua/analyzer/references_spec.lua
-- Tests for References Analyzer - finds all references to a symbol

describe("References Analyzer", function()
  local references
  local index

  before_each(function()
    package.loaded["tcl-lsp.analyzer.references"] = nil
    package.loaded["tcl-lsp.analyzer.index"] = nil
    references = require("tcl-lsp.analyzer.references")
    index = require("tcl-lsp.analyzer.index")
    index.clear()
  end)

  describe("find_references", function()
    it("should return definition as first result", function()
      index.add_symbol({
        type = "proc",
        name = "helper",
        qualified_name = "::utils::helper",
        file = "/project/utils.tcl",
        range = { start = { line = 5, col = 1 }, end_pos = { line = 10, col = 1 } },
        scope = "::utils",
      })

      local results = references.find_references("::utils::helper")

      assert.is_true(#results >= 1)
      assert.equals("definition", results[1].type)
      assert.equals("/project/utils.tcl", results[1].file)
    end)

    it("should group results by type: definition, export, call", function()
      index.add_symbol({
        type = "proc",
        name = "formatDate",
        qualified_name = "::utils::formatDate",
        file = "/project/utils.tcl",
        range = { start = { line = 5, col = 1 }, end_pos = { line = 10, col = 1 } },
        scope = "::utils",
      })

      index.add_reference("::utils::formatDate", {
        type = "export",
        file = "/project/utils.tcl",
        range = { start = { line = 20, col = 1 }, end_pos = { line = 20, col = 30 } },
        text = "namespace export formatDate",
      })

      index.add_reference("::utils::formatDate", {
        type = "call",
        file = "/project/main.tcl",
        range = { start = { line = 15, col = 5 }, end_pos = { line = 15, col = 25 } },
        text = "::utils::formatDate $today",
      })

      local results = references.find_references("::utils::formatDate")

      assert.equals(3, #results)
      assert.equals("definition", results[1].type)
      assert.equals("export", results[2].type)
      assert.equals("call", results[3].type)
    end)

    it("should return empty list for unknown symbol", function()
      local results = references.find_references("::nonexistent::proc")

      assert.is_table(results)
      assert.equals(0, #results)
    end)

    it("should sort calls by file then line", function()
      index.add_symbol({
        type = "proc",
        name = "target",
        qualified_name = "::target",
        file = "/project/lib.tcl",
        range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
        scope = "::",
      })

      -- Add calls in non-sorted order
      index.add_reference("::target", {
        type = "call",
        file = "/project/z_file.tcl",
        range = { start = { line = 10, col = 1 }, end_pos = { line = 10, col = 7 } },
        text = "target",
      })
      index.add_reference("::target", {
        type = "call",
        file = "/project/a_file.tcl",
        range = { start = { line = 5, col = 1 }, end_pos = { line = 5, col = 7 } },
        text = "target",
      })
      index.add_reference("::target", {
        type = "call",
        file = "/project/a_file.tcl",
        range = { start = { line = 20, col = 1 }, end_pos = { line = 20, col = 7 } },
        text = "target",
      })

      local results = references.find_references("::target")

      -- Skip definition, check calls are sorted
      assert.equals("/project/a_file.tcl", results[2].file)
      assert.equals(5, results[2].range.start.line)
      assert.equals("/project/a_file.tcl", results[3].file)
      assert.equals(20, results[3].range.start.line)
      assert.equals("/project/z_file.tcl", results[4].file)
    end)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL

**Step 3: Write minimal implementation**

Replace `lua/tcl-lsp/analyzer/references.lua`:

```lua
-- lua/tcl-lsp/analyzer/references.lua
-- References Analyzer - finds all references to a symbol

local M = {}

local index = require("tcl-lsp.analyzer.index")

-- Type order for sorting: definition first, then exports, then calls
local TYPE_ORDER = {
  definition = 1,
  export = 2,
  call = 3,
}

local function compare_refs(a, b)
  -- First by type
  local order_a = TYPE_ORDER[a.type] or 99
  local order_b = TYPE_ORDER[b.type] or 99
  if order_a ~= order_b then
    return order_a < order_b
  end

  -- Then by file
  if a.file ~= b.file then
    return a.file < b.file
  end

  -- Then by line
  local line_a = a.range and a.range.start and a.range.start.line or 0
  local line_b = b.range and b.range.start and b.range.start.line or 0
  return line_a < line_b
end

--- Find all references to a symbol
---@param qualified_name string The fully qualified symbol name
---@return table List of references with type, file, range, text
function M.find_references(qualified_name)
  local results = {}

  -- Get the symbol definition
  local symbol = index.find(qualified_name)
  if not symbol then
    return results
  end

  -- Add definition as first result
  table.insert(results, {
    type = "definition",
    file = symbol.file,
    range = symbol.range,
    text = symbol.type .. " " .. symbol.name,
  })

  -- Get all references
  local refs = index.get_references(qualified_name)
  for _, ref in ipairs(refs) do
    table.insert(results, {
      type = ref.type,
      file = ref.file,
      range = ref.range,
      text = ref.text,
    })
  end

  -- Sort by type, then file, then line
  table.sort(results, compare_refs)

  return results
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/analyzer/references.lua tests/lua/analyzer/references_spec.lua
git commit -m "feat(analyzer): add references analyzer module"
```

---

## Task 5: Create References Feature Module

**Files:**
- Create: `lua/tcl-lsp/features/references.lua` (replace empty stub)
- Test: `tests/lua/features/references_spec.lua`

**Step 1: Write the failing test**

Create `tests/lua/features/references_spec.lua`:

```lua
-- tests/lua/features/references_spec.lua
-- Tests for find-references feature

local helpers = require "tests.spec.test_helpers"

describe("References Feature", function()
  local references_feature

  before_each(function()
    package.loaded["tcl-lsp.features.references"] = nil
    references_feature = require("tcl-lsp.features.references")
  end)

  describe("setup", function()
    it("should register without error", function()
      local success = pcall(references_feature.setup)
      assert.is_true(success)
    end)

    it("should create TclFindReferences user command", function()
      references_feature.setup()

      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands.TclFindReferences, "TclFindReferences command should be registered")
    end)
  end)

  describe("keymap registration", function()
    local temp_file
    local bufnr

    before_each(function()
      references_feature.setup()
      temp_file = vim.fn.tempname() .. ".tcl"
      helpers.write_file(temp_file, "proc test {} { puts hello }")
      vim.cmd("edit " .. temp_file)
      bufnr = vim.api.nvim_get_current_buf()
      vim.cmd("setfiletype tcl")
      vim.wait(100)
    end)

    after_each(function()
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
      if temp_file then
        vim.fn.delete(temp_file)
      end
    end)

    it("should register gr keymap for TCL files", function()
      local keymaps = vim.api.nvim_buf_get_keymap(bufnr, "n")
      local gr_found = false

      for _, keymap in ipairs(keymaps) do
        if keymap.lhs == "gr" then
          gr_found = true
          break
        end
      end

      assert.is_true(gr_found, "gr keymap should be registered for TCL files")
    end)
  end)

  describe("format_for_quickfix", function()
    it("should format references as quickfix entries", function()
      local refs = {
        {
          type = "definition",
          file = "/project/utils.tcl",
          range = { start = { line = 5, col = 1 }, end_pos = { line = 10, col = 1 } },
          text = "proc formatDate",
        },
        {
          type = "call",
          file = "/project/main.tcl",
          range = { start = { line = 15, col = 5 }, end_pos = { line = 15, col = 25 } },
          text = "formatDate $today",
        },
      }

      local qf_entries = references_feature.format_for_quickfix(refs)

      assert.equals(2, #qf_entries)
      assert.equals("/project/utils.tcl", qf_entries[1].filename)
      assert.equals(5, qf_entries[1].lnum)
      assert.is_true(qf_entries[1].text:match("%[def%]") ~= nil)
    end)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL

**Step 3: Write minimal implementation**

Replace `lua/tcl-lsp/features/references.lua`:

```lua
-- lua/tcl-lsp/features/references.lua
-- Find References feature for TCL LSP

local M = {}

local references_analyzer = require("tcl-lsp.analyzer.references")
local definitions = require("tcl-lsp.analyzer.definitions")
local index = require("tcl-lsp.analyzer.index")

-- Type labels for display
local TYPE_LABELS = {
  definition = "[def]",
  export = "[export]",
  call = "[call]",
}

--- Format references for quickfix list
---@param refs table List of reference entries
---@return table Quickfix entries
function M.format_for_quickfix(refs)
  local entries = {}

  for _, ref in ipairs(refs) do
    local label = TYPE_LABELS[ref.type] or "[?]"
    local lnum = ref.range and ref.range.start and ref.range.start.line or 1
    local col = ref.range and ref.range.start and ref.range.start.col or 1

    table.insert(entries, {
      filename = ref.file,
      lnum = lnum,
      col = col,
      text = label .. " " .. (ref.text or ""),
    })
  end

  return entries
end

--- Format references for Telescope
---@param refs table List of reference entries
---@return table Telescope entries
function M.format_for_telescope(refs)
  local entries = {}

  for _, ref in ipairs(refs) do
    local label = TYPE_LABELS[ref.type] or "[?]"
    local lnum = ref.range and ref.range.start and ref.range.start.line or 1
    local col = ref.range and ref.range.start and ref.range.start.col or 1
    local filename = vim.fn.fnamemodify(ref.file, ":t")

    table.insert(entries, {
      display = string.format("%-8s %s:%d    %s", label, filename, lnum, ref.text or ""),
      ordinal = filename .. " " .. (ref.text or ""),
      filename = ref.file,
      lnum = lnum,
      col = col,
      type = ref.type,
    })
  end

  return entries
end

--- Show references using Telescope if available, otherwise quickfix
---@param refs table List of reference entries
local function show_references(refs)
  if #refs == 0 then
    vim.notify("No references found", vim.log.levels.INFO)
    return
  end

  -- Try Telescope first
  local has_telescope, telescope_builtin = pcall(require, "telescope.builtin")
  if has_telescope then
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local entries = M.format_for_telescope(refs)

    pickers.new({}, {
      prompt_title = "TCL References",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.ordinal,
            filename = entry.filename,
            lnum = entry.lnum,
            col = entry.col,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = conf.grep_previewer({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))
            vim.api.nvim_win_set_cursor(0, { selection.lnum, selection.col - 1 })
          end
        end)
        return true
      end,
    }):find()
    return
  end

  -- Fallback to quickfix
  local qf_entries = M.format_for_quickfix(refs)
  vim.fn.setqflist(qf_entries)
  vim.cmd("copen")
end

--- Handle find-references request
---@param bufnr number Buffer number
---@param line number Line number (0-indexed)
---@param col number Column number (0-indexed)
function M.handle_references(bufnr, line, col)
  -- Get word under cursor
  local word = vim.fn.expand("<cword>")
  if not word or word == "" then
    vim.notify("No symbol under cursor", vim.log.levels.INFO)
    return
  end

  -- Strip $ prefix from variables
  if word:sub(1, 1) == "$" then
    word = word:sub(2)
  end

  -- Get buffer content and parse
  local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local parser = require("tcl-lsp.parser")
  local ast = parser.parse(table.concat(content, "\n"))
  if not ast then
    vim.notify("Failed to parse file", vim.log.levels.WARN)
    return
  end

  -- Get scope context at cursor position
  local scope = require("tcl-lsp.parser.scope")
  local context = scope.get_context(ast, line + 1, col + 1)

  -- Try to find the symbol in the index
  local symbol = definitions.find_in_index(word, context)
  if not symbol then
    vim.notify("Symbol not indexed", vim.log.levels.WARN)
    return
  end

  -- Get references
  local refs = references_analyzer.find_references(symbol.qualified_name)
  show_references(refs)
end

--- Set up find-references feature
function M.setup()
  -- Create user command
  vim.api.nvim_create_user_command("TclFindReferences", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = pos[1] - 1 -- Convert to 0-indexed
    local col = pos[2]

    M.handle_references(bufnr, line, col)
  end, { desc = "Find TCL references" })

  -- Set up keymap for TCL files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tcl", "rvt" },
    callback = function(args)
      vim.keymap.set("n", "gr", "<cmd>TclFindReferences<cr>", {
        buffer = args.buf,
        desc = "Find references",
      })
    end,
  })
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/references.lua tests/lua/features/references_spec.lua
git commit -m "feat(features): add find-references with Telescope/quickfix UI"
```

---

## Task 6: Register References Feature in Plugin Init

**Files:**
- Modify: `lua/tcl-lsp/init.lua`
- Test: `tests/lua/init_spec.lua`

**Step 1: Write the failing test**

Add to `tests/lua/init_spec.lua`:

```lua
describe("references feature registration", function()
  it("should setup references feature on plugin load", function()
    local tcl_lsp = require("tcl-lsp")
    tcl_lsp.setup({})

    -- Verify the command exists
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands.TclFindReferences)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL (command not registered)

**Step 3: Write minimal implementation**

Add to `lua/tcl-lsp/init.lua` in the setup function:

```lua
-- In setup(), after definition.setup()
local references = require("tcl-lsp.features.references")
references.setup()
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/init.lua tests/lua/init_spec.lua
git commit -m "feat: register find-references feature in plugin init"
```

---

## Task 7: Add Integration Test

**Files:**
- Create: `tests/integration/references_spec.lua`

**Step 1: Write the integration test**

Create `tests/integration/references_spec.lua`:

```lua
-- tests/integration/references_spec.lua
-- Integration tests for find-references feature

local helpers = require "tests.spec.test_helpers"

describe("Find References Integration", function()
  local temp_dir
  local utils_file, main_file, report_file

  before_each(function()
    -- Clear module cache
    package.loaded["tcl-lsp"] = nil
    package.loaded["tcl-lsp.features.references"] = nil
    package.loaded["tcl-lsp.analyzer.references"] = nil
    package.loaded["tcl-lsp.analyzer.index"] = nil
    package.loaded["tcl-lsp.analyzer.indexer"] = nil

    -- Create test project
    temp_dir = helpers.create_temp_dir("refs_integration")

    utils_file = temp_dir .. "/utils.tcl"
    helpers.write_file(utils_file, [[
namespace eval ::utils {
    proc formatDate {date} {
        return [clock format $date]
    }

    namespace export formatDate
}
]])

    main_file = temp_dir .. "/main.tcl"
    helpers.write_file(main_file, [[
proc main {} {
    set today [clock seconds]
    set formatted [::utils::formatDate $today]
    puts "Today: $formatted"
}
]])

    report_file = temp_dir .. "/report.tcl"
    helpers.write_file(report_file, [[
namespace import ::utils::formatDate

proc generate_report {} {
    set timestamp [clock seconds]
    return [formatDate $timestamp]
}
]])

    -- Initialize plugin
    local tcl_lsp = require("tcl-lsp")
    tcl_lsp.setup({})

    -- Start indexer
    local indexer = require("tcl-lsp.analyzer.indexer")
    indexer.start(temp_dir)

    -- Wait for indexing
    helpers.wait_for(function()
      return indexer.get_status().status == "ready"
    end, 5000, "Indexer did not complete")
  end)

  after_each(function()
    helpers.cleanup_temp_dir(temp_dir)
  end)

  it("should find definition, export, and calls for formatDate", function()
    local index = require("tcl-lsp.analyzer.index")
    local references = require("tcl-lsp.analyzer.references")

    local refs = references.find_references("::utils::formatDate")

    -- Should have: 1 definition + 1 export + 2 calls = 4
    assert.is_true(#refs >= 3, "Expected at least 3 references, got " .. #refs)

    -- Check ordering: definition first
    assert.equals("definition", refs[1].type)

    -- Check we have an export
    local has_export = false
    for _, ref in ipairs(refs) do
      if ref.type == "export" then
        has_export = true
        break
      end
    end
    assert.is_true(has_export, "Should have export reference")

    -- Check we have calls
    local call_count = 0
    for _, ref in ipairs(refs) do
      if ref.type == "call" then
        call_count = call_count + 1
      end
    end
    assert.is_true(call_count >= 1, "Should have at least 1 call reference")
  end)
end)
```

**Step 2: Run test**

Run: `make test`
Expected: PASS

**Step 3: Commit**

```bash
git add tests/integration/references_spec.lua
git commit -m "test: add find-references integration test"
```

---

## Task 8: Final Verification and Cleanup

**Step 1: Run full test suite**

```bash
make test
make lint
```

Expected: All tests pass, no lint errors

**Step 2: Manual verification checklist**

Open Neovim with a TCL project and verify:
- [ ] `gr` on proc name opens Telescope with grouped results
- [ ] Results show `[def]`, `[export]`, `[call]` prefixes
- [ ] Selecting entry jumps to correct location
- [ ] Works without Telescope (falls back to quickfix)
- [ ] `gr` on undefined symbol shows "not indexed" message
- [ ] Works in both `.tcl` and `.rvt` files

**Step 3: Commit any final fixes**

```bash
git add -A
git commit -m "chore: final cleanup for find-references feature"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Add reference tracking to symbol index | index.lua |
| 2 | Create reference extractor | ref_extractor.lua |
| 3 | Integrate extraction into indexer | indexer.lua |
| 4 | Create references analyzer | references.lua (analyzer) |
| 5 | Create references feature | references.lua (features) |
| 6 | Register in plugin init | init.lua |
| 7 | Integration test | references_spec.lua |
| 8 | Final verification | - |
