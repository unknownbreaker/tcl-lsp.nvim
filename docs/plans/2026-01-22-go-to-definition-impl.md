# Go-to-Definition Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement workspace-wide go-to-definition for TCL procs, namespaces, and variables.

**Architecture:** Lua-driven LSP with background indexing. Symbol index stores definitions, scope resolver handles TCL's namespace/upvar/global semantics, definition resolver ties it together.

**Tech Stack:** Lua (Neovim plugin), plenary.nvim (testing), TCL parser (existing)

---

## Task 1: Symbol Index

Build the core data structure for storing and looking up symbol definitions.

**Files:**
- Create: `lua/tcl-lsp/analyzer/index.lua`
- Test: `tests/lua/analyzer/index_spec.lua`

### Step 1: Write failing test for add/find

Create test file:

```lua
-- tests/lua/analyzer/index_spec.lua
describe("Symbol Index", function()
  local index

  before_each(function()
    package.loaded["tcl-lsp.analyzer.index"] = nil
    index = require("tcl-lsp.analyzer.index")
    index.clear()
  end)

  describe("add_symbol", function()
    it("should store a proc symbol", function()
      local symbol = {
        type = "proc",
        name = "add",
        qualified_name = "::math::add",
        file = "/project/math.tcl",
        range = { start = { line = 10, col = 1 }, end_pos = { line = 20, col = 1 } },
        scope = "::math",
      }

      index.add_symbol(symbol)
      local found = index.find("::math::add")

      assert.is_not_nil(found)
      assert.equals("proc", found.type)
      assert.equals("add", found.name)
      assert.equals("/project/math.tcl", found.file)
    end)
  end)

  describe("find", function()
    it("should return nil for unknown symbol", function()
      local found = index.find("::unknown::symbol")
      assert.is_nil(found)
    end)
  end)
end)
```

### Step 2: Run test to verify it fails

```bash
make test-unit 2>&1 | grep -A5 "Symbol Index"
```

Expected: FAIL - module not found

### Step 3: Write minimal implementation

```lua
-- lua/tcl-lsp/analyzer/index.lua
local M = {}

-- Primary index: qualified_name -> symbol
M.symbols = {}

-- Secondary index: file -> list of qualified names
M.files = {}

function M.clear()
  M.symbols = {}
  M.files = {}
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

return M
```

### Step 4: Run test to verify it passes

```bash
make test-unit 2>&1 | grep -A5 "Symbol Index"
```

Expected: PASS

### Step 5: Add test for remove_file

Add to test file:

```lua
  describe("remove_file", function()
    it("should remove all symbols from a file", function()
      index.add_symbol({
        qualified_name = "::math::add",
        file = "/project/math.tcl",
        type = "proc",
        name = "add",
      })
      index.add_symbol({
        qualified_name = "::math::subtract",
        file = "/project/math.tcl",
        type = "proc",
        name = "subtract",
      })
      index.add_symbol({
        qualified_name = "::utils::helper",
        file = "/project/utils.tcl",
        type = "proc",
        name = "helper",
      })

      index.remove_file("/project/math.tcl")

      assert.is_nil(index.find("::math::add"))
      assert.is_nil(index.find("::math::subtract"))
      assert.is_not_nil(index.find("::utils::helper"))
    end)
  end)
```

### Step 6: Run test to verify it fails

```bash
make test-unit 2>&1 | grep -A5 "remove_file"
```

Expected: FAIL

### Step 7: Implement remove_file

Add to `lua/tcl-lsp/analyzer/index.lua`:

```lua
function M.remove_file(filepath)
  local symbols_in_file = M.files[filepath]
  if not symbols_in_file then
    return
  end

  for _, qualified_name in ipairs(symbols_in_file) do
    M.symbols[qualified_name] = nil
  end

  M.files[filepath] = nil
end
```

### Step 8: Run test to verify it passes

```bash
make test-unit 2>&1 | grep -A5 "remove_file"
```

Expected: PASS

### Step 9: Commit

```bash
git add lua/tcl-lsp/analyzer/index.lua tests/lua/analyzer/index_spec.lua
git commit -m "feat(analyzer): add symbol index with add/find/remove operations"
```

