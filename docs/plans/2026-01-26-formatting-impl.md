# TCL Formatting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a Lua-based TCL code formatter that runs in-process for fast performance.

**Architecture:** Parse TCL code to AST using existing parser, walk AST to determine indent depth for each line, rebuild code with correct indentation and stripped trailing whitespace. Configuration supports auto-detection of indent style.

**Tech Stack:** Lua (Neovim), plenary.nvim (testing), existing TCL parser

---

## Task 1: Add Formatting Configuration to config.lua

**Files:**
- Modify: `lua/tcl-lsp/config.lua`

**Step 1: Add formatting defaults to the defaults table**

In `lua/tcl-lsp/config.lua`, find the `defaults` table and add after `semantic_tokens`:

```lua
  -- Formatting configuration
  formatting = {
    on_save = false,        -- Auto-format on save (default: off)
    indent_size = nil,      -- nil = auto-detect, or 2/4
    indent_style = nil,     -- nil = auto-detect, or "spaces"/"tabs"
  },
```

**Step 2: Verify config still loads**

Run: `make test-unit`
Expected: All tests pass

**Step 3: Commit**

```bash
git add lua/tcl-lsp/config.lua
git commit -m "feat(config): add formatting configuration options"
```

---

## Task 2: Create Formatting Module - Core Structure

**Files:**
- Create: `lua/tcl-lsp/features/formatting.lua`
- Create: `tests/lua/features/formatting_spec.lua`

**Step 1: Write the failing test**

Create `tests/lua/features/formatting_spec.lua`:

```lua
-- tests/lua/features/formatting_spec.lua
-- Tests for formatting feature

describe("Formatting Feature", function()
  local formatting

  before_each(function()
    package.loaded["tcl-lsp.features.formatting"] = nil
    formatting = require("tcl-lsp.features.formatting")
  end)

  describe("setup", function()
    it("should register without error", function()
      local success = pcall(formatting.setup)
      assert.is_true(success)
    end)
  end)

  describe("format_code", function()
    it("should return empty string for empty input", function()
      local result = formatting.format_code("")
      assert.equals("", result)
    end)

    it("should return nil input unchanged", function()
      local result = formatting.format_code(nil)
      assert.is_nil(result)
    end)

    it("should remove trailing whitespace", function()
      local code = "proc foo {} {   \n    puts hello   \n}  "
      local result = formatting.format_code(code)
      assert.is_not_nil(result)
      -- No trailing whitespace on any line
      assert.is_nil(result:match("[ \t]+\n"))
      assert.is_nil(result:match("[ \t]+$"))
    end)

    it("should preserve blank lines", function()
      local code = "proc foo {} {\n\n    puts hello\n}"
      local result = formatting.format_code(code)
      assert.is_not_nil(result)
      -- Should still have a blank line
      assert.is_not_nil(result:match("\n\n"))
    end)
  end)
end)
```

**Step 2: Run test to verify it fails**

Run: `make test-unit`
Expected: FAIL - module not found

**Step 3: Write minimal implementation**

Create `lua/tcl-lsp/features/formatting.lua`:

```lua
-- lua/tcl-lsp/features/formatting.lua
-- Code formatting feature for TCL LSP

local M = {}

--- Format TCL code
---@param code string|nil The TCL code to format
---@param options table|nil Optional formatting options
---@return string|nil Formatted code, or nil if input was nil
function M.format_code(code, options)
  if code == nil then
    return nil
  end

  if code == "" then
    return ""
  end

  options = options or {}

  -- For now, just strip trailing whitespace from each line
  local lines = {}
  for line in (code .. "\n"):gmatch("([^\n]*)\n") do
    -- Remove trailing whitespace
    local trimmed = line:gsub("[ \t]+$", "")
    table.insert(lines, trimmed)
  end

  -- Remove the extra empty line we added
  if #lines > 0 and lines[#lines] == "" and not code:match("\n$") then
    table.remove(lines)
  end

  return table.concat(lines, "\n")
end

--- Set up formatting feature
function M.setup()
  -- Will register commands and autocmds later
end

return M
```

