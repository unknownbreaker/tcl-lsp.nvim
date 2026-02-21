-- lua/tcl-lsp/utils/namespace.lua
-- Namespace qualification helper

local M = {}

--- Qualify a name with a namespace prefix
--- Already-qualified names (starting with ::) are returned as-is.
---@param name string The unqualified name
---@param current_namespace string The current namespace context (e.g., "::" or "::foo")
---@return string The fully qualified name
function M.qualify(name, current_namespace)
  if name:sub(1, 2) == "::" then
    return name
  end
  if current_namespace == "::" then
    return "::" .. name
  end
  return current_namespace .. "::" .. name
end

return M
