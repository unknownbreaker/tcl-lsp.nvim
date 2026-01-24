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

local function visit_node(node, refs, filepath, current_namespace)
  if not node then
    return
  end

  if node.type == "namespace_eval" then
    local new_namespace = current_namespace .. "::" .. node.name
    if current_namespace == "::" then
      new_namespace = "::" .. node.name
    end

    -- Recurse with new namespace context
    if node.body and node.body.children then
      for _, child in ipairs(node.body.children) do
        visit_node(child, refs, filepath, new_namespace)
      end
    end
    return
  end

  if node.type == "namespace_export" then
    for _, export_name in ipairs(node.exports or {}) do
      if export_name ~= "*" then
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
    table.insert(refs, {
      type = "export",
      name = node.alias,
      target = node.target,
      file = filepath,
      range = node.range,
      text = "interp alias " .. (node.alias or "") .. " " .. (node.target or ""),
    })
  end

  if node.type == "command" then
    local cmd_name = node.name
    if cmd_name and not BUILTINS[cmd_name] then
      table.insert(refs, {
        type = "call",
        name = cmd_name,
        namespace = current_namespace,
        file = filepath,
        range = node.range,
        text = cmd_name .. " " .. table.concat(node.args or {}, " "),
      })
    end
  end

  -- Handle command_substitution nodes (e.g., [add 1 2] inside set)
  if node.type == "command_substitution" and node.command then
    local cmd = node.command
    -- command is an array-like table: cmd[1] = name, cmd[2+] = args
    local cmd_name = cmd[1]
    if cmd_name and type(cmd_name) == "string" and not BUILTINS[cmd_name] then
      local args = {}
      for i = 2, #cmd do
        table.insert(args, tostring(cmd[i]))
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

  -- Check for command_substitution in set value
  if node.type == "set" and type(node.value) == "table" then
    visit_node(node.value, refs, filepath, current_namespace)
  end

  -- Recurse into children
  if node.children then
    for _, child in ipairs(node.children) do
      visit_node(child, refs, filepath, current_namespace)
    end
  end

  -- Recurse into body (for procs)
  if node.body and node.body.children then
    for _, child in ipairs(node.body.children) do
      visit_node(child, refs, filepath, current_namespace)
    end
  end
end

---Extract all references (calls, exports, aliases) from an AST
---@param ast table The AST to extract references from
---@param filepath string The file path of the source file
---@return table[] List of reference objects
function M.extract_references(ast, filepath)
  local refs = {}
  visit_node(ast, refs, filepath, "::")
  return refs
end

return M