---

## Task 2: AST Symbol Extraction

Extract symbols (procs, variables, namespaces) from a parsed AST.

**Files:**
- Create: `lua/tcl-lsp/analyzer/extractor.lua`
- Test: `tests/lua/analyzer/extractor_spec.lua`

### Step 1: Write failing test for proc extraction

```lua
-- tests/lua/analyzer/extractor_spec.lua
describe("Symbol Extractor", function()
  local extractor

  before_each(function()
    package.loaded["tcl-lsp.analyzer.extractor"] = nil
    extractor = require("tcl-lsp.analyzer.extractor")
  end)

  describe("extract_symbols", function()
    it("should extract proc definitions", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "proc",
            name = "greet",
            params = { { name = "name" } },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
          },
        },
      }

      local symbols = extractor.extract_symbols(ast, "/test.tcl")

      assert.equals(1, #symbols)
      assert.equals("proc", symbols[1].type)
      assert.equals("greet", symbols[1].name)
      assert.equals("::greet", symbols[1].qualified_name)
      assert.equals("/test.tcl", symbols[1].file)
    end)
  end)
end)
```

### Step 2: Run test to verify it fails

```bash
make test-unit 2>&1 | grep -A5 "Symbol Extractor"
```

Expected: FAIL

### Step 3: Write minimal implementation

```lua
-- lua/tcl-lsp/analyzer/extractor.lua
local M = {}

local function visit_node(node, symbols, filepath, current_namespace)
  if not node then
    return
  end

  if node.type == "proc" then
    local qualified = current_namespace .. "::" .. node.name
    if current_namespace == "::" then
      qualified = "::" .. node.name
    end

    table.insert(symbols, {
      type = "proc",
      name = node.name,
      qualified_name = qualified,
      file = filepath,
      range = node.range,
      params = node.params,
      scope = current_namespace,
    })
  end

  -- Recurse into children
  if node.children then
    for _, child in ipairs(node.children) do
      visit_node(child, symbols, filepath, current_namespace)
    end
  end

  -- Recurse into body (for procs)
  if node.body and node.body.children then
    for _, child in ipairs(node.body.children) do
      visit_node(child, symbols, filepath, current_namespace)
    end
  end
end

function M.extract_symbols(ast, filepath)
  local symbols = {}
  visit_node(ast, symbols, filepath, "::")
  return symbols
end

return M
```

### Step 4: Run test to verify it passes

```bash
make test-unit 2>&1 | grep -A5 "Symbol Extractor"
```

Expected: PASS

### Step 5: Add test for namespace_eval

```lua
    it("should extract procs within namespaces", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "namespace_eval",
            name = "math",
            body = {
              children = {
                {
                  type = "proc",
                  name = "add",
                  params = {},
                  range = { start = { line = 2, col = 1 }, end_pos = { line = 4, col = 1 } },
                },
              },
            },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
          },
        },
      }

      local symbols = extractor.extract_symbols(ast, "/math.tcl")

      assert.equals(2, #symbols) -- namespace + proc
      local proc = vim.tbl_filter(function(s) return s.type == "proc" end, symbols)[1]
      assert.equals("::math::add", proc.qualified_name)
      assert.equals("::math", proc.scope)
    end)
```

### Step 6: Run test, implement namespace support

Update `visit_node` to handle namespace_eval:

```lua
  if node.type == "namespace_eval" then
    local new_namespace = current_namespace .. "::" .. node.name
    if current_namespace == "::" then
      new_namespace = "::" .. node.name
    end

    table.insert(symbols, {
      type = "namespace",
      name = node.name,
      qualified_name = new_namespace,
      file = filepath,
      range = node.range,
      scope = current_namespace,
    })

    -- Recurse with new namespace context
    if node.body and node.body.children then
      for _, child in ipairs(node.body.children) do
        visit_node(child, symbols, filepath, new_namespace)
      end
    end
    return -- Don't process body again below
  end
```

### Step 7: Add test for variable extraction

