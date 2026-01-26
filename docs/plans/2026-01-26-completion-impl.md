# Completion Feature Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement context-aware autocompletion for TCL/RVT files

**Architecture:** Lua-based completion using omnifunc, gathering items from current file AST, project index, and static builtins/packages lists. Context detection filters items appropriately.

**Tech Stack:** Lua, Neovim omnifunc API, existing parser/indexer infrastructure

---

## Task 1: Create Static Builtins Data

**Files:**
- Create: `lua/tcl-lsp/data/builtins.lua`
- Test: `tests/lua/data/builtins_spec.lua`

**Step 1: Write the failing test**

```lua
-- tests/lua/data/builtins_spec.lua
describe("builtins", function()
  local builtins

  before_each(function()
    builtins = require("tcl-lsp.data.builtins")
  end)

  after_each(function()
    package.loaded["tcl-lsp.data.builtins"] = nil
  end)

  it("returns a table", function()
    assert.is_table(builtins)
  end)

  it("contains common TCL commands", function()
    local names = {}
    for _, item in ipairs(builtins) do
      names[item.name] = true
    end
    assert.is_true(names["puts"])
    assert.is_true(names["set"])
    assert.is_true(names["if"])
    assert.is_true(names["proc"])
    assert.is_true(names["foreach"])
  end)

  it("has required fields for each item", function()
    for _, item in ipairs(builtins) do
      assert.is_string(item.name)
      assert.equals("builtin", item.type)
    end
  end)

  it("contains at least 50 commands", function()
    assert.is_true(#builtins >= 50)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL with "module 'tcl-lsp.data.builtins' not found"

**Step 3: Create data directory and implementation**

```lua
-- lua/tcl-lsp/data/builtins.lua
-- Static list of TCL builtin commands for completion

