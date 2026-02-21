-- lua/tcl-lsp/features/hover.lua
-- Hover feature for TCL LSP - shows symbol info in floating window

local M = {}

local definitions = require("tcl-lsp.analyzer.definitions")
local docs = require("tcl-lsp.analyzer.docs")
local variable = require("tcl-lsp.utils.variable")
local buffer = require("tcl-lsp.utils.buffer")
local notify = require("tcl-lsp.utils.notify")

--- Format parameters for display in proc signature
---@param params table|nil Array of parameter names or {name, default} pairs
---@return string Formatted parameter string like "{arg1 arg2 {opt default}}"
local function format_params(params)
  if not params or #params == 0 then
    return "{}"
  end

  local parts = {}
  for _, param in ipairs(params) do
    if type(param) == "table" then
      -- Optional param with default: {name, default}
      table.insert(parts, string.format("{%s %s}", param[1], param[2]))
    else
      table.insert(parts, param)
    end
  end

  return "{" .. table.concat(parts, " ") .. "}"
end

--- Extract just the filename from a full path
---@param filepath string Full file path
---@return string Just the filename
local function basename(filepath)
  return filepath:match("([^/]+)$") or filepath
end

--- Format hover content for a procedure
---@param symbol table Symbol info with type, name, qualified_name, params, file, range, scope
---@param doc_comment string|nil Extracted documentation comment
---@return string Markdown formatted hover content
function M.format_proc_hover(symbol, doc_comment)
  local lines = {}

  -- Signature in code block
  local params_str = format_params(symbol.params)
  table.insert(lines, "```tcl")
  table.insert(lines, string.format("proc %s %s", symbol.qualified_name, params_str))
  table.insert(lines, "```")

  -- Documentation if present
  if doc_comment and doc_comment ~= "" then
    table.insert(lines, "")
    table.insert(lines, doc_comment)
  end

  -- Location and namespace
  table.insert(lines, "")
  local line_num = symbol.range and symbol.range.start and symbol.range.start.line or 1
  table.insert(lines, string.format("**Location:** `%s:%d`", basename(symbol.file), line_num))
  table.insert(lines, string.format("**Namespace:** `%s`", symbol.scope or "::"))

  return table.concat(lines, "\n")
end

--- Format hover content for a variable
---@param symbol table Symbol info with type, name, qualified_name, file, range, scope
---@param initial_value string|nil Initial value if found
---@param scope_type string Scope description: "local variable", "global variable", "namespace variable"
---@return string Markdown formatted hover content
function M.format_variable_hover(symbol, initial_value, scope_type)
  local lines = {}

  if initial_value then
    -- Show the set command
    table.insert(lines, "```tcl")
    table.insert(lines, string.format("set %s %s", symbol.qualified_name, initial_value))
    table.insert(lines, "```")
  else
    -- Just show the variable name
    table.insert(lines, string.format("**Variable:** `%s`", symbol.qualified_name))
  end

  -- Type and location
  table.insert(lines, "")
  table.insert(lines, string.format("**Type:** %s", scope_type))
  local line_num = symbol.range and symbol.range.start and symbol.range.start.line or 1
  table.insert(lines, string.format("**Location:** `%s:%d`", basename(symbol.file), line_num))
  table.insert(lines, string.format("**Scope:** `%s`", symbol.scope or "::"))

  return table.concat(lines, "\n")
end

--- Determine the scope type of a variable based on context
---@param var_name string Variable name
---@param context table Scope context with locals, globals, namespace
---@return string Scope type description
function M.get_scope_type(var_name, context)
  if not context then
    return "namespace variable"
  end

  -- Check if local
  if context.locals and vim.tbl_contains(context.locals, var_name) then
    return "local variable"
  end

  -- Check if global
  if context.globals and vim.tbl_contains(context.globals, var_name) then
    return "global variable"
  end

  -- Default to namespace variable
  return "namespace variable"
end

--- Handle hover request - main entry point
---@param bufnr number Buffer number
---@param line number Line number (0-indexed)
---@param col number Column number (0-indexed)
---@return string|nil Markdown content for hover, or nil if nothing found
function M.handle_hover(bufnr, line, col)
  -- Validate buffer
  if not buffer.is_valid(bufnr) then
    return nil
  end

  -- Get word under cursor
  local word = vim.fn.expand("<cword>")
  if not word or word == "" then
    return nil
  end

  -- Extract variable name from TCL syntax
  word = variable.extract_variable_name(word)

  -- Parse buffer (cached by changedtick)
  local cache = require("tcl-lsp.utils.cache")
  local ast, _ = cache.parse(bufnr)
  if not ast then
    return nil
  end

  -- Get scope context at cursor position (1-indexed for scope module)
  local scope = require("tcl-lsp.parser.scope")
  local context = scope.get_context(ast, line + 1, col + 1)

  -- Find symbol in index or AST
  local symbol = definitions.find_in_index(word, context)
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  if not symbol then
    -- Try finding in current file AST
    local extractor = require("tcl-lsp.analyzer.extractor")
    local symbols = extractor.extract_symbols(ast, filepath)
    local candidates = definitions.build_candidates(word, context)

    for _, candidate in ipairs(candidates) do
      for _, sym in ipairs(symbols) do
        if sym.qualified_name == candidate or sym.name == word then
          symbol = sym
          break
        end
      end
      if symbol then
        break
      end
    end
  end

  if not symbol then
    return nil
  end

  -- Format based on symbol type
  if symbol.type == "proc" then
    -- Extract doc comment from source lines
    local doc_comment = nil
    if symbol.range and symbol.range.start then
      local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      doc_comment = docs.extract_comments(content, symbol.range.start.line)
    end
    return M.format_proc_hover(symbol, doc_comment)
  elseif symbol.type == "variable" then
    local initial_value = docs.get_initial_value(ast, symbol.name)
    local scope_type = M.get_scope_type(symbol.name, context)
    return M.format_variable_hover(symbol, initial_value, scope_type)
  elseif symbol.type == "namespace" then
    -- Basic namespace hover
    local lines = {
      string.format("**Namespace:** `%s`", symbol.qualified_name),
      "",
      string.format("**Location:** `%s:%d`", basename(symbol.file), symbol.range.start.line),
    }
    return table.concat(lines, "\n")
  end

  return nil
end

--- Set up hover feature
--- Creates user command and registers keymaps for TCL/RVT files
function M.setup()
  -- Create user command for hover
  vim.api.nvim_create_user_command("TclHover", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = pos[1] - 1 -- Convert to 0-indexed
    local col = pos[2]

    local result = M.handle_hover(bufnr, line, col)

    if result then
      -- Display in floating window
      local lines = vim.split(result, "\n")
      vim.lsp.util.open_floating_preview(lines, "markdown", {
        border = "rounded",
        focusable = false,
        max_width = 80,
        max_height = 20,
      })
    else
      notify.notify("No hover information")
    end
  end, { desc = "Show TCL hover information" })

  -- Set up keymap for TCL files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tcl", "rvt" },
    callback = function(args)
      vim.keymap.set("n", "K", "<cmd>TclHover<cr>", {
        buffer = args.buf,
        desc = "Show hover information",
      })
    end,
  })
end

return M
