-- lua/tcl-lsp/analyzer/definitions.lua
-- Definition Resolver - finds definitions given cursor position, using scope context and index

local M = {}

local index = require("tcl-lsp.analyzer.index")

--- Build qualified name candidates for a word given context
--- Tries current namespace first, then global namespace
---@param word string The unqualified symbol name
---@param context table Scope context with namespace, proc, locals, globals, upvars
---@return table List of candidate qualified names to search
function M.build_candidates(word, context)
  local candidates = {}

  -- Unqualified name first
  table.insert(candidates, word)

  -- Qualified with current namespace (if not global)
  if context.namespace ~= "::" then
    table.insert(candidates, context.namespace .. "::" .. word)
  end

  -- Global namespace
  table.insert(candidates, "::" .. word)

  return candidates
end

--- Find a symbol definition in the index
---@param word string The symbol name to find
---@param context table Scope context with namespace, proc, locals, globals, upvars
---@return table|nil Symbol entry from index, or nil if not found
function M.find_in_index(word, context)
  -- Skip if it's a local variable (locals don't have index entries)
  if vim.tbl_contains(context.locals, word) then
    return nil
  end

  -- Check upvars - follow the binding to the original variable
  if context.upvars and context.upvars[word] then
    word = context.upvars[word].other_var
  end

  -- Check globals - look directly in global namespace
  if vim.tbl_contains(context.globals, word) then
    local symbol = index.find("::" .. word)
    if symbol then
      return symbol
    end
  end

  -- Try each candidate in order (current namespace first, then global)
  local candidates = M.build_candidates(word, context)
  for _, candidate in ipairs(candidates) do
    local symbol = index.find(candidate)
    if symbol then
      return symbol
    end
  end

  return nil
end

--- Find a symbol definition within a single file's AST
--- Used as fallback when symbol not found in cross-file index
---@param ast table Parsed AST
---@param word string Symbol name to find
---@param context table Scope context
---@param filepath string Path to the file
---@return table|nil LSP location format: { uri, range }
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

--- Main entry point: find definition for symbol at cursor position
---@param bufnr number Buffer number
---@param line number Line number (1-indexed)
---@param col number Column number (1-indexed)
---@return table|nil LSP location format: { uri, range }, or nil if not found
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

  -- Get scope context at cursor position
  local scope = require("tcl-lsp.parser.scope")
  local context = scope.get_context(ast, line, col)

  -- First try the cross-file index
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

return M
