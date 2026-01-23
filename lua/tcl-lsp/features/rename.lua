-- lua/tcl-lsp/features/rename.lua
-- Rename feature for TCL LSP

local M = {}

local index = require("tcl-lsp.analyzer.index")

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

--- Check if new name conflicts with existing symbols in scope
---@param new_name string The proposed new name
---@param scope string The scope to check (e.g., "::" or "::namespace")
---@param current_name string The current symbol name (to exclude from conflict check)
---@return boolean has_conflict True if conflict exists
---@return string|nil message Conflict description
function M.check_conflicts(new_name, scope, current_name)
  -- If renaming to same name, no conflict
  if new_name == current_name then
    return false, nil
  end

  -- Build qualified name to check
  local qualified_to_check
  if scope == "::" then
    qualified_to_check = "::" .. new_name
  else
    qualified_to_check = scope .. "::" .. new_name
  end

  -- Check if symbol exists
  local existing = index.find(qualified_to_check)
  if existing then
    return true, string.format("Symbol '%s' already exists in scope %s", new_name, scope)
  end

  return false, nil
end

return M