return {
  -- Core commands
  { name = "after", type = "builtin" },
  { name = "append", type = "builtin" },
  { name = "apply", type = "builtin" },
  { name = "array", type = "builtin" },
  { name = "binary", type = "builtin" },
  { name = "break", type = "builtin" },
  { name = "catch", type = "builtin" },
  { name = "cd", type = "builtin" },
  { name = "chan", type = "builtin" },
  { name = "clock", type = "builtin" },
  { name = "close", type = "builtin" },
  { name = "concat", type = "builtin" },
  { name = "continue", type = "builtin" },
  { name = "dict", type = "builtin" },
  { name = "encoding", type = "builtin" },
  { name = "eof", type = "builtin" },
  { name = "error", type = "builtin" },
  { name = "eval", type = "builtin" },
  { name = "exec", type = "builtin" },
  { name = "exit", type = "builtin" },
  { name = "expr", type = "builtin" },
  { name = "fblocked", type = "builtin" },
  { name = "fconfigure", type = "builtin" },
  { name = "fcopy", type = "builtin" },
  { name = "file", type = "builtin" },
  { name = "fileevent", type = "builtin" },
  { name = "flush", type = "builtin" },
  { name = "for", type = "builtin" },
  { name = "foreach", type = "builtin" },
  { name = "format", type = "builtin" },
  { name = "gets", type = "builtin" },
  { name = "glob", type = "builtin" },
  { name = "global", type = "builtin" },
  { name = "if", type = "builtin" },
  { name = "incr", type = "builtin" },
  { name = "info", type = "builtin" },
  { name = "interp", type = "builtin" },
  { name = "join", type = "builtin" },
  { name = "lappend", type = "builtin" },
  { name = "lassign", type = "builtin" },
  { name = "lindex", type = "builtin" },
  { name = "linsert", type = "builtin" },
  { name = "list", type = "builtin" },
  { name = "llength", type = "builtin" },
  { name = "lmap", type = "builtin" },
  { name = "load", type = "builtin" },
  { name = "lrange", type = "builtin" },
  { name = "lrepeat", type = "builtin" },
  { name = "lreplace", type = "builtin" },
  { name = "lreverse", type = "builtin" },
  { name = "lsearch", type = "builtin" },
  { name = "lset", type = "builtin" },
  { name = "lsort", type = "builtin" },
  { name = "namespace", type = "builtin" },
  { name = "open", type = "builtin" },
  { name = "package", type = "builtin" },
  { name = "pid", type = "builtin" },
  { name = "proc", type = "builtin" },
  { name = "puts", type = "builtin" },
  { name = "pwd", type = "builtin" },
  { name = "read", type = "builtin" },
  { name = "regexp", type = "builtin" },
  { name = "regsub", type = "builtin" },
  { name = "rename", type = "builtin" },
  { name = "return", type = "builtin" },
  { name = "scan", type = "builtin" },
  { name = "seek", type = "builtin" },
  { name = "set", type = "builtin" },
  { name = "socket", type = "builtin" },
  { name = "source", type = "builtin" },
  { name = "split", type = "builtin" },
  { name = "string", type = "builtin" },
  { name = "subst", type = "builtin" },
  { name = "switch", type = "builtin" },
  { name = "tailcall", type = "builtin" },
  { name = "tell", type = "builtin" },
  { name = "throw", type = "builtin" },
  { name = "time", type = "builtin" },
  { name = "trace", type = "builtin" },
  { name = "try", type = "builtin" },
  { name = "unload", type = "builtin" },
  { name = "unset", type = "builtin" },
  { name = "update", type = "builtin" },
  { name = "uplevel", type = "builtin" },
  { name = "upvar", type = "builtin" },
  { name = "variable", type = "builtin" },
  { name = "vwait", type = "builtin" },
  { name = "while", type = "builtin" },
}
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/data/builtins.lua tests/lua/data/builtins_spec.lua
git commit -m "feat(completion): add static TCL builtins list"
```

---

## Task 2: Create Static Packages Data

**Files:**
- Create: `lua/tcl-lsp/data/packages.lua`
- Test: `tests/lua/data/packages_spec.lua`

**Step 1: Write the failing test**

```lua
-- tests/lua/data/packages_spec.lua
describe("packages", function()
  local packages

  before_each(function()
    packages = require("tcl-lsp.data.packages")
  end)

  after_each(function()
    package.loaded["tcl-lsp.data.packages"] = nil
  end)

  it("returns a table", function()
    assert.is_table(packages)
  end)

  it("contains common TCL packages", function()
    local names = {}
    for _, name in ipairs(packages) do
      names[name] = true
    end
    assert.is_true(names["Tcl"])
    assert.is_true(names["http"])
    assert.is_true(names["json"])
  end)

  it("contains only strings", function()
    for _, name in ipairs(packages) do
      assert.is_string(name)
    end
  end)

  it("contains at least 15 packages", function()
    assert.is_true(#packages >= 15)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL with "module 'tcl-lsp.data.packages' not found"

**Step 3: Write implementation**

```lua
-- lua/tcl-lsp/data/packages.lua
-- Static list of common TCL packages for completion

return {
  "Tcl",
  "Tk",
  "http",
  "tls",
  "json",
  "json::write",
  "sqlite3",
  "tdbc",
  "tdbc::sqlite3",
  "tdbc::postgres",
  "tdbc::mysql",
  "tdom",
  "msgcat",
  "fileutil",
  "struct::list",
  "struct::set",
  "struct::stack",
  "struct::queue",
  "csv",
  "base64",
  "md5",
  "sha1",
  "sha256",
  "uri",
  "ncgi",
  "html",
  "textutil",
  "cmdline",
  "logger",
  "snit",
}
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/data/packages.lua tests/lua/data/packages_spec.lua
git commit -m "feat(completion): add static TCL packages list"
```

---

## Task 3: Add Completion Config Options

**Files:**
- Modify: `lua/tcl-lsp/config.lua:8-54` (add completion section to defaults)
- Test: `tests/lua/config_spec.lua` (existing tests should still pass)

**Step 1: Write the failing test**

Add this test to `tests/lua/config_spec.lua`:

```lua
describe("completion config", function()
  local config

  before_each(function()
    package.loaded["tcl-lsp.config"] = nil
    config = require("tcl-lsp.config")
    config.reset()
  end)

  it("has completion defaults", function()
    config.setup({})
    local cfg = config.get()
    assert.is_table(cfg.completion)
    assert.equals(true, cfg.completion.enabled)
    assert.equals(2, cfg.completion.trigger_length)
  end)

  it("allows overriding completion settings", function()
    config.setup({
      completion = {
        enabled = false,
        trigger_length = 3,
      },
    })
    local cfg = config.get()
    assert.equals(false, cfg.completion.enabled)
    assert.equals(3, cfg.completion.trigger_length)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL with "cfg.completion is nil"

**Step 3: Add completion config to defaults**

In `lua/tcl-lsp/config.lua`, add to the `defaults` table after `formatting`:

```lua
  -- Completion configuration
  completion = {
    enabled = true,         -- Enable completion
    trigger_length = 2,     -- Characters before triggering
  },
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/config.lua tests/lua/config_spec.lua
git commit -m "feat(completion): add completion config options"
```

---

## Task 4: Core Completion Module - Context Detection

**Files:**
- Create: `lua/tcl-lsp/features/completion.lua`
- Test: `tests/lua/features/completion_spec.lua`

**Step 1: Write the failing test**

```lua
-- tests/lua/features/completion_spec.lua
describe("completion", function()
  local completion

  before_each(function()
    package.loaded["tcl-lsp.features.completion"] = nil
    completion = require("tcl-lsp.features.completion")
  end)

  describe("detect_context", function()
    it("detects variable context after $", function()
      assert.equals("variable", completion.detect_context("set x $", 7))
      assert.equals("variable", completion.detect_context("puts $foo", 9))
    end)

    it("detects variable context with partial name", function()
      assert.equals("variable", completion.detect_context("puts $var", 9))
    end)

    it("detects namespace context after ::", function()
      assert.equals("namespace", completion.detect_context("::ns::", 6))
      assert.equals("namespace", completion.detect_context("::foo::bar", 10))
    end)

    it("detects package context after package require", function()
      assert.equals("package", completion.detect_context("package require ", 16))
      assert.equals("package", completion.detect_context("package require htt", 19))
    end)

    it("returns command context by default", function()
      assert.equals("command", completion.detect_context("pu", 2))
      assert.equals("command", completion.detect_context("set x [for", 10))
    end)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL with "module 'tcl-lsp.features.completion' not found"

**Step 3: Write implementation**

```lua
-- lua/tcl-lsp/features/completion.lua
-- Context-aware autocompletion for TCL/RVT files

local M = {}

--- Detect completion context from line text
---@param line_text string The line text
---@param col number Column position (1-indexed)
---@return string Context type: "variable", "namespace", "package", or "command"
function M.detect_context(line_text, col)
  local before_cursor = line_text:sub(1, col)

  -- Check for variable context: $varname
  if before_cursor:match("%$[%w_]*$") then
    return "variable"
  end

  -- Check for namespace context: ::ns:: or ::ns::name
  if before_cursor:match("::[%w_:]*$") then
    return "namespace"
  end

  -- Check for package require context
  if before_cursor:match("package%s+require%s+[%w_:]*$") then
    return "package"
  end

  return "command"
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/completion.lua tests/lua/features/completion_spec.lua
git commit -m "feat(completion): add context detection"
```

---

## Task 5: Completion Items from Current File

**Files:**
- Modify: `lua/tcl-lsp/features/completion.lua`
- Test: `tests/lua/features/completion_spec.lua`

**Step 1: Write the failing test**

Add to `tests/lua/features/completion_spec.lua`:

```lua
  describe("get_file_symbols", function()
    it("extracts procs from code", function()
      local code = [[
proc my_proc {arg1 arg2} {
  return $arg1
}
proc another_proc {} {
  puts "hello"
}
]]
      local symbols = completion.get_file_symbols(code, "/test.tcl")
      local names = {}
      for _, sym in ipairs(symbols) do
        if sym.type == "proc" then
          names[sym.name] = true
        end
      end
      assert.is_true(names["my_proc"])
      assert.is_true(names["another_proc"])
    end)

    it("extracts variables from code", function()
      local code = [[
set myvar "value"
set another 123
]]
      local symbols = completion.get_file_symbols(code, "/test.tcl")
      local names = {}
      for _, sym in ipairs(symbols) do
        if sym.type == "variable" then
          names[sym.name] = true
        end
      end
      assert.is_true(names["myvar"])
      assert.is_true(names["another"])
    end)

    it("returns empty list for invalid code", function()
      local code = "this is not valid {{{ tcl"
      local symbols = completion.get_file_symbols(code, "/test.tcl")
      assert.is_table(symbols)
      -- May be empty or contain partial results
    end)
  end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL with "get_file_symbols is nil"

**Step 3: Write implementation**

Add to `lua/tcl-lsp/features/completion.lua`:

```lua
local parser = require("tcl-lsp.parser")
local extractor = require("tcl-lsp.analyzer.extractor")

--- Extract symbols from code for completion
---@param code string TCL source code
---@param filepath string File path
---@return table List of symbols
function M.get_file_symbols(code, filepath)
  local ast = parser.parse(code, filepath)
  if not ast then
    return {}
  end

  return extractor.extract_symbols(ast, filepath)
end
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/completion.lua tests/lua/features/completion_spec.lua
git commit -m "feat(completion): extract symbols from current file"
```

---

## Task 6: Build Completion Items

**Files:**
- Modify: `lua/tcl-lsp/features/completion.lua`
- Test: `tests/lua/features/completion_spec.lua`

**Step 1: Write the failing test**

Add to `tests/lua/features/completion_spec.lua`:

```lua
  describe("build_completion_item", function()
    it("builds item for proc", function()
      local symbol = { name = "my_proc", type = "proc", qualified_name = "::my_proc" }
      local item = completion.build_completion_item(symbol)
      assert.equals("my_proc", item.label)
      assert.equals("proc", item.detail)
      assert.equals("my_proc", item.insertText)
      assert.equals(vim.lsp.protocol.CompletionItemKind.Function, item.kind)
    end)

    it("builds item for variable", function()
      local symbol = { name = "myvar", type = "variable", qualified_name = "::myvar" }
      local item = completion.build_completion_item(symbol)
      assert.equals("myvar", item.label)
      assert.equals("variable", item.detail)
      assert.equals("myvar", item.insertText)
      assert.equals(vim.lsp.protocol.CompletionItemKind.Variable, item.kind)
    end)

    it("builds item for builtin", function()
      local builtin = { name = "puts", type = "builtin" }
      local item = completion.build_completion_item(builtin)
      assert.equals("puts", item.label)
      assert.equals("builtin", item.detail)
      assert.equals(vim.lsp.protocol.CompletionItemKind.Keyword, item.kind)
    end)

    it("builds item for namespace", function()
      local symbol = { name = "myns", type = "namespace", qualified_name = "::myns" }
      local item = completion.build_completion_item(symbol)
      assert.equals("myns", item.label)
      assert.equals("namespace", item.detail)
      assert.equals(vim.lsp.protocol.CompletionItemKind.Module, item.kind)
    end)
  end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL with "build_completion_item is nil"

**Step 3: Write implementation**

Add to `lua/tcl-lsp/features/completion.lua`:

```lua
--- Map symbol types to LSP CompletionItemKind
local KIND_MAP = {
  proc = vim.lsp.protocol.CompletionItemKind.Function,
  variable = vim.lsp.protocol.CompletionItemKind.Variable,
  builtin = vim.lsp.protocol.CompletionItemKind.Keyword,
  namespace = vim.lsp.protocol.CompletionItemKind.Module,
  package = vim.lsp.protocol.CompletionItemKind.Module,
}

--- Build a completion item from a symbol
---@param symbol table Symbol with name, type fields
---@return table LSP completion item
function M.build_completion_item(symbol)
  return {
    label = symbol.name,
    kind = KIND_MAP[symbol.type] or vim.lsp.protocol.CompletionItemKind.Text,
    detail = symbol.type,
    insertText = symbol.name,
  }
end
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/completion.lua tests/lua/features/completion_spec.lua
git commit -m "feat(completion): build LSP completion items"
```

---

## Task 7: Get Completions - Main Entry Point

**Files:**
- Modify: `lua/tcl-lsp/features/completion.lua`
- Test: `tests/lua/features/completion_spec.lua`

**Step 1: Write the failing test**

Add to `tests/lua/features/completion_spec.lua`:

```lua
  describe("get_completions", function()
    local builtins, packages

    before_each(function()
      builtins = require("tcl-lsp.data.builtins")
      packages = require("tcl-lsp.data.packages")
    end)

    it("returns empty for empty buffer", function()
      local items = completion.get_completions("", 1, 0, "/test.tcl")
      assert.is_table(items)
    end)

    it("includes builtins in command context", function()
      local items = completion.get_completions("pu", 1, 2, "/test.tcl")
      local has_puts = false
      for _, item in ipairs(items) do
        if item.label == "puts" then
          has_puts = true
          break
        end
      end
      assert.is_true(has_puts)
    end)

    it("filters to variables after $", function()
      local code = [[set myvar "hello"
puts $my]]
      local items = completion.get_completions(code, 2, 8, "/test.tcl")
      -- Should include myvar, exclude procs/builtins
      local found_var = false
      local found_builtin = false
      for _, item in ipairs(items) do
        if item.label == "myvar" then
          found_var = true
        end
        if item.detail == "builtin" then
          found_builtin = true
        end
      end
      assert.is_true(found_var)
      assert.is_false(found_builtin)
    end)

    it("filters to packages after package require", function()
      local code = "package require ht"
      local items = completion.get_completions(code, 1, 18, "/test.tcl")
      -- Should include http, exclude procs/variables
      local found_http = false
      local found_proc = false
      for _, item in ipairs(items) do
        if item.label == "http" then
          found_http = true
        end
        if item.detail == "proc" then
          found_proc = true
        end
      end
      assert.is_true(found_http)
      assert.is_false(found_proc)
    end)

    it("includes procs from current file", function()
      local code = [[proc my_helper {} { return 1 }
my_]]
      local items = completion.get_completions(code, 2, 3, "/test.tcl")
      local found = false
      for _, item in ipairs(items) do
        if item.label == "my_helper" then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)
  end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL with "get_completions is nil"

**Step 3: Write implementation**

Add to `lua/tcl-lsp/features/completion.lua`:

```lua
local builtins = require("tcl-lsp.data.builtins")
local packages = require("tcl-lsp.data.packages")
local index = require("tcl-lsp.analyzer.index")

--- Get all completions for the given position
---@param code string Full buffer content
---@param line number Line number (1-indexed)
---@param col number Column number (0-indexed)
---@param filepath string File path
---@return table List of completion items
function M.get_completions(code, line, col, filepath)
  local items = {}
  local lines = vim.split(code, "\n", { plain = true })
  local line_text = lines[line] or ""

  -- Detect context
  local context = M.detect_context(line_text, col)

  -- Get symbols from current file
  local file_symbols = M.get_file_symbols(code, filepath)

  -- Get symbols from index (project-wide)
  local index_symbols = {}
  for _, symbol in pairs(index.symbols) do
    table.insert(index_symbols, symbol)
  end

  if context == "variable" then
    -- Variables only
    for _, sym in ipairs(file_symbols) do
      if sym.type == "variable" then
        table.insert(items, M.build_completion_item(sym))
      end
    end
    for _, sym in ipairs(index_symbols) do
      if sym.type == "variable" then
        table.insert(items, M.build_completion_item(sym))
      end
    end
  elseif context == "package" then
    -- Packages only
    for _, pkg_name in ipairs(packages) do
      table.insert(items, {
        label = pkg_name,
        kind = vim.lsp.protocol.CompletionItemKind.Module,
        detail = "package",
        insertText = pkg_name,
      })
    end
  elseif context == "namespace" then
    -- Namespace-qualified procs and namespaces
    for _, sym in ipairs(file_symbols) do
      if sym.type == "proc" or sym.type == "namespace" then
        table.insert(items, M.build_completion_item(sym))
      end
    end
    for _, sym in ipairs(index_symbols) do
      if sym.type == "proc" or sym.type == "namespace" then
        table.insert(items, M.build_completion_item(sym))
      end
    end
  else
    -- Command context: procs, builtins, namespaces
    for _, sym in ipairs(file_symbols) do
      if sym.type == "proc" or sym.type == "namespace" then
        table.insert(items, M.build_completion_item(sym))
      end
    end
    for _, sym in ipairs(index_symbols) do
      if sym.type == "proc" or sym.type == "namespace" then
        table.insert(items, M.build_completion_item(sym))
      end
    end
    for _, builtin in ipairs(builtins) do
      table.insert(items, M.build_completion_item(builtin))
    end
  end

  return items
end
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/completion.lua tests/lua/features/completion_spec.lua
git commit -m "feat(completion): implement get_completions with context filtering"
```

---

## Task 8: Setup and Omnifunc Registration

**Files:**
- Modify: `lua/tcl-lsp/features/completion.lua`
- Test: `tests/lua/features/completion_spec.lua`

**Step 1: Write the failing test**

Add to `tests/lua/features/completion_spec.lua`:

```lua
  describe("setup", function()
    it("is callable", function()
      assert.has_no.errors(function()
        completion.setup()
      end)
    end)
  end)

  describe("omnifunc", function()
    it("returns start position when findstart=1", function()
      -- Mock vim functions
      local original_fn = vim.fn
      vim.fn = setmetatable({
        getline = function()
          return "puts hello"
        end,
        col = function()
          return 11
        end,
      }, { __index = original_fn })

      local result = completion.omnifunc(1, "")
      assert.is_number(result)

      vim.fn = original_fn
    end)
  end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL with "omnifunc is nil"

**Step 3: Write implementation**

Add to `lua/tcl-lsp/features/completion.lua`:

```lua
local config = require("tcl-lsp.config")

--- Omnifunc for TCL completion
---@param findstart number 1 to find start, 0 to get completions
---@param base string Prefix to complete (when findstart=0)
---@return number|table Start column or completion items
function M.omnifunc(findstart, base)
  if findstart == 1 then
    -- Find start of completion
    local line = vim.fn.getline(".")
    local col = vim.fn.col(".") - 1

    -- Walk backwards to find start of word
    while col > 0 do
      local char = line:sub(col, col)
      if char:match("[%w_:]") or char == "$" then
        col = col - 1
      else
        break
      end
    end

    return col
  else
    -- Get completions
    local cfg = config.get()
    if not cfg.completion.enabled then
      return {}
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local code = table.concat(lines, "\n")
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = pos[1]
    local col = pos[2]
    local filepath = vim.api.nvim_buf_get_name(bufnr)

    local items = M.get_completions(code, line, col, filepath)

    -- Filter by base prefix
    if base and base ~= "" then
      local filtered = {}
      local base_lower = base:lower()
      for _, item in ipairs(items) do
        if item.label:lower():sub(1, #base) == base_lower then
          table.insert(filtered, item)
        end
      end
      items = filtered
    end

    -- Convert to omnifunc format
    local results = {}
    for _, item in ipairs(items) do
      table.insert(results, {
        word = item.insertText,
        abbr = item.label,
        kind = item.detail,
        menu = "[TCL]",
      })
    end

    return results
  end
end

--- Set up completion for TCL files
function M.setup()
  -- Set omnifunc for TCL files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tcl", "rvt" },
    callback = function(args)
      vim.bo[args.buf].omnifunc = "v:lua.require'tcl-lsp.features.completion'.omnifunc"
    end,
  })
end
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/completion.lua tests/lua/features/completion_spec.lua
git commit -m "feat(completion): add omnifunc and setup"
```

---

## Task 9: Register Completion in Plugin Init

**Files:**
- Modify: `lua/tcl-lsp/init.lua:6-13` (add require)
- Modify: `lua/tcl-lsp/init.lua:114-118` (add setup call)

**Step 1: Run existing tests to establish baseline**

Run: `make test-unit`
Expected: PASS (all existing tests)

**Step 2: Add require at top**

In `lua/tcl-lsp/init.lua`, after line 13 (require folding), add:

```lua
local completion = require "tcl-lsp.features.completion"
```

**Step 3: Add setup call**

In `lua/tcl-lsp/init.lua`, after formatting.setup() call, add:

```lua
  -- Set up completion feature
  completion.setup()
```

**Step 4: Run tests to verify nothing broke**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/init.lua
git commit -m "feat(completion): register completion in plugin init"
```

---

## Task 10: Final Integration Testing

**Files:**
- Test manually with real TCL file

**Step 1: Run all tests**

Run: `make test`
Expected: All tests PASS

**Step 2: Run linting**

Run: `make lint`
Expected: No errors

**Step 3: Manual integration test**

Create a test file and verify completion works:

```tcl
# test_completion.tcl
proc my_helper {x y} {
    return [expr {$x + $y}]
}

set myvar "hello"
set another 123

# Test: Type "my_" and press Ctrl-X Ctrl-O
# Expected: See my_helper in completions

# Test: Type "$my" and press Ctrl-X Ctrl-O
# Expected: See myvar in completions, NOT my_helper

# Test: Type "package require ht" and press Ctrl-X Ctrl-O
# Expected: See http in completions
```

**Step 4: Commit final integration**

```bash
git add -A
git commit -m "feat(completion): complete Phase 6 completion feature"
```

**Step 5: Push to remote**

```bash
git push
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Static builtins data | `data/builtins.lua` |
| 2 | Static packages data | `data/packages.lua` |
| 3 | Completion config | `config.lua` |
| 4 | Context detection | `features/completion.lua` |
| 5 | File symbol extraction | `features/completion.lua` |
| 6 | Completion item building | `features/completion.lua` |
| 7 | Main get_completions | `features/completion.lua` |
| 8 | Omnifunc and setup | `features/completion.lua` |
| 9 | Plugin registration | `init.lua` |
| 10 | Final integration | Manual testing |
