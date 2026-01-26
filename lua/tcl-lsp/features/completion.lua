-- lua/tcl-lsp/features/completion.lua
-- Context-aware autocompletion for TCL/RVT files

local parser = require("tcl-lsp.parser")
local extractor = require("tcl-lsp.analyzer.extractor")
local builtins = require("tcl-lsp.data.builtins")
local packages = require("tcl-lsp.data.packages")
local index = require("tcl-lsp.analyzer.index")

local M = {}

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

return M