**Step 4: Run test to verify it passes**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/formatting.lua tests/lua/features/formatting_spec.lua
git commit -m "feat(formatting): add formatting module with trailing whitespace removal"
```

---

## Task 3: Add Indentation Detection

**Files:**
- Modify: `lua/tcl-lsp/features/formatting.lua`
- Modify: `tests/lua/features/formatting_spec.lua`

**Step 1: Add failing tests for indent detection**

Add to `tests/lua/features/formatting_spec.lua`:

```lua
  describe("detect_indent", function()
    it("should detect 4-space indent", function()
      local code = "proc foo {} {\n    puts hello\n}"
      local style, size = formatting.detect_indent(code)
      assert.equals("spaces", style)
      assert.equals(4, size)
    end)

    it("should detect 2-space indent", function()
      local code = "proc foo {} {\n  puts hello\n}"
      local style, size = formatting.detect_indent(code)
      assert.equals("spaces", style)
      assert.equals(2, size)
    end)

    it("should detect tab indent", function()
      local code = "proc foo {} {\n\tputs hello\n}"
      local style, size = formatting.detect_indent(code)
      assert.equals("tabs", style)
      assert.equals(1, size)
    end)

    it("should default to 4 spaces for no indentation", function()
      local code = "puts hello"
      local style, size = formatting.detect_indent(code)
      assert.equals("spaces", style)
      assert.equals(4, size)
    end)
  end)
```

**Step 2: Run tests to verify they fail**

Run: `make test-unit`
Expected: FAIL - detect_indent not found

**Step 3: Implement detect_indent**

Add to `lua/tcl-lsp/features/formatting.lua` before `format_code`:

```lua
--- Detect indentation style from code
---@param code string The code to analyze
---@return string style "spaces" or "tabs"
---@return number size Indent size (spaces count or 1 for tabs)
function M.detect_indent(code)
  local tab_count = 0
  local space_counts = {}
  local lines_checked = 0
  local max_lines = 100

  for line in code:gmatch("[^\n]+") do
    if lines_checked >= max_lines then
      break
    end

    -- Check for leading whitespace
    local leading = line:match("^([ \t]+)")
    if leading then
      if leading:match("^\t") then
        tab_count = tab_count + 1
      else
        local spaces = #leading
        -- Only count likely indent levels (2, 4, 6, 8, etc.)
        if spaces > 0 and spaces <= 16 then
          space_counts[spaces] = (space_counts[spaces] or 0) + 1
        end
      end
    end

    lines_checked = lines_checked + 1
  end

  -- If tabs predominate, use tabs
  if tab_count > 0 then
    local total_spaces = 0
    for _, count in pairs(space_counts) do
      total_spaces = total_spaces + count
    end
    if tab_count >= total_spaces then
      return "tabs", 1
    end
  end

  -- Find most common space indent
  local best_size = 4
  local best_count = 0

  -- Check for 2-space indent pattern
  local two_space_score = (space_counts[2] or 0) + (space_counts[4] or 0) + (space_counts[6] or 0)
  -- Check for 4-space indent pattern
  local four_space_score = (space_counts[4] or 0) + (space_counts[8] or 0) + (space_counts[12] or 0)

  if two_space_score > four_space_score and two_space_score > 0 then
    best_size = 2
  elseif four_space_score > 0 then
    best_size = 4
  end

  return "spaces", best_size
end
```

**Step 4: Run tests to verify they pass**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/formatting.lua tests/lua/features/formatting_spec.lua
git commit -m "feat(formatting): add indentation detection"
```

---

## Task 4: Add AST-Based Indentation Fixing

**Files:**
- Modify: `lua/tcl-lsp/features/formatting.lua`
- Modify: `tests/lua/features/formatting_spec.lua`

**Step 1: Add failing tests for indentation fixing**