```lua
    it("should extract variable definitions", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "set",
            var_name = "config",
            value = "default",
            range = { start = { line = 1, col = 1 }, end_pos = { line = 1, col = 20 } },
          },
        },
      }

      local symbols = extractor.extract_symbols(ast, "/init.tcl")

      assert.equals(1, #symbols)
      assert.equals("variable", symbols[1].type)
      assert.equals("config", symbols[1].name)
      assert.equals("::config", symbols[1].qualified_name)
    end)
```

### Step 8: Implement variable extraction

Add to `visit_node`:

```lua
  if node.type == "set" then
    local var_name = node.var_name
    local qualified = current_namespace .. "::" .. var_name
    if current_namespace == "::" then
      qualified = "::" .. var_name
    end

    table.insert(symbols, {
      type = "variable",
      name = var_name,
      qualified_name = qualified,
      file = filepath,
      range = node.range,
      scope = current_namespace,
    })
  end

  if node.type == "variable" then
    local var_name = node.name
    local qualified = current_namespace .. "::" .. var_name
    if current_namespace == "::" then
      qualified = "::" .. var_name
    end

    table.insert(symbols, {
      type = "variable",
      name = var_name,
      qualified_name = qualified,
      file = filepath,
      range = node.range,
      scope = current_namespace,
    })
  end
```

### Step 9: Run all extractor tests

```bash
make test-unit 2>&1 | grep -A10 "Symbol Extractor"
```

Expected: PASS

### Step 10: Commit

```bash
git add lua/tcl-lsp/analyzer/extractor.lua tests/lua/analyzer/extractor_spec.lua
git commit -m "feat(analyzer): add symbol extractor for procs, namespaces, variables"
```

---

## Task 3: Background Indexer

Scan workspace files without blocking the editor.

**Files:**
- Create: `lua/tcl-lsp/analyzer/indexer.lua`
- Test: `tests/lua/analyzer/indexer_spec.lua`

### Step 1: Write failing test for file discovery

```lua
-- tests/lua/analyzer/indexer_spec.lua
describe("Background Indexer", function()
  local indexer

  before_each(function()
    package.loaded["tcl-lsp.analyzer.indexer"] = nil
    package.loaded["tcl-lsp.analyzer.index"] = nil
    indexer = require("tcl-lsp.analyzer.indexer")
    indexer.reset()
  end)

  describe("find_tcl_files", function()
    it("should find .tcl files in directory", function()
      -- Use the project's own tcl directory for testing
      local project_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h:h")
      local files = indexer.find_tcl_files(project_root .. "/tcl")

      assert.is_table(files)
      assert.is_true(#files > 0, "Should find TCL files")

      local has_tcl = false
      for _, f in ipairs(files) do
        if f:match("%.tcl$") then
          has_tcl = true
          break
        end
      end
      assert.is_true(has_tcl, "Should include .tcl files")
    end)
  end)

  describe("state", function()
    it("should start in idle state", function()
      assert.equals("idle", indexer.get_status().status)
    end)
  end)
end)
```

### Step 2: Run test to verify it fails

```bash
make test-unit 2>&1 | grep -A5 "Background Indexer"
```

Expected: FAIL

### Step 3: Write minimal implementation

```lua
-- lua/tcl-lsp/analyzer/indexer.lua
local M = {}

M.state = {
  status = "idle", -- idle | scanning | ready
  queued = {},
  total_files = 0,
  indexed_count = 0,
  root_dir = nil,
}

function M.reset()
  M.state = {
    status = "idle",
    queued = {},
    total_files = 0,
    indexed_count = 0,
    root_dir = nil,
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

return M
```

### Step 4: Run test to verify it passes

```bash
make test-unit 2>&1 | grep -A5 "Background Indexer"
```

Expected: PASS

### Step 5: Add test for index_file

```lua
  describe("index_file", function()
    it("should parse file and add symbols to index", function()
      local index = require("tcl-lsp.analyzer.index")
      index.clear()

      -- Create a temp file with TCL code
      local temp_file = vim.fn.tempname() .. ".tcl"
      local f = io.open(temp_file, "w")
      f:write("proc hello {} { puts hi }\n")
      f:close()

      indexer.index_file(temp_file)

      local symbol = index.find("::hello")
      assert.is_not_nil(symbol, "Should index the proc")
      assert.equals("proc", symbol.type)

      vim.fn.delete(temp_file)
    end)
  end)
```

