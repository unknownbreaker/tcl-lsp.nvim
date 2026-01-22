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
