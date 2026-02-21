-- lua/tcl-lsp/utils/variable.lua
-- Shared variable utilities for TCL variable name handling

local M = {}

--- Safely extract a string variable name from a var_name field.
--- TCL parser emits var_name as string OR table (for array access like arr($key)).
--- Returns the base name string, or nil if the field is unusable.
---@param field any The var_name or name field from an AST node
---@return string|nil
function M.safe_var_name(field)
  if type(field) == "string" then
    return field
  end
  if type(field) == "table" and field.name then
    return field.name
  end
  return nil
end

--- Extract variable name from TCL variable syntax.
--- Handles: $var, ${var}, $arr(key), $::ns::var, ${ns::var}
---@param word string Raw word that may contain variable syntax
---@return string Extracted variable name
function M.extract_variable_name(word)
  if word:sub(1, 1) ~= "$" then
    return word
  end

  -- Remove leading $
  word = word:sub(2)

  -- Handle braced: ${varname} or ${ns::var}
  if word:sub(1, 1) == "{" then
    local closing = word:find("}")
    if closing then
      return word:sub(2, closing - 1)
    end
    return word:sub(2) -- Unclosed brace, best effort
  end

  -- Handle array: $arr(key) - extract just the array name
  local paren = word:find("%(")
  if paren then
    return word:sub(1, paren - 1)
  end

  -- Simple or qualified: $var or $::ns::var
  return word
end

return M