### Step 6: Run test, implement index_file

```lua
local parser = require("tcl-lsp.parser")
local index = require("tcl-lsp.analyzer.index")
local extractor = require("tcl-lsp.analyzer.extractor")

function M.index_file(filepath)
  -- Remove old symbols from this file
  index.remove_file(filepath)

  -- Read file content
  local f = io.open(filepath, "r")
  if not f then
    return false
  end
  local content = f:read("*all")
  f:close()

  -- Parse to AST
  local ast, err = parser.parse(content, filepath)
  if not ast then
    return false
  end

  -- Extract and index symbols
  local symbols = extractor.extract_symbols(ast, filepath)
  for _, symbol in ipairs(symbols) do
    index.add_symbol(symbol)
  end

  return true
end
```

### Step 7: Add test for async start

```lua
  describe("start", function()
    it("should set status to scanning", function()
      local project_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h:h")

      indexer.start(project_root .. "/tcl")

      local status = indexer.get_status()
      assert.is_true(status.status == "scanning" or status.status == "ready")
      assert.is_true(status.total > 0)
    end)
  end)
```

### Step 8: Implement async start with batching

```lua
local BATCH_SIZE = 5

function M.start(root_dir)
  M.state.root_dir = root_dir
  M.state.queued = M.find_tcl_files(root_dir)
  M.state.total_files = #M.state.queued
  M.state.indexed_count = 0
  M.state.status = "scanning"

  M.process_batch()
end

function M.process_batch()
  if M.state.status ~= "scanning" then
    return
  end

  for _ = 1, BATCH_SIZE do
    local file = table.remove(M.state.queued, 1)
    if not file then
      M.state.status = "ready"
      return
    end

    M.index_file(file)
    M.state.indexed_count = M.state.indexed_count + 1
  end

  -- Yield to editor, continue next tick
  vim.defer_fn(M.process_batch, 1)
end
```

### Step 9: Run all indexer tests

```bash
make test-unit 2>&1 | grep -A10 "Background Indexer"
```

Expected: PASS

### Step 10: Commit

```bash
git add lua/tcl-lsp/analyzer/indexer.lua tests/lua/analyzer/indexer_spec.lua
git commit -m "feat(analyzer): add background indexer with async batching"
```

---

## Task 4: Scope Context Builder

Extract scope context (current namespace, locals, globals, upvars) from cursor position.

**Files:**
- Modify: `lua/tcl-lsp/parser/scope.lua` (replace stub)
- Test: `tests/lua/parser/scope_spec.lua`

### Step 1: Write failing test

```lua
-- tests/lua/parser/scope_spec.lua
describe("Scope Context", function()
  local scope

  before_each(function()
    package.loaded["tcl-lsp.parser.scope"] = nil
    scope = require("tcl-lsp.parser.scope")
  end)

  describe("get_context", function()
    it("should return global namespace at top level", function()
      local ast = {
        type = "root",
        children = {},
        range = { start = { line = 1, col = 1 }, end_pos = { line = 10, col = 1 } },
      }

      local ctx = scope.get_context(ast, 5, 1)

      assert.equals("::", ctx.namespace)
      assert.is_nil(ctx.proc)
      assert.same({}, ctx.locals)
    end)

    it("should detect namespace context", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "namespace_eval",
            name = "math",
            range = { start = { line = 1, col = 1 }, end_pos = { line = 10, col = 1 } },
            body = { children = {} },
          },
        },
      }

      local ctx = scope.get_context(ast, 5, 1)

      assert.equals("::math", ctx.namespace)
    end)

    it("should detect proc context with params as locals", function()
      local ast = {
        type = "root",
        children = {
          {
            type = "proc",
            name = "greet",
            params = { { name = "name" }, { name = "greeting", default = "hello" } },
            range = { start = { line = 1, col = 1 }, end_pos = { line = 5, col = 1 } },
            body = { children = {} },
          },
        },
      }

      local ctx = scope.get_context(ast, 3, 1)

      assert.equals("greet", ctx.proc)
      assert.same({ "name", "greeting" }, ctx.locals)
    end)
  end)
end)
```

