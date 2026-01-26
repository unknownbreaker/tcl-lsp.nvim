-- lua/tcl-lsp/features/formatting.lua
-- Code formatting feature for TCL LSP

local M = {}

--- Format TCL code
---@param code string|nil The TCL code to format
---@param options table|nil Optional formatting options
---@return string|nil Formatted code, or nil if input was nil
function M.format_code(code, options)
  if code == nil then
    return nil
  end

  if code == "" then
    return ""
  end

  options = options or {}

  local has_trailing_newline = code:match("\n$") ~= nil

  -- Split into lines, strip trailing whitespace from each
  local lines = {}
  for line in (code .. "\n"):gmatch("([^\n]*)\n") do
    -- Remove trailing whitespace
    local trimmed = line:gsub("[ \t]+$", "")
    table.insert(lines, trimmed)
  end

  -- Remove the extra empty line we added if original didn't have trailing newline
  if #lines > 0 and lines[#lines] == "" and not has_trailing_newline then
    table.remove(lines)
  end

  local result = table.concat(lines, "\n")

  -- Restore trailing newline if original had one
  if has_trailing_newline and not result:match("\n$") then
    result = result .. "\n"
  end

  return result
end

--- Set up formatting feature
function M.setup()
  -- Will register commands and autocmds in later tasks
end

return M
