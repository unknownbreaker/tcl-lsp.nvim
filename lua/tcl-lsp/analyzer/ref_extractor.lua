-- lua/tcl-lsp/analyzer/ref_extractor.lua
-- Reference Extractor - extracts references (calls, exports, aliases) from AST

local M = {}

-- TCL built-in commands to skip (not user-defined procs)
local BUILTINS = {
  set = true,
  puts = true,
  expr = true,
  ["if"] = true,
  ["else"] = true,
  ["for"] = true,
  foreach = true,
  ["while"] = true,
  switch = true,
  proc = true,
  ["return"] = true,
  ["break"] = true,
  continue = true,
  catch = true,
  try = true,
  throw = true,
  error = true,
  list = true,
  lindex = true,
  llength = true,
  lappend = true,
  lsort = true,
  lsearch = true,
  lrange = true,
  lreplace = true,
  string = true,
  regexp = true,
  regsub = true,
  split = true,
  join = true,
  array = true,
  dict = true,
  incr = true,
  append = true,
  open = true,
  close = true,
  read = true,
  gets = true,
  eof = true,
  file = true,
  glob = true,
  cd = true,
  pwd = true,
  package = true,
  namespace = true,
  variable = true,
  global = true,
  upvar = true,
  info = true,
  rename = true,
  interp = true,
  source = true,
  after = true,
  update = true,
  vwait = true,
}

-- Max recursion depth to prevent infinite loops
local MAX_DEPTH = 50

local function visit_node(node, refs, filepath, current_namespace, depth)
  if not node then
    return
  end

  -- Prevent infinite recursion with depth limit
  depth = depth or 0
  if depth > MAX_DEPTH then
    return
  end

  if node.type == "namespace_eval" then
    local ns_name = node.name
    if type(ns_name) ~= "string" then
      return
    end
    local new_namespace = current_namespace .. "::" .. ns_name
    if current_namespace == "::" then
      new_namespace = "::" .. ns_name
    end

    -- Recurse with new namespace context
    if node.body and node.body.children then
      for _, child in ipairs(node.body.children) do
        visit_node(child, refs, filepath, new_namespace, depth + 1)
      end
    end
    return
  end

  if node.type == "namespace_export" then
    for _, export_name in ipairs(node.exports or {}) do
      if type(export_name) == "string" and export_name ~= "*" then
        table.insert(refs, {
          type = "export",
          name = export_name,
          namespace = current_namespace,
          file = filepath,
          range = node.range,
          text = "namespace export " .. export_name,
        })
      end
    end
  end

  if node.type == "interp_alias" then
    local alias = node.alias
    local target = node.target
    if type(alias) == "string" then
      table.insert(refs, {
        type = "export",
        name = alias,
        target = target,
        file = filepath,
        range = node.range,
        text = "interp alias " .. (alias or "") .. " " .. (type(target) == "string" and target or ""),
      })
    end
  end

  if node.type == "command" then
    local cmd_name = node.name
    if cmd_name and type(cmd_name) == "string" and not BUILTINS[cmd_name] then
      -- Safely build args text (only use string args, limit count)
      local args_text = ""
      if node.args and type(node.args) == "table" then
        local str_args = {}
        for i, arg in ipairs(node.args) do
          if i > 5 then break end  -- Limit to first 5 args
          if type(arg) == "string" then
            table.insert(str_args, arg)
          end
        end
        args_text = table.concat(str_args, " ")
      end
      table.insert(refs, {
        type = "call",
        name = cmd_name,
        namespace = current_namespace,
        file = filepath,
        range = node.range,
        text = cmd_name .. " " .. args_text,
      })
    end
  end

  -- Handle command_substitution nodes (e.g., [add 1 2] inside set)
  if node.type == "command_substitution" and node.command then
    local cmd = node.command
    if type(cmd) == "table" then
      local cmd_name = cmd[1]
      if cmd_name and type(cmd_name) == "string" and not BUILTINS[cmd_name] then
        -- Safely build args (only use string values, limit count)
        local args = {}
        for i = 2, math.min(#cmd, 6) do
          if type(cmd[i]) == "string" then
            table.insert(args, cmd[i])
          end
        end
        table.insert(refs, {
          type = "call",
          name = cmd_name,
          namespace = current_namespace,
          file = filepath,
          range = node.range,
          text = cmd_name .. " " .. table.concat(args, " "),
        })
      end
    end
  end

  -- Check for command_substitution in set value (with type check)
  if node.type == "set" and node.value and type(node.value) == "table" and node.value.type then
    visit_node(node.value, refs, filepath, current_namespace, depth + 1)
  end

  -- Recurse into children
  if node.children and type(node.children) == "table" then
    for _, child in ipairs(node.children) do
      visit_node(child, refs, filepath, current_namespace, depth + 1)
    end
  end

  -- Recurse into body (for procs)
  if node.body and type(node.body) == "table" and node.body.children then
    for _, child in ipairs(node.body.children) do
      visit_node(child, refs, filepath, current_namespace, depth + 1)
    end
  end
end

---Extract all references (calls, exports, aliases) from an AST
---@param ast table The AST to extract references from
---@param filepath string The file path of the source file
---@return table[] List of reference objects
function M.extract_references(ast, filepath)
  local refs = {}
  visit_node(ast, refs, filepath, "::", 0)
  return refs
end

return M