### Step 2: Run test to verify it fails

```bash
make test-unit 2>&1 | grep -A5 "Scope Context"
```

Expected: FAIL

### Step 3: Write implementation

```lua
-- lua/tcl-lsp/parser/scope.lua
local M = {}

local function position_in_range(line, col, range)
  if not range then
    return false
  end
  local start = range.start or range.start_pos
  local end_pos = range.end_pos or range["end"]

  if not start or not end_pos then
    return false
  end

  if line < start.line or line > end_pos.line then
    return false
  end
  if line == start.line and col < start.col then
    return false
  end
  if line == end_pos.line and col > end_pos.col then
    return false
  end
  return true
end

local function find_enclosing_nodes(node, line, col, path)
  path = path or {}

  if not node then
    return path
  end

  if position_in_range(line, col, node.range) then
    table.insert(path, node)
  end

  -- Check children
  if node.children then
    for _, child in ipairs(node.children) do
      find_enclosing_nodes(child, line, col, path)
    end
  end

  -- Check body (for procs and namespaces)
  if node.body then
    if node.body.children then
      for _, child in ipairs(node.body.children) do
        find_enclosing_nodes(child, line, col, path)
      end
    end
    if position_in_range(line, col, node.body.range) then
      table.insert(path, node.body)
    end
  end

  return path
end

function M.get_context(ast, line, col)
  local context = {
    namespace = "::",
    proc = nil,
    locals = {},
    globals = {},
    upvars = {},
  }

  local path = find_enclosing_nodes(ast, line, col, {})

  for _, node in ipairs(path) do
    if node.type == "namespace_eval" then
      if context.namespace == "::" then
        context.namespace = "::" .. node.name
      else
        context.namespace = context.namespace .. "::" .. node.name
      end
    elseif node.type == "proc" then
      context.proc = node.name
      -- Add params as locals
      if node.params then
        for _, param in ipairs(node.params) do
          table.insert(context.locals, param.name)
        end
      end
    elseif node.type == "set" and context.proc then
      -- Variables set inside a proc are local
      table.insert(context.locals, node.var_name)
    elseif node.type == "global" then
      if node.vars then
        vim.list_extend(context.globals, node.vars)
      end
    elseif node.type == "upvar" then
      context.upvars[node.local_var] = {
        level = node.level,
        other_var = node.other_var,
      }
    end
  end

  return context
end

return M
```

### Step 4: Run test to verify it passes

```bash
make test-unit 2>&1 | grep -A10 "Scope Context"
```

Expected: PASS

### Step 5: Commit

```bash
git add lua/tcl-lsp/parser/scope.lua tests/lua/parser/scope_spec.lua
git commit -m "feat(parser): add scope context builder for namespace/proc/variable resolution"
```

---

## Task 5: Definition Resolver

Find definitions given cursor position, using scope context and index.

**Files:**
- Modify: `lua/tcl-lsp/analyzer/definitions.lua` (replace stub)
- Test: `tests/lua/analyzer/definitions_spec.lua`

### Step 1: Write failing test

