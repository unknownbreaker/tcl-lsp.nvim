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

--- Prepare workspace edit from references
---@param refs table List of references from find-references
---@param old_name string The current symbol name
---@param new_name string The new symbol name
---@return table workspace_edit LSP WorkspaceEdit structure
function M.prepare_workspace_edit(refs, old_name, new_name)
  local changes = {}

  for _, ref in ipairs(refs) do
    local uri = vim.uri_from_fname(ref.file)

    if not changes[uri] then
      changes[uri] = {}
    end

    -- Calculate the edit range
    -- Range is 0-indexed for LSP, but our refs use 1-indexed lines
    local start_line = (ref.range and ref.range.start and ref.range.start.line or 1) - 1
    local start_col = ref.range and ref.range.start and (ref.range.start.col or ref.range.start.column or 1) or 1

    -- Find where the symbol name starts in the text
    local text = ref.text or ""
    local name_start = text:find(old_name, 1, true)
    if name_start then
      start_col = start_col + name_start - 1
    end

    local end_col = start_col + #old_name

    table.insert(changes[uri], {
      range = {
        start = { line = start_line, character = start_col - 1 },
        ["end"] = { line = start_line, character = end_col - 1 },
      },
      newText = new_name,
    })
  end

  return { changes = changes }
end

return M