Add to `tests/lua/features/formatting_spec.lua`:

```lua
  describe("indentation fixing", function()
    it("should fix badly indented proc", function()
      local code = "proc foo {} {\nputs hello\n}"
      local result = formatting.format_code(code)
      -- Should have indentation on the puts line
      assert.is_not_nil(result:match("\n[ \t]+puts"))
    end)

    it("should fix nested if indentation", function()
      local code = "proc foo {} {\nif {1} {\nputs hello\n}\n}"
      local result = formatting.format_code(code)
      -- The puts should be more indented than the if
      local lines = {}
      for line in result:gmatch("[^\n]+") do
        table.insert(lines, line)
      end
      -- lines[2] = "if {1} {" (indent 1)
      -- lines[3] = "puts hello" (indent 2)
      if #lines >= 3 then
        local if_indent = #(lines[2]:match("^([ \t]*)") or "")
        local puts_indent = #(lines[3]:match("^([ \t]*)") or "")
        assert.is_true(puts_indent > if_indent)
      end
    end)

    it("should handle syntax errors gracefully", function()
      local code = "proc foo { missing brace"
      local result = formatting.format_code(code)
      -- Should return original code (with trailing whitespace stripped)
      assert.is_not_nil(result)
      assert.is_true(result:match("proc foo"))
    end)
  end)
```

**Step 2: Run tests to verify they fail**

Run: `make test-unit`
Expected: FAIL - indentation not being applied

**Step 3: Implement AST-based indentation**

Update `format_code` in `lua/tcl-lsp/features/formatting.lua`:

```lua
local parser = require "tcl-lsp.parser"

--- Node types that increase indent depth for their body
local INDENT_NODES = {
  proc = true,
  ["if"] = true,
  ["else"] = true,
  foreach = true,
  ["for"] = true,
  ["while"] = true,
  switch = true,
  namespace = true,
}

--- Build a line-to-indent-depth map from AST
---@param ast table The parsed AST
---@return table Map of line number to indent depth
local function build_indent_map(ast)
  local indent_map = {}

  local function walk(node, depth)
    if not node then return end

    -- Get the range of this node
    local start_line, end_line
    if node.range then
      if node.range.start and node.range.start.line then
        start_line = node.range.start.line
      end
      if node.range.end_pos and node.range.end_pos.line then
        end_line = node.range.end_pos.line
      end
    end

    -- If this is an indent node, mark inner lines with increased depth
    local is_indent_node = node.type and INDENT_NODES[node.type]

    -- Process children with appropriate depth
    local child_depth = is_indent_node and (depth + 1) or depth

    if node.children then
      for _, child in ipairs(node.children) do
        walk(child, child_depth)
      end
    end

    -- Process body (procs, loops)
    if node.body then
      if node.body.children then
        for _, child in ipairs(node.body.children) do
          walk(child, child_depth)
        end
      end
    end

    -- Process then_body, else_body (if statements)
    if node.then_body then
      if node.then_body.children then
        for _, child in ipairs(node.then_body.children) do
          walk(child, child_depth)
        end
      end
    end
    if node.else_body then
      if node.else_body.children then
        for _, child in ipairs(node.else_body.children) do
          walk(child, child_depth)
        end
      end
    end

    -- Mark this node's first line with current depth
    if start_line and node.type and node.type ~= "root" then
      indent_map[start_line] = depth
    end
  end

  walk(ast, 0)
  return indent_map
end

--- Format TCL code
---@param code string|nil The TCL code to format
---@param options table|nil Optional formatting options
---@return string|nil Formatted code, or nil if input was nil
function M.format_code(code, options)
  if code == nil then
    return nil
  end

  if code == "" then
    return ""
  end

  options = options or {}

  -- Detect or use configured indent style
  local indent_style = options.indent_style
  local indent_size = options.indent_size

  if not indent_style or not indent_size then
    local detected_style, detected_size = M.detect_indent(code)
    indent_style = indent_style or detected_style
    indent_size = indent_size or detected_size
  end

  -- Create indent string
  local indent_str
  if indent_style == "tabs" then
    indent_str = "\t"
  else
    indent_str = string.rep(" ", indent_size)
  end

  -- Try to parse for AST-based formatting
  local ast, err = parser.parse(code)
  local indent_map = {}

  if ast then
    indent_map = build_indent_map(ast)
  end

  -- Process lines
  local lines = {}
  local line_num = 1

  for line in (code .. "\n"):gmatch("([^\n]*)\n") do
    -- Remove trailing whitespace
    local content = line:gsub("[ \t]+$", "")

    -- Remove leading whitespace (we'll re-add correct amount)
    local stripped = content:gsub("^[ \t]+", "")

    -- Apply indent based on AST map, or preserve if no AST info
    if stripped ~= "" then
      local depth = indent_map[line_num]
      if depth and depth > 0 then
        content = string.rep(indent_str, depth) .. stripped
      elseif depth == 0 then
        content = stripped
      else
        -- No AST info for this line, keep original indent but strip trailing
        content = content
      end
    end

    table.insert(lines, content)
    line_num = line_num + 1
  end

  -- Handle trailing newline
  if #lines > 0 and lines[#lines] == "" and not code:match("\n$") then
    table.remove(lines)
  end

  return table.concat(lines, "\n")
end
```

