-- lua/tcl-lsp/parser/schema.lua
-- AST Schema Definitions
-- Defines expected structure of all AST node types for validation

local M = {}

-- Type validators - functions that check if a value matches a type
M.types = {
  string = function(v)
    return type(v) == "string"
  end,

  number = function(v)
    return type(v) == "number"
  end,

  boolean = function(v)
    return type(v) == "boolean"
  end,

  array = function(v)
    return type(v) == "table" and vim.islist(v)
  end,

  object = function(v)
    if type(v) ~= "table" then
      return false
    end
    -- Empty table is considered an object (not a list)
    if next(v) == nil then
      return true
    end
    return not vim.islist(v)
  end,

  any = function(_)
    return true
  end,

  -- TCL-compatible boolean (accepts 0/1 as well as true/false)
  tcl_boolean = function(v)
    if type(v) == "boolean" then
      return true
    end
    if type(v) == "number" and (v == 0 or v == 1) then
      return true
    end
    return false
  end,

  -- TCL-compatible array (accepts empty string as empty array)
  tcl_array = function(v)
    if type(v) == "table" and vim.islist(v) then
      return true
    end
    if type(v) == "string" and v == "" then
      return true
    end
    return false
  end,
}

-- Position schema (line, column)
M.position = {
  line = { required = true, type = "number" },
  column = { required = true, type = "number" },
}

-- Range schema (start, end_pos)
M.range = {
  start = {
    required = true,
    type = "object",
    fields = {
      line = { required = true, type = "number" },
      column = { required = true, type = "number" },
    },
  },
  end_pos = {
    required = true,
    type = "object",
    fields = {
      line = { required = true, type = "number" },
      column = { required = true, type = "number" },
    },
  },
}

-- Body schema (children array)
M.body = {
  children = { required = true, type = "array" },
}

-- Parameter schema (for proc parameters)
M.param = {
  name = { required = true, type = "string" },
  default = { required = false, type = "string" },
  is_varargs = { required = false, type = "boolean" },
}

-- Common field definitions used across multiple nodes
local common = {
  type_field = { required = true, type = "string" },
  range_field = { required = true, type = "object", fields = M.range },
  depth_field = { required = true, type = "number" },
  body_field = { required = true, type = "object", fields = M.body },
}

-- Node schemas - defines structure of each AST node type
M.nodes = {
  -- Root node
  root = {
    fields = {
      type = common.type_field,
      children = { required = true, type = "tcl_array" },
      filepath = { required = false, type = "string" },
      comments = { required = false, type = "any" },
      had_error = { required = false, type = "tcl_boolean" },
      errors = { required = false, type = "tcl_array" },
    },
  },

  -- Procedure node
  proc = {
    fields = {
      type = common.type_field,
      name = { required = true, type = "string" },
      params = { required = true, type = "array", item_schema = M.param },
      body = common.body_field,
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Set (variable assignment) node
  set = {
    fields = {
      type = common.type_field,
      var_name = { required = true, type = "string" },
      value = { required = true, type = "any" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Variable declaration node
  variable = {
    fields = {
      type = common.type_field,
      name = { required = true, type = "string" },
      value = { required = false, type = "any" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Global declaration node
  global = {
    fields = {
      type = common.type_field,
      vars = { required = true, type = "array" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Upvar node
  upvar = {
    fields = {
      type = common.type_field,
      level = { required = true, type = "string" },
      other_var = { required = true, type = "string" },
      local_var = { required = false, type = "string" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Array operation node
  array = {
    fields = {
      type = common.type_field,
      operation = { required = true, type = "string" },
      array_name = { required = true, type = "string" },
      args = { required = false, type = "array" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- If statement node
  ["if"] = {
    fields = {
      type = common.type_field,
      condition = { required = true, type = "string" },
      then_body = common.body_field,
      else_body = { required = false, type = "object", fields = M.body },
      elseif_branches = { required = false, type = "array" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- While loop node
  ["while"] = {
    fields = {
      type = common.type_field,
      condition = { required = true, type = "string" },
      body = common.body_field,
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- For loop node
  ["for"] = {
    fields = {
      type = common.type_field,
      init = { required = true, type = "string" },
      condition = { required = true, type = "string" },
      increment = { required = true, type = "string" },
      body = common.body_field,
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Foreach loop node
  foreach = {
    fields = {
      type = common.type_field,
      var_name = { required = true, type = "string" },
      list = { required = true, type = "string" },
      body = common.body_field,
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Switch statement node
  switch = {
    fields = {
      type = common.type_field,
      expression = { required = true, type = "string" },
      cases = { required = true, type = "array" },
      option = { required = false, type = "string" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Namespace eval node (namespace eval name {body})
  namespace_eval = {
    fields = {
      type = common.type_field,
      name = { required = true, type = "string" },
      body = { required = true, type = "any" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Generic namespace node (for unrecognized subcommands)
  namespace = {
    fields = {
      type = common.type_field,
      subcommand = { required = false, type = "string" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Namespace import node
  namespace_import = {
    fields = {
      type = common.type_field,
      patterns = { required = true, type = "array" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Namespace export node
  namespace_export = {
    fields = {
      type = common.type_field,
      exports = { required = true, type = "array" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Package node (generic)
  package = {
    fields = {
      type = common.type_field,
      package_name = { required = false, type = "string" },
      version = { required = false, type = "string" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Package require node
  package_require = {
    fields = {
      type = common.type_field,
      package_name = { required = true, type = "string" },
      version = { required = false, type = "string" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Package provide node
  package_provide = {
    fields = {
      type = common.type_field,
      package_name = { required = true, type = "string" },
      version = { required = false, type = "string" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Source node
  source = {
    fields = {
      type = common.type_field,
      filepath = { required = true, type = "string" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Expr node
  expr = {
    fields = {
      type = common.type_field,
      expression = { required = true, type = "string" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- List node
  list = {
    fields = {
      type = common.type_field,
      elements = { required = true, type = "array" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Lappend node
  lappend = {
    fields = {
      type = common.type_field,
      var_name = { required = true, type = "string" },
      value = { required = true, type = "any" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Puts node
  puts = {
    fields = {
      type = common.type_field,
      args = { required = true, type = "array" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },

  -- Error node
  error = {
    fields = {
      type = common.type_field,
      message = { required = true, type = "string" },
      range = { required = false, type = "object", fields = M.range },
    },
  },

  -- Command substitution node
  command_substitution = {
    fields = {
      type = common.type_field,
      command = { required = true, type = "string" },
    },
  },

  -- Generic command node (fallback)
  command = {
    fields = {
      type = common.type_field,
      name = { required = true, type = "string" },
      args = { required = false, type = "array" },
      range = common.range_field,
      depth = common.depth_field,
    },
  },
}

-- Get schema for a specific node type
function M.get_schema_for_type(node_type)
  return M.nodes[node_type]
end

-- Get list of all known node types
function M.get_all_node_types()
  local types = {}
  for node_type, _ in pairs(M.nodes) do
    table.insert(types, node_type)
  end
  table.sort(types)
  return types
end

-- Check if a node type is known
function M.is_known_node_type(node_type)
  return M.nodes[node_type] ~= nil
end

return M