```lua
-- tests/lua/analyzer/definitions_spec.lua
describe("Definition Resolver", function()
  local definitions
  local index

  before_each(function()
    package.loaded["tcl-lsp.analyzer.definitions"] = nil
    package.loaded["tcl-lsp.analyzer.index"] = nil
    definitions = require("tcl-lsp.analyzer.definitions")
    index = require("tcl-lsp.analyzer.index")
    index.clear()
  end)

  describe("build_candidates", function()
    it("should generate qualified name candidates", function()
      local context = {
        namespace = "::math",
        proc = nil,
        locals = {},
        globals = {},
      }

      local candidates = definitions.build_candidates("add", context)

      assert.includes("add", candidates)
      assert.includes("::math::add", candidates)
      assert.includes("::add", candidates)
    end)
  end)

  describe("find_definition", function()
    it("should find proc in index", function()
      index.add_symbol({
        type = "proc",
        name = "helper",
        qualified_name = "::utils::helper",
        file = "/project/utils.tcl",
        range = { start = { line = 5, col = 1 }, end_pos = { line = 10, col = 1 } },
        scope = "::utils",
      })

      local result = definitions.find_in_index("helper", {
        namespace = "::utils",
        proc = nil,
        locals = {},
        globals = {},
      })

      assert.is_not_nil(result)
      assert.equals("/project/utils.tcl", result.file)
      assert.equals(5, result.range.start.line)
    end)

    it("should return nil for local variable", function()
      local result = definitions.find_in_index("x", {
        namespace = "::",
        proc = "test",
        locals = { "x", "y" },
        globals = {},
      })

      -- Local variables don't have index entries
      assert.is_nil(result)
    end)
  end)
end)

-- Helper for test assertions
function assert.includes(item, list)
  for _, v in ipairs(list) do
    if v == item then
      return true
    end
  end
  error("Expected list to include: " .. tostring(item))
end
```

### Step 2: Run test to verify it fails

```bash
make test-unit 2>&1 | grep -A5 "Definition Resolver"
```

Expected: FAIL

### Step 3: Write implementation

```lua
-- lua/tcl-lsp/analyzer/definitions.lua
local M = {}

local index = require("tcl-lsp.analyzer.index")

function M.build_candidates(word, context)
  local candidates = {}

  -- Unqualified name
  table.insert(candidates, word)

  -- Qualified with current namespace
  if context.namespace ~= "::" then
    table.insert(candidates, context.namespace .. "::" .. word)
  end

  -- Global namespace
  table.insert(candidates, "::" .. word)

  return candidates
end

function M.find_in_index(word, context)
  -- Skip if it's a local variable
  if vim.tbl_contains(context.locals, word) then
    return nil
  end

  -- Check upvars
  if context.upvars[word] then
    -- Follow upvar chain (simplified - just use the other_var name)
    word = context.upvars[word].other_var
  end

  -- Check globals
  if vim.tbl_contains(context.globals, word) then
    -- Look in global namespace
    local symbol = index.find("::" .. word)
    if symbol then
      return symbol
    end
  end

  -- Try each candidate
  local candidates = M.build_candidates(word, context)
  for _, candidate in ipairs(candidates) do
    local symbol = index.find(candidate)
    if symbol then
      return symbol
    end
  end

  return nil
end

function M.find_definition(bufnr, line, col)
  -- Get word under cursor
  local word = vim.fn.expand("<cword>")
  if not word or word == "" then
    return nil
  end

  -- Strip $ prefix from variables
  if word:sub(1, 1) == "$" then
    word = word:sub(2)
  end

  -- Get buffer content and parse
  local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local parser = require("tcl-lsp.parser")
  local ast, err = parser.parse(table.concat(content, "\n"))
  if not ast then
    return nil
  end

  -- Get scope context
  local scope = require("tcl-lsp.parser.scope")
  local context = scope.get_context(ast, line, col)

  -- Find in index
  local symbol = M.find_in_index(word, context)
  if symbol then
    return {
      uri = "file://" .. symbol.file,
      range = {
        start = { line = symbol.range.start.line - 1, character = symbol.range.start.col - 1 },
        ["end"] = { line = symbol.range.end_pos.line - 1, character = symbol.range.end_pos.col - 1 },
      },
    }
  end

  -- Fallback: search current file AST
  return M.find_in_ast(ast, word, context, vim.api.nvim_buf_get_name(bufnr))
end

function M.find_in_ast(ast, word, context, filepath)
  local extractor = require("tcl-lsp.analyzer.extractor")
  local symbols = extractor.extract_symbols(ast, filepath)

  local candidates = M.build_candidates(word, context)

  for _, candidate in ipairs(candidates) do
    for _, symbol in ipairs(symbols) do
      if symbol.qualified_name == candidate or symbol.name == word then
        return {
          uri = "file://" .. filepath,
          range = {
            start = { line = symbol.range.start.line - 1, character = symbol.range.start.col - 1 },
            ["end"] = { line = symbol.range.end_pos.line - 1, character = symbol.range.end_pos.col - 1 },
          },
        }
      end
    end
  end

  return nil
end

return M
```