**Step 4: Run tests to verify they pass**

Run: `make test-unit`
Expected: PASS (or adjust tests based on actual AST output)

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/formatting.lua tests/lua/features/formatting_spec.lua
git commit -m "feat(formatting): add AST-based indentation fixing"
```

---

## Task 5: Add User Command and Format Buffer

**Files:**
- Modify: `lua/tcl-lsp/features/formatting.lua`
- Modify: `tests/lua/features/formatting_spec.lua`

**Step 1: Add failing tests for format_buffer and command**

Add to `tests/lua/features/formatting_spec.lua`:

```lua
  describe("format_buffer", function()
    it("should format current buffer", function()
      -- Create a test buffer
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "proc foo {} {",
        "puts hello   ",
        "}",
      })

      formatting.format_buffer(bufnr)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      -- Should have removed trailing whitespace
      assert.equals("puts hello", lines[2]:match("^%s*(.-)%s*$"))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("setup", function()
    it("should create TclFormat command", function()
      formatting.setup()
      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands.TclFormat)
    end)
  end)
```

**Step 2: Run tests to verify they fail**

Run: `make test-unit`
Expected: FAIL - format_buffer not working, TclFormat command not created

**Step 3: Implement format_buffer and setup**

Add to `lua/tcl-lsp/features/formatting.lua`:

```lua
--- Format a buffer
---@param bufnr number|nil Buffer number (default: current buffer)
---@return boolean success Whether formatting succeeded
function M.format_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  -- Get buffer content
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local code = table.concat(lines, "\n")

  -- Get formatting options from config
  local config = require("tcl-lsp.config")
  local cfg = config.get(bufnr)
  local fmt_opts = cfg.formatting or {}

  -- Format the code
  local formatted = M.format_code(code, {
    indent_style = fmt_opts.indent_style,
    indent_size = fmt_opts.indent_size,
  })

  if not formatted then
    return false
  end

  -- Only update if changed
  if formatted == code then
    return true
  end

  -- Split back into lines
  local new_lines = {}
  for line in (formatted .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(new_lines, line)
  end

  -- Remove extra trailing empty line if original didn't have one
  if #new_lines > 0 and new_lines[#new_lines] == "" and not code:match("\n$") then
    table.remove(new_lines)
  end

  -- Update buffer
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

  return true
end

--- Set up formatting feature
function M.setup()
  -- Create user command
  vim.api.nvim_create_user_command("TclFormat", function()
    M.format_buffer()
  end, { desc = "Format TCL code" })
end
```

**Step 4: Run tests to verify they pass**

Run: `make test-unit`
Expected: PASS

**Step 5: Commit**

```bash
git add lua/tcl-lsp/features/formatting.lua tests/lua/features/formatting_spec.lua
git commit -m "feat(formatting): add format_buffer and TclFormat command"
```

---

## Task 6: Add Format on Save

**Files:**
- Modify: `lua/tcl-lsp/features/formatting.lua`
- Modify: `tests/lua/features/formatting_spec.lua`

**Step 1: Add test for format on save**

Add to `tests/lua/features/formatting_spec.lua`:

```lua
  describe("format on save", function()
    it("should register autocmd when on_save is true", function()
      -- This test verifies the autocmd is created
      -- Actual formatting is tested in format_buffer tests
      formatting.setup()
      -- Check that autocmd group exists
      local ok = pcall(vim.api.nvim_get_autocmds, {
        group = "TclLspFormatting",
        event = "BufWritePre",
      })
      assert.is_true(ok)
    end)
  end)
```

**Step 2: Update setup to add format on save autocmd**

Update `setup` in `lua/tcl-lsp/features/formatting.lua`:

```lua
--- Set up formatting feature
function M.setup()
  -- Create user command
  vim.api.nvim_create_user_command("TclFormat", function()
    M.format_buffer()
  end, { desc = "Format TCL code" })

  -- Create autocmd group for formatting
  local group = vim.api.nvim_create_augroup("TclLspFormatting", { clear = true })

  -- Format on save (checks config each time)
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    pattern = { "*.tcl", "*.rvt" },
    callback = function(args)
      local config = require("tcl-lsp.config")
      local cfg = config.get(args.buf)
      if cfg.formatting and cfg.formatting.on_save then
        M.format_buffer(args.buf)
      end
    end,
  })
