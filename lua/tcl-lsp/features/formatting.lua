-- lua/tcl-lsp/features/formatting.lua
-- Code formatting feature for TCL LSP

local M = {}

local parser = require "tcl-lsp.parser"

--- Calculate brace depth for each line
--- Uses brace counting which is more reliable for formatting than AST line numbers
---@param code string The TCL code
---@return table Map of line number to indent depth for that line's content
local function calculate_brace_depth(code)
  local depth_map = {}
  local line_num = 1
  local current_depth = 0

  -- First, split into lines and process each line
  for line in (code .. "\n"):gmatch("([^\n]*)\n") do
    -- Count braces to determine if this line opens or closes a block
    local opens = 0
    local closes = 0
    local in_string = false
    local escape_next = false

    for i = 1, #line do
      local char = line:sub(i, i)

      if escape_next then
        escape_next = false
      elseif char == "\\" then
        escape_next = true
      elseif char == '"' and not in_string then
        in_string = true
      elseif char == '"' and in_string then
        in_string = false
      elseif not in_string then
        if char == "{" then
          opens = opens + 1
        elseif char == "}" then
          closes = closes + 1
        end
      end
    end

    -- Determine the indent depth for this line's content
    -- If line starts with closing brace, it should be outdented
    local stripped = line:gsub("^[ \t]+", "")
    local starts_with_close = stripped:match("^}") ~= nil

    if starts_with_close then
      -- This line's closing brace is at the outer depth
      depth_map[line_num] = math.max(0, current_depth - 1)
    else
      depth_map[line_num] = current_depth
    end

    -- Update depth for next line based on net brace change
    current_depth = current_depth + opens - closes
    current_depth = math.max(0, current_depth)

    line_num = line_num + 1
  end

  return depth_map
end

--- Check if line content is just a closing brace (possibly with whitespace)
---@param content string The line content (already stripped of leading whitespace)
---@return boolean True if line is a closing brace line
local function is_closing_brace_line(content)
  return content:match("^%s*}%s*$") ~= nil or content == "}"
end

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

  -- Detect or use configured indent style
  local indent_style = options.indent_style
  local indent_size = options.indent_size

  if not indent_style or not indent_size then
    local detected_style, detected_size = M.detect_indent(code)
    indent_style = indent_style or detected_style
    indent_size = indent_size or detected_size
  end

  -- Create indent string
  local indent_str
  if indent_style == "tabs" then
    indent_str = "\t"
  else
    indent_str = string.rep(" ", indent_size)
  end

  -- Try to parse to check for syntax errors
  -- If parsing fails, just do basic trailing whitespace cleanup (don't change indentation)
  local ast, _ = parser.parse(code)

  -- Calculate brace-based depth for indentation
  local depth_map = calculate_brace_depth(code)

  -- Process lines
  local lines = {}
  local line_num = 1

  for line in (code .. "\n"):gmatch("([^\n]*)\n") do
    -- Remove trailing whitespace
    local content = line:gsub("[ \t]+$", "")

    -- Get content without leading whitespace
    local stripped = content:gsub("^[ \t]+", "")

    -- Apply indent if we have a valid AST (no syntax errors)
    if ast and stripped ~= "" then
      local depth = depth_map[line_num] or 0

      -- Closing braces should be outdented one level
      if is_closing_brace_line(stripped) then
        depth = math.max(0, depth)
      end

      if depth > 0 then
        content = string.rep(indent_str, depth) .. stripped
      else
        content = stripped
      end
    end
    -- If parse error or empty line, keep content as-is (with trailing whitespace stripped)

    table.insert(lines, content)
    line_num = line_num + 1
  end

  -- Handle trailing newline
  if #lines > 0 and lines[#lines] == "" and not has_trailing_newline then
    table.remove(lines)
  end

  local result = table.concat(lines, "\n")

  if has_trailing_newline and not result:match("\n$") then
    result = result .. "\n"
  end

  return result
end

--- Format a buffer
---@param bufnr number|nil Buffer number (default: current buffer)
---@return boolean success Whether formatting succeeded
function M.format_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  -- Get buffer content
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local code = table.concat(lines, "\n")

  -- Get formatting options from config
  local ok, config = pcall(require, "tcl-lsp.config")
  local fmt_opts = {}
  if ok then
    local cfg = config.get(bufnr)
    fmt_opts = cfg.formatting or {}
  end

  -- Format the code
  local formatted = M.format_code(code, {
    indent_style = fmt_opts.indent_style,
    indent_size = fmt_opts.indent_size,
  })

  if not formatted then
    return false
  end

  -- Only update if changed
  if formatted == code then
    return true
  end

  -- Split back into lines
  local new_lines = {}
  for line in (formatted .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(new_lines, line)
  end

  -- Remove extra trailing empty line if original didn't have one
  if #new_lines > 0 and new_lines[#new_lines] == "" and not code:match("\n$") then
    table.remove(new_lines)
  end

  -- Update buffer
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

  return true
end

--- Set up formatting feature
function M.setup()
  -- Create user command
  vim.api.nvim_create_user_command("TclFormat", function()
    M.format_buffer()
  end, { desc = "Format TCL code" })
end

return M
