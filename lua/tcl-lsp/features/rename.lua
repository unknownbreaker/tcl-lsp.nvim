-- lua/tcl-lsp/features/rename.lua
-- Rename feature for TCL LSP

local M = {}

--- Validate a new symbol name
---@param name string The proposed new name
---@return boolean ok True if valid
---@return string|nil error Error message if invalid
function M.validate_name(name)
  -- Check empty
  if not name or name:match("^%s*$") then
    return false, "Name cannot be empty"
  end

  -- Trim whitespace
  name = name:gsub("^%s+", ""):gsub("%s+$", "")

  -- TCL identifiers: alphanumeric, underscore, and :: for namespaces
  -- Pattern allows colons; we validate namespace separators separately below
  if not name:match("^[%a_:][%w_:]*$") then
    return false, "Invalid identifier: must contain only letters, numbers, underscores, and :: for namespaces"
  end

  -- Reject invalid colon usage (only :: is valid for namespaces)
  -- Replace all valid :: with empty, then check if any : remains
  local without_ns = name:gsub("::", "")
  if without_ns:match(":") then
    return false, "Invalid namespace separator"
  end

  return true, nil
end

return M
