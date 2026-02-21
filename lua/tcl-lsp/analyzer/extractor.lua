-- lua/tcl-lsp/analyzer/extractor.lua
-- Symbol Extractor - extracts symbols (procs, variables, namespaces) from parsed AST

local M = {}

local variable = require("tcl-lsp.utils.variable")

local MAX_DEPTH = 50

local function visit_node(node, symbols, filepath, current_namespace, depth)
  if not node then
    return
  end

  depth = depth or 0
  if depth > MAX_DEPTH then
    return
  end

  if node.type == "namespace_eval" then
    local new_namespace = current_namespace .. "::" .. node.name
    if current_namespace == "::" then
      new_namespace = "::" .. node.name
    end

    table.insert(symbols, {
      type = "namespace",
      name = node.name,
      qualified_name = new_namespace,
      file = filepath,
      range = node.range,
      scope = current_namespace,
    })

    -- Recurse with new namespace context
    if node.body and node.body.children then
      for _, child in ipairs(node.body.children) do
        visit_node(child, symbols, filepath, new_namespace, depth + 1)
      end
    end
    return -- Don't process body again below
  end

  if node.type == "proc" then
    local proc_name = node.name
    local qualified
    -- If proc name is already fully qualified (starts with ::), use as-is
    if proc_name:sub(1, 2) == "::" then
      qualified = proc_name
    elseif current_namespace == "::" then
      qualified = "::" .. proc_name
    else
      qualified = current_namespace .. "::" .. proc_name
    end

    table.insert(symbols, {
      type = "proc",
      name = proc_name,
      qualified_name = qualified,
      file = filepath,
      range = node.range,
      params = node.params,
      scope = current_namespace,
    })
  end

  if node.type == "set" then
    local var_name = variable.safe_var_name(node.var_name)

    if var_name then
      local qualified = current_namespace .. "::" .. var_name
      if current_namespace == "::" then
        qualified = "::" .. var_name
      end

      table.insert(symbols, {
        type = "variable",
        name = var_name,
        qualified_name = qualified,
        file = filepath,
        range = node.range,
        scope = current_namespace,
      })
    end
  end

  if node.type == "variable" then
    local var_name = variable.safe_var_name(node.name)

    if var_name then
      local qualified = current_namespace .. "::" .. var_name
      if current_namespace == "::" then
        qualified = "::" .. var_name
      end

      table.insert(symbols, {
        type = "variable",
        name = var_name,
        qualified_name = qualified,
        file = filepath,
        range = node.range,
        scope = current_namespace,
      })
    end
  end

  -- Recurse into children
  if node.children then
    for _, child in ipairs(node.children) do
      visit_node(child, symbols, filepath, current_namespace, depth + 1)
    end
  end

  -- Recurse into body (for procs)
  if node.body and node.body.children then
    for _, child in ipairs(node.body.children) do
      visit_node(child, symbols, filepath, current_namespace, depth + 1)
    end
  end
end

function M.extract_symbols(ast, filepath)
  local symbols = {}
  visit_node(ast, symbols, filepath, "::")
  return symbols
end

return M
