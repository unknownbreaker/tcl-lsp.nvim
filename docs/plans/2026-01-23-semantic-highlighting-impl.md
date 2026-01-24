# Semantic Highlighting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add LSP semantic token support for rich, meaning-based syntax highlighting in TCL/RVT files.

**Architecture:** Three new modules — `semantic_tokens.lua` (token extraction), `highlights.lua` (LSP handlers), `rvt.lua` (template parsing). Hybrid mode provides immediate single-file highlighting, enhanced when workspace index is ready.

**Tech Stack:** Lua, plenary.nvim for tests, existing TCL parser infrastructure.

**Design Doc:** `docs/plans/2026-01-23-semantic-highlighting-design.md`

---

## Task 1: Token Type Constants

**Files:**
- Create: `lua/tcl-lsp/analyzer/semantic_tokens.lua`
- Test: `tests/lua/semantic_tokens_spec.lua`

**Step 1: Write the failing test**

```lua
-- tests/lua/semantic_tokens_spec.lua
describe("Semantic Tokens", function()
  local semantic_tokens

  before_each(function()
    package.loaded["tcl-lsp.analyzer.semantic_tokens"] = nil
    semantic_tokens = require("tcl-lsp.analyzer.semantic_tokens")
  end)

  describe("Token Types", function()
    it("should define standard LSP token types", function()
      assert.is_table(semantic_tokens.token_types)
      assert.equals(0, semantic_tokens.token_types.namespace)
      assert.equals(1, semantic_tokens.token_types.type)
      assert.equals(2, semantic_tokens.token_types.class)
      assert.equals(5, semantic_tokens.token_types.function_)
      assert.equals(8, semantic_tokens.token_types.variable)
      assert.equals(10, semantic_tokens.token_types.parameter)
    end)

    it("should define custom token types", function()
      assert.is_number(semantic_tokens.token_types.macro)
      assert.is_number(semantic_tokens.token_types.decorator)
    end)

    it("should provide token_types_legend array", function()
      assert.is_table(semantic_tokens.token_types_legend)
      assert.equals("namespace", semantic_tokens.token_types_legend[1])
      assert.equals("function", semantic_tokens.token_types_legend[6])
    end)
  end)
end)
```

**Step 2: Run test to verify it fails**

```bash
make test-unit
```

Expected: FAIL — module not found

**Step 3: Write minimal implementation**

```lua
-- lua/tcl-lsp/analyzer/semantic_tokens.lua
-- Semantic token extraction for TCL LSP

local M = {}

-- LSP standard token types (indices match LSP spec)
-- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#semanticTokenTypes
M.token_types_legend = {
  "namespace",   -- 0
  "type",        -- 1
  "class",       -- 2
  "enum",        -- 3
  "interface",   -- 4
  "function",    -- 5
  "variable",    -- 6
  "property",    -- 7
  "parameter",   -- 8 (note: swapped with variable per LSP spec)
  "string",      -- 9
  "number",      -- 10
  "keyword",     -- 11
  "comment",     -- 12
  "operator",    -- 13
  "macro",       -- 14 (custom)
  "decorator",   -- 15 (custom)
}

-- Build reverse lookup (name -> index, 0-based for LSP)
M.token_types = {}
for i, name in ipairs(M.token_types_legend) do
  local key = name
  if name == "function" then
    key = "function_"  -- Lua reserved word
  end
  M.token_types[key] = i - 1
end

return M
```

**Step 4: Run test to verify it passes**

