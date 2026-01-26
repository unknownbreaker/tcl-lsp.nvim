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
