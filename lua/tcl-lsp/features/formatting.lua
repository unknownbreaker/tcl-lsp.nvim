-- lua/tcl-lsp/features/formatting.lua
-- Code formatting feature for TCL LSP

local M = {}

--- Detect indentation style from code
---@param code string The code to analyze
---@return string style "spaces" or "tabs"
---@return number size Indent size (spaces count or 1 for tabs)
function M.detect_indent(code)
  if not code or code == "" then
    return "spaces", 4
  end

  local tab_count = 0
  local space_counts = {}
  local lines_checked = 0
  local max_lines = 100

  for line in code:gmatch("[^\n]+") do
    if lines_checked >= max_lines then
      break
    end

    -- Check for leading whitespace
    local leading = line:match("^([ \t]+)")
    if leading then
      if leading:match("^\t") then
        tab_count = tab_count + 1
      else
        local spaces = #leading
        -- Only count likely indent levels (2, 4, 6, 8, etc.)
        if spaces > 0 and spaces <= 16 then
          space_counts[spaces] = (space_counts[spaces] or 0) + 1
        end
      end
    end

    lines_checked = lines_checked + 1
  end

  -- If tabs predominate, use tabs
  if tab_count > 0 then
    local total_spaces = 0
    for _, count in pairs(space_counts) do
      total_spaces = total_spaces + count
    end
    if tab_count >= total_spaces then
      return "tabs", 1
    end
  end

  -- Find most common space indent pattern
  -- Check for 2-space indent pattern (lines with 2, 4, 6 spaces)
  local two_space_score = (space_counts[2] or 0) + (space_counts[4] or 0) + (space_counts[6] or 0)
  -- Check for 4-space indent pattern (lines with 4, 8, 12 spaces)
  local four_space_score = (space_counts[4] or 0) + (space_counts[8] or 0) + (space_counts[12] or 0)

  if two_space_score > four_space_score and two_space_score > 0 then
    return "spaces", 2
  end

  return "spaces", 4
end

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
