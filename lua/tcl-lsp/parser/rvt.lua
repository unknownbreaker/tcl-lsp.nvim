-- lua/tcl-lsp/parser/rvt.lua
-- RVT (Rivet template) block parser
-- Detects and extracts TCL code blocks from RVT templates
-- <? ... ?> for code blocks, <?= ... ?> for expression blocks

local M = {}

---Check if a filepath is an RVT file
---@param filepath string The file path to check
---@return boolean
function M.is_rvt_file(filepath)
  if not filepath then
    return false
  end
  return filepath:match("%.rvt$") ~= nil
end

---Find all TCL blocks in RVT content
---@param content string The RVT template content
---@return table[] List of block objects with type, code, start_line, start_col, end_line
function M.find_blocks(content)
  if not content or content == "" then
    return {}
  end

  local blocks = {}
  local line_num = 1
  local col = 1
  local i = 1
  local len = #content

  while i <= len do
    local char = content:sub(i, i)

    -- Track line/column for newlines
    if char == "\n" then
      line_num = line_num + 1
      col = 1
      i = i + 1
    elseif content:sub(i, i + 2) == "<?=" then
      -- Expression block: <?= ... ?>
      local start_line = line_num
      local start_col = col + 3  -- Position after "<?="
      local end_pos = content:find("?>", i + 3, true)

      if end_pos then
        -- Count newlines within the block to find end_line
        local block_content = content:sub(i + 3, end_pos - 1)
        local end_line = start_line
        for _ in block_content:gmatch("\n") do
          end_line = end_line + 1
        end

        table.insert(blocks, {
          type = "expr",
          code = block_content,
          start_line = start_line,
          start_col = start_col,
          end_line = end_line,
        })

        -- Update position tracking
        -- Count newlines between current position and end
        local skipped = content:sub(i, end_pos + 1)
        local newlines_in_skipped = 0
        local last_newline_pos = 0
        for pos in skipped:gmatch("()\n") do
          newlines_in_skipped = newlines_in_skipped + 1
          last_newline_pos = pos
        end

        if newlines_in_skipped > 0 then
          line_num = line_num + newlines_in_skipped
          col = #skipped - last_newline_pos + 1
        else
          col = col + #skipped
        end

        i = end_pos + 2
      else
        -- Unclosed block, skip
        col = col + 1
        i = i + 1
      end
    elseif content:sub(i, i + 1) == "<?" then
      -- Code block: <? ... ?>
      local start_line = line_num
      local start_col = col + 2  -- Position after "<?"
      local end_pos = content:find("?>", i + 2, true)

      if end_pos then
        -- Count newlines within the block to find end_line
        local block_content = content:sub(i + 2, end_pos - 1)
        local end_line = start_line
        for _ in block_content:gmatch("\n") do
          end_line = end_line + 1
        end

        table.insert(blocks, {
          type = "code",
          code = block_content,
          start_line = start_line,
          start_col = start_col,
          end_line = end_line,
        })

        -- Update position tracking
        local skipped = content:sub(i, end_pos + 1)
        local newlines_in_skipped = 0
        local last_newline_pos = 0
        for pos in skipped:gmatch("()\n") do
          newlines_in_skipped = newlines_in_skipped + 1
          last_newline_pos = pos
        end

        if newlines_in_skipped > 0 then
          line_num = line_num + newlines_in_skipped
          col = #skipped - last_newline_pos + 1
        else
          col = col + #skipped
        end

        i = end_pos + 2
      else
        -- Unclosed block, skip
        col = col + 1
        i = i + 1
      end
    else
      col = col + 1
      i = i + 1
    end
  end

  return blocks
end

return M