```bash
make test-unit
```

Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/analyzer/semantic_tokens.lua tests/lua/semantic_tokens_spec.lua
git commit -m "feat(semantic): add token type constants"
```

---

## Task 2: Token Modifiers

**Files:**
- Modify: `lua/tcl-lsp/analyzer/semantic_tokens.lua`
- Modify: `tests/lua/semantic_tokens_spec.lua`

**Step 1: Write the failing test**

Add to `tests/lua/semantic_tokens_spec.lua`:

```lua
  describe("Token Modifiers", function()
    it("should define modifier bitmasks", function()
      assert.is_table(semantic_tokens.token_modifiers)
      assert.equals(1, semantic_tokens.token_modifiers.declaration)      -- bit 0
      assert.equals(2, semantic_tokens.token_modifiers.definition)       -- bit 1
      assert.equals(4, semantic_tokens.token_modifiers.readonly)         -- bit 2
      assert.equals(32, semantic_tokens.token_modifiers.modification)    -- bit 5
      assert.equals(64, semantic_tokens.token_modifiers.defaultLibrary)  -- bit 6
      assert.equals(256, semantic_tokens.token_modifiers.async)          -- bit 8
    end)

    it("should provide token_modifiers_legend array", function()
      assert.is_table(semantic_tokens.token_modifiers_legend)
      assert.equals("declaration", semantic_tokens.token_modifiers_legend[1])
      assert.equals("definition", semantic_tokens.token_modifiers_legend[2])
    end)

    it("should combine modifiers with bitwise OR", function()
      local mods = semantic_tokens.token_modifiers
      local combined = semantic_tokens.combine_modifiers({ "definition", "readonly" })
      assert.equals(mods.definition + mods.readonly, combined)
    end)
  end)
```

**Step 2: Run test to verify it fails**

```bash
make test-unit
```

Expected: FAIL — token_modifiers not defined

**Step 3: Write minimal implementation**

Add to `lua/tcl-lsp/analyzer/semantic_tokens.lua`:

```lua
-- LSP standard token modifiers (bitmask values)
M.token_modifiers_legend = {
  "declaration",    -- bit 0 (1)
  "definition",     -- bit 1 (2)
  "readonly",       -- bit 2 (4)
  "static",         -- bit 3 (8)
  "deprecated",     -- bit 4 (16)
  "modification",   -- bit 5 (32)
  "defaultLibrary", -- bit 6 (64)
  "documentation",  -- bit 7 (128)
  "async",          -- bit 8 (256)
}

-- Build modifier bitmask lookup
M.token_modifiers = {}
for i, name in ipairs(M.token_modifiers_legend) do
  M.token_modifiers[name] = bit.lshift(1, i - 1)
end

-- Combine multiple modifiers into a single bitmask
function M.combine_modifiers(modifier_names)
  local result = 0
  for _, name in ipairs(modifier_names or {}) do
    if M.token_modifiers[name] then
      result = bit.bor(result, M.token_modifiers[name])
    end
  end
  return result
