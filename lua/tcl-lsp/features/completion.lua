-- lua/tcl-lsp/features/completion.lua
-- Context-aware autocompletion for TCL/RVT files

local parser = require("tcl-lsp.parser")
local extractor = require("tcl-lsp.analyzer.extractor")

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

return M