### Step 4: Run test to verify it passes

```bash
make test-unit 2>&1 | grep -A10 "Definition Resolver"
```

Expected: PASS

### Step 5: Commit

```bash
git add lua/tcl-lsp/analyzer/definitions.lua tests/lua/analyzer/definitions_spec.lua
git commit -m "feat(analyzer): add definition resolver with scope-aware lookup"
```

---

## Task 6: LSP Handler Integration

Wire up go-to-definition to Neovim's LSP.

**Files:**
- Create: `lua/tcl-lsp/features/definition.lua`
- Modify: `lua/tcl-lsp/init.lua`
- Test: `tests/lua/features/definition_spec.lua`

### Step 1: Write failing test

```lua
-- tests/lua/features/definition_spec.lua
describe("Definition Feature", function()
  local definition

  before_each(function()
    package.loaded["tcl-lsp.features.definition"] = nil
    definition = require("tcl-lsp.features.definition")
  end)

  describe("setup", function()
    it("should register without error", function()
      local success = pcall(definition.setup)
      assert.is_true(success)
    end)
  end)

  describe("handler", function()
    it("should return nil for empty buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      local result = definition.handle_definition(bufnr, 0, 0)

      assert.is_nil(result)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
```

### Step 2: Run test to verify it fails

```bash
make test-unit 2>&1 | grep -A5 "Definition Feature"
```

Expected: FAIL

### Step 3: Write implementation

```lua
-- lua/tcl-lsp/features/definition.lua
local M = {}

local definitions = require("tcl-lsp.analyzer.definitions")

function M.handle_definition(bufnr, line, col)
  return definitions.find_definition(bufnr, line + 1, col + 1)
end

function M.setup()
  -- Create user command for go-to-definition
  vim.api.nvim_create_user_command("TclGoToDefinition", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = pos[1] - 1 -- Convert to 0-indexed
    local col = pos[2]

    local result = M.handle_definition(bufnr, line, col)

    if result then
      -- Jump to location
      local uri = result.uri
      local filepath = uri:gsub("^file://", "")
      local target_line = result.range.start.line + 1
      local target_col = result.range.start.character

      -- Open file if different
      if filepath ~= vim.api.nvim_buf_get_name(bufnr) then
        vim.cmd("edit " .. vim.fn.fnameescape(filepath))
      end

      -- Jump to position
      vim.api.nvim_win_set_cursor(0, { target_line, target_col })
    else
      vim.notify("No definition found", vim.log.levels.INFO)
    end
  end, { desc = "Go to TCL definition" })

  -- Set up keymap for TCL files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tcl", "rvt" },
    callback = function(args)
      vim.keymap.set("n", "gd", "<cmd>TclGoToDefinition<cr>", {
        buffer = args.buf,
        desc = "Go to definition",
      })
    end,
  })
end

return M
```

### Step 4: Run test to verify it passes

```bash
make test-unit 2>&1 | grep -A5 "Definition Feature"
```

Expected: PASS

### Step 5: Wire up in init.lua

Read current init.lua and add the definition feature setup:

Add after other feature setups:

```lua
-- Set up go-to-definition
local definition = require("tcl-lsp.features.definition")
definition.setup()
```

### Step 6: Commit

```bash
git add lua/tcl-lsp/features/definition.lua tests/lua/features/definition_spec.lua lua/tcl-lsp/init.lua
git commit -m "feat(features): add go-to-definition with gd keymap"
```

---

## Task 7: Initialize Indexer on Startup

Start background indexing when the plugin loads.

**Files:**
- Modify: `lua/tcl-lsp/init.lua`
- Modify: `lua/tcl-lsp/server.lua`

### Step 1: Add indexer startup to server.lua

In `M.start()`, after setting root_dir:

