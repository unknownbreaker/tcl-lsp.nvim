-- lua/tcl-lsp/features/folding.lua
-- Code folding feature for TCL LSP
-- Extracts fold ranges from parsed AST for foldingRange requests

local M = {}

--- Foldable node types (mirrors TCL ::ast::folding::is_foldable)
local FOLDABLE_TYPES = {
  proc = true,
  ["if"] = true,
  ["elseif"] = true,
  ["else"] = true,
  foreach = true,
  ["for"] = true,
  ["while"] = true,
  switch = true,
  namespace_eval = true,
  oo_class = true,
  oo_method = true,
}

--- Get folding ranges from a buffer
---@param bufnr number Buffer number
---@param filepath string|nil Optional filepath
---@return table[] Array of FoldingRange objects
function M.get_folding_ranges(bufnr, filepath)
  if not bufnr then
    return {}
  end

  -- Parse the buffer (cached by changedtick)
  local cache = require("tcl-lsp.utils.cache")
  local ast, err = cache.parse(bufnr, filepath)
  if not ast then
    return {}
  end

  -- Extract fold ranges from AST
  return M.extract_ranges_from_ast(ast)
end

--- Extract folding ranges from AST
---@param ast table The parsed AST
---@return table[] Array of FoldingRange objects
function M.extract_ranges_from_ast(ast)
  local ranges = {}

  -- Extract from comments (stored at root level)
  if ast.comments then
    local comment_ranges = M.extract_comment_ranges(ast.comments)
    for _, r in ipairs(comment_ranges) do
      table.insert(ranges, r)
    end
  end

  -- Extract from children
  if ast.children then
    for _, child in ipairs(ast.children) do
      M.extract_from_node(child, ranges)
    end
  end

  return ranges
end

--- Extract folding range from a node (recursive)
---@param node table AST node
---@param ranges table[] Accumulator for ranges
function M.extract_from_node(node, ranges)
  if not node or not node.type then
    return
  end

  -- Check if this node is foldable
  if FOLDABLE_TYPES[node.type] then
    local range = M.make_range(node)
    if range then
      table.insert(ranges, range)
    end
  end

  -- Recurse into children
  if node.children then
    for _, child in ipairs(node.children) do
      M.extract_from_node(child, ranges)
    end
  end

  -- Recurse into body (for procs, namespaces, etc.)
  if node.body then
    if node.body.children then
      for _, child in ipairs(node.body.children) do
        M.extract_from_node(child, ranges)
      end
    end
  end

  -- Recurse into then_body (for if statements)
  if node.then_body then
    if node.then_body.children then
      for _, child in ipairs(node.then_body.children) do
        M.extract_from_node(child, ranges)
      end
    end
  end

  -- Recurse into else_body (for if statements)
  if node.else_body then
    if node.else_body.children then
      for _, child in ipairs(node.else_body.children) do
        M.extract_from_node(child, ranges)
      end
    end
  end

  -- Recurse into elseif branches (for if statements)
  if node["elseif"] then
    for _, branch in ipairs(node["elseif"]) do
      M.extract_from_node(branch, ranges)
    end
  end

  -- Recurse into switch cases
  if node.cases then
    for _, case in ipairs(node.cases) do
      M.extract_from_node(case, ranges)
      -- Also recurse into case body
      if case.body and case.body.children then
        for _, child in ipairs(case.body.children) do
          M.extract_from_node(child, ranges)
        end
      end
    end
  end
end

--- Create a FoldingRange from a node
---@param node table AST node with range
---@return table|nil FoldingRange or nil if single-line
function M.make_range(node)
  if not node.range then
    return nil
  end

  local range = node.range
  local start_line, end_line

  -- Handle different range formats from the parser
  -- Format 1: range.start.line and range.end_pos.line
  -- Format 2: range.start_line and range.end_line
  if range.start and range.start.line then
    start_line = range.start.line
  elseif range.start_line then
    start_line = range.start_line
  else
    return nil
  end

  if range.end_pos and range.end_pos.line then
    end_line = range.end_pos.line
  elseif range["end"] and range["end"].line then
    end_line = range["end"].line
  elseif range.end_line then
    end_line = range.end_line
  else
    return nil
  end

  -- Skip single-line constructs (no folding benefit)
  if end_line <= start_line then
    return nil
  end

  -- LSP uses 0-indexed lines, parser uses 1-indexed
  return {
    startLine = start_line - 1,
    endLine = end_line - 1,
    kind = "region",
  }
end

--- Extract folding ranges from consecutive comment lines
---@param comments table[] Array of comment nodes
---@return table[] Array of FoldingRange objects
function M.extract_comment_ranges(comments)
  local ranges = {}

  if not comments or #comments < 2 then
    return ranges
  end

  -- Group consecutive comments
  local groups = {}
  local current_group = {}
  local last_line = -1

  for _, comment in ipairs(comments) do
    if not comment.range then
      goto continue
    end

    local line
    -- Handle different range formats
    if comment.range.start and comment.range.start.line then
      line = comment.range.start.line
    elseif comment.range.start_line then
      line = comment.range.start_line
    else
      goto continue
    end

    if last_line == -1 or line == last_line + 1 then
      table.insert(current_group, { line = line })
    else
      if #current_group >= 2 then
        table.insert(groups, current_group)
      end
      current_group = { { line = line } }
    end

    last_line = line
    ::continue::
  end

  -- Don't forget last group
  if #current_group >= 2 then
    table.insert(groups, current_group)
  end

  -- Create ranges from groups
  for _, group in ipairs(groups) do
    local start_line = group[1].line
    local end_line = group[#group].line

    -- LSP uses 0-indexed lines
    table.insert(ranges, {
      startLine = start_line - 1,
      endLine = end_line - 1,
      kind = "comment",
    })
  end

  return ranges
end

--- Set up folding feature
--- Nothing to set up - folding is requested by the editor on demand
function M.setup()
  -- Folding ranges are requested via textDocument/foldingRange
  -- No user commands or autocommands needed
end

return M