end
```

**Step 3: Run tests to verify they pass**

Run: `make test-unit`
Expected: PASS

**Step 4: Commit**

```bash
git add lua/tcl-lsp/features/formatting.lua tests/lua/features/formatting_spec.lua
git commit -m "feat(formatting): add format on save support"
```

---

## Task 7: Register Formatting in Plugin

**Files:**
- Modify: `lua/tcl-lsp/init.lua`

**Step 1: Add require and setup call**

In `lua/tcl-lsp/init.lua`, add after the folding require:

```lua
local formatting = require "tcl-lsp.features.formatting"
```

And in the `M.setup()` function, after `folding.setup()`:

```lua
  -- Set up formatting feature
  formatting.setup()
```

**Step 2: Add public API function**

Add before `return M`:

```lua
-- Format current buffer (for testing and API)
function M.format(bufnr)
  local formatting_module = require "tcl-lsp.features.formatting"
  return formatting_module.format_buffer(bufnr)
end
```

**Step 3: Verify plugin loads**

Run: `make test-unit`
Expected: All tests pass

**Step 4: Commit**

```bash
git add lua/tcl-lsp/init.lua
git commit -m "feat: register formatting feature in plugin"
```

---

## Task 8: Final Integration Test

**Files:**
- Test all components together

**Step 1: Run full test suite**

Run: `make test`
Expected: All tests pass

**Step 2: Manual verification**

Create a badly indented TCL file and verify:
1. `:TclFormat` command fixes indentation
2. Trailing whitespace is removed
3. Blank lines are preserved

**Step 3: Final commit (if any remaining changes)**

```bash
git add -A
git commit -m "feat(formatting): complete Phase 5 formatting implementation"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Add formatting config | config.lua |
| 2 | Core module + trailing whitespace | formatting.lua, test |
| 3 | Indent detection | formatting.lua, test |
| 4 | AST-based indent fixing | formatting.lua, test |
| 5 | format_buffer + TclFormat command | formatting.lua, test |
| 6 | Format on save | formatting.lua, test |
| 7 | Plugin registration | init.lua |
| 8 | Final integration | verify all |