end
```

**Step 4: Run test to verify it passes**

```bash
make test-unit
```

Expected: PASS

**Step 5: Commit**

```bash
git add -u
git commit -m "feat(semantic): add token modifier constants and combiner"
```

---

## Task 3: Extract Proc Definition Tokens

**Files:**
- Modify: `lua/tcl-lsp/analyzer/semantic_tokens.lua`
- Modify: `tests/lua/semantic_tokens_spec.lua`
- Create: `tests/fixtures/semantic/simple_proc.tcl`

**Step 1: Create test fixture**

```tcl
# tests/fixtures/semantic/simple_proc.tcl
proc hello {name} {
    puts "Hello, $name"
}
```

**Step 2: Write the failing test**

Add to `tests/lua/semantic_tokens_spec.lua`:

```lua
  describe("Token Extraction", function()
    local parser = require("tcl-lsp.parser")

    it("should extract proc definition token", function()
      local code = [[proc hello {name} {
    puts "Hello, $name"
}]]
      local ast = parser.parse(code, "test.tcl")
      local tokens = semantic_tokens.extract_tokens(ast)

      -- Should have token for "hello" (function definition)
      assert.is_table(tokens)
      assert.is_true(#tokens >= 1)

      local proc_token = tokens[1]
      assert.equals(1, proc_token.line)           -- line 1
      assert.equals(5, proc_token.start_char)     -- after "proc "
      assert.equals(5, proc_token.length)         -- "hello"
      assert.equals(semantic_tokens.token_types.function_, proc_token.type)
      assert.is_true(bit.band(proc_token.modifiers, semantic_tokens.token_modifiers.definition) > 0)
    end)
  end)
```

**Step 3: Run test to verify it fails**

```bash
make test-unit
```

Expected: FAIL — extract_tokens not defined

**Step 4: Write minimal implementation**

Add to `lua/tcl-lsp/analyzer/semantic_tokens.lua`:

```lua
-- Extract semantic tokens from AST
function M.extract_tokens(ast)
  local tokens = {}

  local function visit(node)
    if not node then return end

    if node.type == "proc" then
      -- Extract proc name token
      if node.name and node.range then
        table.insert(tokens, {
          line = node.range.start.line,
          start_char = node.range.start.column + 5, -- after "proc "
          length = #node.name,
          type = M.token_types.function_,
          modifiers = M.token_modifiers.definition,
        })
      end
    end

    -- Recurse into children
    if node.children then
      for _, child in ipairs(node.children) do
        visit(child)
      end
    end
    if node.body and node.body.children then
      for _, child in ipairs(node.body.children) do
        visit(child)
      end
    end
  end

  visit(ast)
  return tokens
end
```

**Step 5: Run test to verify it passes**

```bash
make test-unit
```

Expected: PASS

**Step 6: Commit**

```bash
mkdir -p tests/fixtures/semantic
echo 'proc hello {name} {
    puts "Hello, $name"
}' > tests/fixtures/semantic/simple_proc.tcl
git add lua/tcl-lsp/analyzer/semantic_tokens.lua tests/lua/semantic_tokens_spec.lua tests/fixtures/semantic/
git commit -m "feat(semantic): extract proc definition tokens"
```

---

## Task 4: Extract Parameter Tokens

**Files:**
- Modify: `lua/tcl-lsp/analyzer/semantic_tokens.lua`
- Modify: `tests/lua/semantic_tokens_spec.lua`

**Step 1: Write the failing test**

Add to `tests/lua/semantic_tokens_spec.lua`:

```lua
    it("should extract parameter tokens from proc", function()
      local code = [[proc greet {name age} {
    puts "$name is $age"
}]]
      local ast = parser.parse(code, "test.tcl")
      local tokens = semantic_tokens.extract_tokens(ast)

      -- Find parameter tokens
      local param_tokens = vim.tbl_filter(function(t)
        return t.type == semantic_tokens.token_types.parameter
      end, tokens)

      assert.equals(2, #param_tokens)
      assert.equals("name", param_tokens[1].text)
      assert.equals("age", param_tokens[2].text)
    end)
```

**Step 2: Run test, verify failure, implement**

Update `extract_tokens` in `semantic_tokens.lua` to handle proc parameters:

```lua
if node.type == "proc" then
  -- ... existing proc name handling ...

  -- Extract parameter tokens
  if node.params then
    for _, param in ipairs(node.params) do
      if param.range then
        table.insert(tokens, {
          line = param.range.start.line,
          start_char = param.range.start.column,
          length = #param.name,
          type = M.token_types.parameter,
          modifiers = M.token_modifiers.declaration,
          text = param.name,
        })
      end
    end
  end
end
```

**Step 3: Commit**

```bash
git add -u && git commit -m "feat(semantic): extract parameter tokens"
```

---

## Task 5: Extract Variable Tokens

**Files:**
- Modify: `lua/tcl-lsp/analyzer/semantic_tokens.lua`
- Modify: `tests/lua/semantic_tokens_spec.lua`

**Step 1: Write the failing test**

```lua
    it("should extract variable reference tokens", function()
      local code = [[set name "World"
puts $name]]
      local ast = parser.parse(code, "test.tcl")
      local tokens = semantic_tokens.extract_tokens(ast)

      local var_tokens = vim.tbl_filter(function(t)
        return t.type == semantic_tokens.token_types.variable
      end, tokens)

      assert.is_true(#var_tokens >= 2)
      -- First: set target (modification)
      assert.is_true(bit.band(var_tokens[1].modifiers, semantic_tokens.token_modifiers.modification) > 0)
    end)
```

**Step 2: Implement variable handling**

```lua
if node.type == "set" then
  if node.var_name and node.var_range then
    table.insert(tokens, {
      line = node.var_range.start.line,
      start_char = node.var_range.start.column,
      length = #node.var_name,
      type = M.token_types.variable,
      modifiers = M.token_modifiers.modification,
      text = node.var_name,
    })
  end
end

if node.type == "var_ref" then
  if node.name and node.range then
    table.insert(tokens, {
      line = node.range.start.line,
      start_char = node.range.start.column,
      length = #node.name + 1,  -- include $
      type = M.token_types.variable,
      modifiers = 0,
      text = node.name,
    })
  end
end
```

**Step 3: Commit**

```bash
git add -u && git commit -m "feat(semantic): extract variable tokens"
```

---

## Task 6: Extract Keyword Tokens (Builtins)

**Files:**
- Modify: `lua/tcl-lsp/analyzer/semantic_tokens.lua`
- Modify: `tests/lua/semantic_tokens_spec.lua`

**Step 1: Write the failing test**

```lua
    it("should mark builtin commands as keywords with defaultLibrary", function()
      local code = [[if {$x > 0} {
    puts "positive"
}]]
      local ast = parser.parse(code, "test.tcl")
      local tokens = semantic_tokens.extract_tokens(ast)

      local keyword_tokens = vim.tbl_filter(function(t)
        return t.type == semantic_tokens.token_types.keyword
      end, tokens)

      assert.is_true(#keyword_tokens >= 1)
      local if_token = keyword_tokens[1]
      assert.equals("if", if_token.text)
      assert.is_true(bit.band(if_token.modifiers, semantic_tokens.token_modifiers.defaultLibrary) > 0)
    end)
```

**Step 2: Implement builtin detection**

Reuse `BUILTINS` table from `ref_extractor.lua` or define locally:

```lua
local BUILTINS = {
  set = true, puts = true, expr = true, ["if"] = true, ["else"] = true,
  ["for"] = true, foreach = true, ["while"] = true, switch = true,
  proc = true, ["return"] = true, ["break"] = true, continue = true,
  -- ... rest of builtins
}

-- In visit function:
if node.type == "command" then
  if node.name and BUILTINS[node.name] then
    table.insert(tokens, {
      line = node.range.start.line,
      start_char = node.range.start.column,
      length = #node.name,
      type = M.token_types.keyword,
      modifiers = M.token_modifiers.defaultLibrary,
      text = node.name,
    })
  end
end
```

**Step 3: Commit**

```bash
git add -u && git commit -m "feat(semantic): extract builtin keyword tokens"
```

---

## Task 7: LSP Token Encoding

**Files:**
- Modify: `lua/tcl-lsp/analyzer/semantic_tokens.lua`
- Modify: `tests/lua/semantic_tokens_spec.lua`

**Step 1: Write the failing test**

```lua
  describe("LSP Encoding", function()
    it("should encode tokens to LSP format (relative positions)", function()
      local tokens = {
        { line = 1, start_char = 5, length = 5, type = 5, modifiers = 2 },
        { line = 1, start_char = 12, length = 4, type = 8, modifiers = 1 },
        { line = 3, start_char = 4, length = 4, type = 11, modifiers = 64 },
      }

      local encoded = semantic_tokens.encode_tokens(tokens)

      -- LSP format: [deltaLine, deltaStartChar, length, tokenType, tokenModifiers]
      assert.same({
        0, 5, 5, 5, 2,    -- first token (line 1, char 5)
        0, 7, 4, 8, 1,    -- same line, 7 chars later
        2, 4, 4, 11, 64,  -- 2 lines down, char 4
      }, encoded)
    end)
  end)
```

**Step 2: Implement encoding**

```lua
-- Encode tokens to LSP semantic tokens format
-- Returns flat array: [deltaLine, deltaStartChar, length, tokenType, tokenModifiers, ...]
function M.encode_tokens(tokens)
  -- Sort by position
  table.sort(tokens, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return a.start_char < b.start_char
  end)

  local result = {}
  local prev_line = 1
  local prev_char = 0

  for _, token in ipairs(tokens) do
    local delta_line = token.line - prev_line
    local delta_char = delta_line == 0 and (token.start_char - prev_char) or token.start_char

    table.insert(result, delta_line)
    table.insert(result, delta_char)
    table.insert(result, token.length)
    table.insert(result, token.type)
    table.insert(result, token.modifiers)

    prev_line = token.line
    prev_char = token.start_char
  end

  return result
end
```

**Step 3: Commit**

```bash
git add -u && git commit -m "feat(semantic): LSP token encoding"
```

---

## Task 8: Highlights Feature Module

**Files:**
- Create: `lua/tcl-lsp/features/highlights.lua`
- Test: `tests/lua/highlights_spec.lua`

**Step 1: Write the failing test**

```lua
-- tests/lua/highlights_spec.lua
describe("Highlights Feature", function()
  local highlights

  before_each(function()
    package.loaded["tcl-lsp.features.highlights"] = nil
    highlights = require("tcl-lsp.features.highlights")
  end)

  it("should provide semantic token capabilities", function()
    local caps = highlights.get_capabilities()
    assert.is_table(caps.semanticTokensProvider)
    assert.is_table(caps.semanticTokensProvider.legend)
    assert.is_table(caps.semanticTokensProvider.legend.tokenTypes)
    assert.is_table(caps.semanticTokensProvider.legend.tokenModifiers)
    assert.is_true(caps.semanticTokensProvider.full)
  end)

  it("should handle semantic tokens request for buffer", function()
    -- Create test buffer with TCL code
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "proc test {} {}", "  return 1", "}" })
    vim.api.nvim_buf_set_option(bufnr, "filetype", "tcl")

    local result = highlights.handle_semantic_tokens(bufnr)
    assert.is_table(result)
    assert.is_table(result.data)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
```

**Step 2: Implement highlights.lua**

```lua
-- lua/tcl-lsp/features/highlights.lua
local M = {}

local semantic_tokens = require("tcl-lsp.analyzer.semantic_tokens")
local parser = require("tcl-lsp.parser")

function M.get_capabilities()
  return {
    semanticTokensProvider = {
      legend = {
        tokenTypes = semantic_tokens.token_types_legend,
        tokenModifiers = semantic_tokens.token_modifiers_legend,
      },
      full = true,
      delta = false,  -- Phase 1: no delta support yet
    },
  }
end

function M.handle_semantic_tokens(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local code = table.concat(lines, "\n")
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  local ast = parser.parse(code, filepath)
  if not ast then
    return { data = {} }
  end

  local tokens = semantic_tokens.extract_tokens(ast)
  local encoded = semantic_tokens.encode_tokens(tokens)

  return { data = encoded }
end

function M.setup()
  -- Register for TCL/RVT filetypes
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tcl", "rvt" },
    callback = function(args)
      -- Enable semantic tokens for this buffer
      vim.b[args.buf].tcl_lsp_semantic_tokens = true
    end,
  })
end

return M
```

**Step 3: Commit**

```bash
git add lua/tcl-lsp/features/highlights.lua tests/lua/highlights_spec.lua
git commit -m "feat(highlights): add semantic tokens feature module"
```

---

## Task 9: RVT Block Parser

**Files:**
- Create: `lua/tcl-lsp/parser/rvt.lua`
- Test: `tests/lua/rvt_parser_spec.lua`

**Step 1: Write the failing test**

```lua
-- tests/lua/rvt_parser_spec.lua
describe("RVT Parser", function()
  local rvt

  before_each(function()
    package.loaded["tcl-lsp.parser.rvt"] = nil
    rvt = require("tcl-lsp.parser.rvt")
  end)

  it("should detect TCL code blocks", function()
    local content = [[<html>
<? set name "World" ?>
<h1>Hello</h1>
<?= $name ?>
</html>]]
    local blocks = rvt.find_blocks(content)

    assert.equals(2, #blocks)
    assert.equals("code", blocks[1].type)
    assert.equals("expr", blocks[2].type)
  end)

  it("should extract TCL code from blocks", function()
    local content = [[<? set x 1 ?>]]
    local blocks = rvt.find_blocks(content)

    assert.equals(' set x 1 ', blocks[1].code)
    assert.equals(1, blocks[1].start_line)
    assert.equals(3, blocks[1].start_col)  -- after "<?
  end)
end)
```

**Step 2: Implement rvt.lua**

```lua
-- lua/tcl-lsp/parser/rvt.lua
local M = {}

function M.find_blocks(content)
  local blocks = {}
  local line_num = 1
  local col = 1
  local i = 1

  while i <= #content do
    -- Track line/column
    if content:sub(i, i) == "\n" then
      line_num = line_num + 1
      col = 1
      i = i + 1
    elseif content:sub(i, i + 2) == "<?=" then
      -- Expression block
      local end_pos = content:find("?>", i + 3, true)
      if end_pos then
        table.insert(blocks, {
          type = "expr",
          code = content:sub(i + 3, end_pos - 1),
          start_line = line_num,
          start_col = col + 3,
          end_line = line_num,  -- simplified
        })
        i = end_pos + 2
        col = col + (end_pos + 2 - i)
      else
        i = i + 1
        col = col + 1
      end
    elseif content:sub(i, i + 1) == "<?" then
      -- Code block
      local end_pos = content:find("?>", i + 2, true)
      if end_pos then
        table.insert(blocks, {
          type = "code",
          code = content:sub(i + 2, end_pos - 1),
          start_line = line_num,
          start_col = col + 2,
        })
        i = end_pos + 2
      else
        i = i + 1
      end
    else
      i = i + 1
      col = col + 1
    end
  end

  return blocks
end

return M
```

**Step 3: Commit**

```bash
git add lua/tcl-lsp/parser/rvt.lua tests/lua/rvt_parser_spec.lua
git commit -m "feat(rvt): add RVT block parser"
```

---

## Task 10: Integrate RVT with Semantic Tokens

**Files:**
- Modify: `lua/tcl-lsp/features/highlights.lua`
- Modify: `tests/lua/highlights_spec.lua`

**Step 1: Write the failing test**

```lua
  it("should handle RVT files with mixed content", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "<html>",
      "<? proc test {} {} ?>",
      "</html>",
    })
    vim.api.nvim_buf_set_option(bufnr, "filetype", "rvt")

    local result = highlights.handle_semantic_tokens(bufnr)
    assert.is_table(result.data)
    assert.is_true(#result.data > 0)  -- Should have tokens

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
```

**Step 2: Update highlights.lua to handle RVT**

```lua
function M.handle_semantic_tokens(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local code = table.concat(lines, "\n")
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo[bufnr].filetype

  local all_tokens = {}

  if filetype == "rvt" then
    local rvt = require("tcl-lsp.parser.rvt")
    local blocks = rvt.find_blocks(code)

    for _, block in ipairs(blocks) do
      local ast = parser.parse(block.code, filepath)
      if ast then
        local tokens = semantic_tokens.extract_tokens(ast)
        -- Offset tokens by block position
        for _, token in ipairs(tokens) do
          token.line = token.line + block.start_line - 1
          token.start_char = token.start_char + block.start_col - 1
          table.insert(all_tokens, token)
        end
      end
    end
  else
    local ast = parser.parse(code, filepath)
    if ast then
      all_tokens = semantic_tokens.extract_tokens(ast)
    end
  end

  return { data = semantic_tokens.encode_tokens(all_tokens) }
end
```

**Step 3: Commit**

```bash
git add -u && git commit -m "feat(highlights): integrate RVT support"
```

---

## Task 11: Configuration Support

**Files:**
- Modify: `lua/tcl-lsp/config.lua`
- Modify: `tests/lua/config_spec.lua`

**Step 1: Add semantic_tokens config to defaults**

In `config.lua`, add to defaults:

```lua
semantic_tokens = {
  enabled = true,
  debounce_ms = 150,
  large_file_threshold = 1000,
},
```

**Step 2: Add validation and tests**

**Step 3: Commit**

```bash
git add -u && git commit -m "feat(config): add semantic_tokens configuration"
```

---

## Task 12: Wire Up to Init

**Files:**
- Modify: `lua/tcl-lsp/init.lua`

**Step 1: Import and call highlights.setup() in plugin init**

**Step 2: Verify with manual testing**

**Step 3: Commit**

```bash
git add -u && git commit -m "feat(init): wire up semantic highlighting"
```

---

## Summary

| Task | Description | Est. Complexity |
|------|-------------|-----------------|
| 1 | Token type constants | Simple |
| 2 | Token modifiers | Simple |
| 3 | Proc definition extraction | Medium |
| 4 | Parameter extraction | Simple |
| 5 | Variable extraction | Medium |
| 6 | Builtin keyword extraction | Simple |
| 7 | LSP encoding | Medium |
| 8 | Highlights feature module | Medium |
| 9 | RVT block parser | Medium |
| 10 | RVT integration | Simple |
| 11 | Configuration | Simple |
| 12 | Wire up to init | Simple |

**Total: 12 tasks**

Future tasks (not in this plan):
- Delta/incremental updates
- Index integration for enhanced mode
- Namespace tokens
- Comment/string/number tokens
- Large file viewport prioritization
