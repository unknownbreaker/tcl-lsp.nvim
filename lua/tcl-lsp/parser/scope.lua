-- lua/tcl-lsp/parser/scope.lua
-- Scope Context Builder - extracts scope context from cursor position

local M = {}

--- Check if a position (line, col) is within a range
---@param line number Line number (1-indexed)
---@param col number Column number (1-indexed)
---@param range table|nil Range with start and end_pos
---@return boolean
local function position_in_range(line, col, range)
  if not range then
    return false
  end

  local start = range.start or range.start_pos
  local end_pos = range.end_pos or range["end"]

  if not start or not end_pos then
    return false
  end

  -- Get column values (parser uses 'column', some code uses 'col')
  local start_col = start.col or start.column
  local end_col = end_pos.col or end_pos.column

  if not start.line or not end_pos.line or not start_col or not end_col then
    return false
  end

  -- Check line bounds
  if line < start.line or line > end_pos.line then
    return false
  end

  -- Check column bounds on boundary lines
  if line == start.line and col < start_col then
    return false
  end
  if line == end_pos.line and col > end_col then
    return false
  end

  return true
end

--- Recursively find all nodes that enclose the given position
--- Returns only structural nodes (namespace_eval, proc) that contain the cursor
---@param node table AST node
---@param line number Line number
---@param col number Column number
---@param path table Accumulator for enclosing nodes
---@return table List of enclosing nodes in tree order
local function find_enclosing_nodes(node, line, col, path)
  path = path or {}

  if not node then
    return path
  end

  -- Add this node if position is in its range
  if position_in_range(line, col, node.range) then
    table.insert(path, node)
  end

  -- Check children array
  if node.children then
    for _, child in ipairs(node.children) do
      find_enclosing_nodes(child, line, col, path)
    end
  end

  -- Check body (for procs and namespaces)
  if node.body then
    -- Body might be a node with children
    if node.body.children then
      for _, child in ipairs(node.body.children) do
        find_enclosing_nodes(child, line, col, path)
      end
    end
  end

  return path
end

--- Collect all declarations from a proc's body
--- This includes set, global, and upvar statements
---@param proc_node table The proc node
---@param context table The context to populate
local function collect_proc_declarations(proc_node, context)
  if not proc_node.body or not proc_node.body.children then
    return
  end

  for _, child in ipairs(proc_node.body.children) do
    if child.type == "set" and child.var_name then
      table.insert(context.locals, child.var_name)
    elseif child.type == "global" and child.vars then
      vim.list_extend(context.globals, child.vars)
    elseif child.type == "upvar" and child.local_var then
      context.upvars[child.local_var] = {
        level = child.level,
        other_var = child.other_var,
      }
    end
  end
end

--- Get scope context at cursor position
---@param ast table|nil Parsed AST
---@param line number Line number (1-indexed)
---@param col number Column number (1-indexed)
---@return table Scope context with namespace, proc, locals, globals, upvars
function M.get_context(ast, line, col)
  local context = {
    namespace = "::",
    proc = nil,
    locals = {},
    globals = {},
    upvars = {},
  }

  if not ast then
    return context
  end

  local path = find_enclosing_nodes(ast, line, col, {})

  for _, node in ipairs(path) do
    if node.type == "namespace_eval" then
      -- Build namespace path
      if context.namespace == "::" then
        context.namespace = "::" .. node.name
      else
        context.namespace = context.namespace .. "::" .. node.name
      end
    elseif node.type == "proc" then
      context.proc = node.name
      -- Add params as locals
      if node.params then
        for _, param in ipairs(node.params) do
          table.insert(context.locals, param.name)
        end
      end
      -- Collect all declarations from the proc's body
      collect_proc_declarations(node, context)
    end
  end

  return context
end

return M
