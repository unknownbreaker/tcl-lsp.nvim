-- lua/tcl-lsp/analyzer/index.lua
-- Symbol Index - core data structure for storing and looking up symbol definitions

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

return M