```lua
-- Start background indexer
local indexer = require("tcl-lsp.analyzer.indexer")
if indexer.get_status().status == "idle" then
  indexer.start(root_dir)
end
```

### Step 2: Add file change watcher

In init.lua, add autocommand:

```lua
-- Re-index file on save
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = { "*.tcl", "*.rvt" },
  callback = function(args)
    local indexer = require("tcl-lsp.analyzer.indexer")
    if indexer.get_status().status == "ready" then
      indexer.index_file(args.file)
    end
  end,
})
```

### Step 3: Add status command

```lua
vim.api.nvim_create_user_command("TclIndexStatus", function()
  local indexer = require("tcl-lsp.analyzer.indexer")
  local status = indexer.get_status()
  vim.notify(string.format(
    "Index status: %s (%d/%d files)",
    status.status,
    status.indexed,
    status.total
  ), vim.log.levels.INFO)
end, { desc = "Show TCL index status" })
```

### Step 4: Test manually

```bash
nvim --headless -c "lua require('tcl-lsp').setup({})" -c "TclIndexStatus" -c "qa"
```

### Step 5: Commit

```bash
git add lua/tcl-lsp/init.lua lua/tcl-lsp/server.lua
git commit -m "feat: start background indexer on plugin load"
```

---

## Task 8: Integration Test

End-to-end test of go-to-definition.

**Files:**
- Create: `tests/integration/definition_spec.lua`

### Step 1: Write integration test

```lua
-- tests/integration/definition_spec.lua
describe("Go-to-Definition Integration", function()
  local test_dir
  local indexer
  local definition

  before_each(function()
    -- Create temp directory with test files
    test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    -- Create math.tcl
    local math_file = test_dir .. "/math.tcl"
    local f = io.open(math_file, "w")
    f:write([[
namespace eval ::math {
  proc add {a b} {
    return [expr {$a + $b}]
  }
}
]])
    f:close()

    -- Create main.tcl that uses math
    local main_file = test_dir .. "/main.tcl"
    f = io.open(main_file, "w")
    f:write([[
source math.tcl
set result [::math::add 1 2]
puts $result
]])
    f:close()

    -- Reset and initialize
    package.loaded["tcl-lsp.analyzer.index"] = nil
    package.loaded["tcl-lsp.analyzer.indexer"] = nil
    package.loaded["tcl-lsp.analyzer.definitions"] = nil

    local index = require("tcl-lsp.analyzer.index")
    index.clear()

    indexer = require("tcl-lsp.analyzer.indexer")
    indexer.reset()

    definition = require("tcl-lsp.features.definition")
  end)

  after_each(function()
    vim.fn.delete(test_dir, "rf")
  end)

  it("should jump to proc definition across files", function()
    -- Index the test directory
    indexer.start(test_dir)

    -- Wait for indexing to complete (synchronous for test)
    while indexer.get_status().status == "scanning" do
      vim.wait(10)
    end

    -- Open main.tcl
    local main_file = test_dir .. "/main.tcl"
    local bufnr = vim.fn.bufadd(main_file)
    vim.fn.bufload(bufnr)

    -- Find definition of ::math::add on line 2
    local result = definition.handle_definition(bufnr, 1, 15) -- 0-indexed line 1

    assert.is_not_nil(result, "Should find definition")
    assert.matches("math.tcl", result.uri, "Should point to math.tcl")
    assert.equals(1, result.range.start.line, "Should point to line 2 (0-indexed: 1)")
  end)
end)
```

### Step 2: Run integration test

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_file('tests/integration/definition_spec.lua')" \
  -c "qa!"
```

### Step 3: Commit

```bash
git add tests/integration/definition_spec.lua
git commit -m "test: add go-to-definition integration test"
```

---

## Summary

8 tasks total:
1. Symbol Index - core data structure
2. Symbol Extractor - AST to symbols
3. Background Indexer - async workspace scanning
4. Scope Context - TCL scope resolution
5. Definition Resolver - lookup logic
6. LSP Handler - Neovim integration
7. Startup Integration - wire it together
8. Integration Test - end-to-end verification

Each task follows TDD: write failing test → implement → verify → commit.
