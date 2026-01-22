-- lua/tcl-lsp/analyzer/extractor.lua
-- Symbol Extractor - extracts symbols (procs, variables, namespaces) from parsed AST

local M = {}

local function visit_node(node, symbols, filepath, current_namespace)
  if not node then
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
        visit_node(child, symbols, filepath, new_namespace)
      end
    end
    return -- Don't process body again below
  end

  if node.type == "proc" then
    local qualified = current_namespace .. "::" .. node.name
    if current_namespace == "::" then
      qualified = "::" .. node.name
    end

    table.insert(symbols, {
      type = "proc",
      name = node.name,
      qualified_name = qualified,
      file = filepath,
      range = node.range,
      params = node.params,
      scope = current_namespace,
    })
  end

  if node.type == "set" then
    local var_name = node.var_name
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

  if node.type == "variable" then
    local var_name = node.name
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

  -- Recurse into children
  if node.children then
    for _, child in ipairs(node.children) do
      visit_node(child, symbols, filepath, current_namespace)
    end
  end

  -- Recurse into body (for procs)
  if node.body and node.body.children then
    for _, child in ipairs(node.body.children) do
      visit_node(child, symbols, filepath, current_namespace)
    end
  end
end

function M.extract_symbols(ast, filepath)
  local symbols = {}
  visit_node(ast, symbols, filepath, "::")
  return symbols
end

return M
