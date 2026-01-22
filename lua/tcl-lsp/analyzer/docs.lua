-- lua/tcl-lsp/analyzer/docs.lua
-- Documentation extraction utilities for hover and other features

local M = {}

--- Extract comment block immediately above a target line
--- Walks backwards collecting contiguous # comment lines
---@param lines table Array of source lines (1-indexed)
---@param end_line number Target line number (1-indexed, comments are above this)
---@return string|nil Extracted comment text with # prefixes removed, or nil if none
function M.extract_comments(lines, end_line)
  if end_line <= 1 then
    return nil
  end

  local comment_lines = {}
  local current_line = end_line - 1

  -- Walk backwards collecting comment lines
  while current_line >= 1 do
    local line = lines[current_line]
    local trimmed = line:match("^%s*(.-)%s*$") -- Trim whitespace

    -- Check if line is a comment
    if trimmed:match("^#") then
      -- Extract comment content (remove leading # and optional space)
      local content = trimmed:match("^#%s?(.*)$") or ""
      table.insert(comment_lines, 1, content)
      current_line = current_line - 1
    elseif trimmed == "" then
      -- Blank line - stop collecting
      break
    else
      -- Non-comment, non-blank line - stop collecting
      break
    end
  end

  if #comment_lines == 0 then
    return nil
  end

  return table.concat(comment_lines, "\n")
end

--- Recursively search AST for a set node with the given variable name
--- Protected against circular references via visited table
---@param node table AST node to search
---@param var_name string Variable name to find
---@param visited table|nil Set of already-visited nodes (for cycle detection)
---@return string|nil Value if found, nil otherwise
local function find_set_value(node, var_name, visited)
  -- Initialize visited set on first call
  visited = visited or {}

  -- Guard against nil nodes and circular references
  if not node or visited[node] then
    return nil
  end

  -- Mark this node as visited
  visited[node] = true

  -- Check if this node is a set for our variable
  if node.type == "set" and node.var_name == var_name then
    return node.value
  end

  -- Recurse into children
  if node.children then
    for _, child in ipairs(node.children) do
      local result = find_set_value(child, var_name, visited)
      if result then
        return result
      end
    end
  end

  -- Recurse into body (for namespace_eval, proc, etc.)
  if node.body then
    local result = find_set_value(node.body, var_name, visited)
    if result then
      return result
    end
    if node.body.children then
      for _, child in ipairs(node.body.children) do
        local result_child = find_set_value(child, var_name, visited)
        if result_child then
          return result_child
        end
      end
    end
  end

  return nil
end

--- Get the initial value of a variable from AST
--- Searches for set commands that assign to the variable
---@param ast table Parsed AST
---@param var_name string Variable name to find
---@return string|nil Initial value if found, nil otherwise
function M.get_initial_value(ast, var_name)
  if not ast then
    return nil
  end

  return find_set_value(ast, var_name)
end

return M
