-- lua/tcl-lsp/parser/validator.lua
-- AST Schema Validator
-- Validates AST nodes against defined schemas

local M = {}

local schema = require "tcl-lsp.parser.schema"

-- Validate a value against a type
local function validate_type(value, expected_type)
  local validator = schema.types[expected_type]
  if validator then
    return validator(value)
  end
  return false
end

-- Validate nested fields (e.g., range.start.line)
local function validate_nested_fields(value, field_schema, path, errors, options)
  if field_schema.fields then
    for field_name, field_def in pairs(field_schema.fields) do
      local field_value = value[field_name]
      local field_path = path .. "." .. field_name

      if field_def.required and field_value == nil then
        table.insert(errors, {
          message = string.format("Missing required field '%s'", field_name),
          path = field_path,
          node_type = nil,
        })
        if not options.strict then
          return false
        end
      elseif field_value ~= nil then
        if not validate_type(field_value, field_def.type) then
          table.insert(errors, {
            message = string.format(
              "Field '%s' has wrong type: expected %s, got %s",
              field_name,
              field_def.type,
              type(field_value)
            ),
            path = field_path,
            node_type = nil,
          })
          if not options.strict then
            return false
          end
        elseif field_def.fields then
          -- Recursively validate nested structure
          local nested_valid =
            validate_nested_fields(field_value, field_def, field_path, errors, options)
          if not nested_valid and not options.strict then
            return false
          end
        end
      end
    end
  end
  return #errors == 0
end

-- Validate a single AST node
function M.validate_node(node, path, options)
  options = options or { strict = true }
  local errors = {}

  -- Check node is a table
  if type(node) ~= "table" then
    table.insert(errors, {
      message = "Node must be a table, got " .. type(node),
      path = path,
      node_type = nil,
    })
    return { valid = false, errors = errors }
  end

  -- Check type field exists
  local node_type = node.type
  if node_type == nil then
    table.insert(errors, {
      message = "Missing required 'type' field",
      path = path,
      node_type = nil,
    })
    return { valid = false, errors = errors }
  end

  -- Check if node type is known
  local node_schema = schema.get_schema_for_type(node_type)
  if not node_schema then
    table.insert(errors, {
      message = string.format("Unknown node type: '%s'", node_type),
      path = path,
      node_type = node_type,
    })
    return { valid = false, errors = errors }
  end

  -- Validate fields against schema
  for field_name, field_def in pairs(node_schema.fields) do
    local field_value = node[field_name]
    local field_path = path .. "." .. field_name

    -- Check required fields
    if field_def.required and field_value == nil then
      table.insert(errors, {
        message = string.format("Missing required field '%s' for node type '%s'", field_name, node_type),
        path = field_path,
        node_type = node_type,
      })
      if not options.strict then
        break
      end
    elseif field_value ~= nil then
      -- Check type
      if not validate_type(field_value, field_def.type) then
        table.insert(errors, {
          message = string.format(
            "Field '%s' has wrong type: expected %s, got %s",
            field_name,
            field_def.type,
            type(field_value)
          ),
          path = field_path,
          node_type = node_type,
        })
        if not options.strict then
          break
        end
      elseif field_def.fields and field_def.type == "object" then
        -- Validate nested structure (e.g., range)
        local initial_error_count = #errors
        validate_nested_fields(field_value, field_def, field_path, errors, options)
        if #errors > initial_error_count then
          -- Update node_type for nested errors
          for i = initial_error_count + 1, #errors do
            errors[i].node_type = node_type
          end
          if not options.strict then
            break
          end
        end
      end
    end
  end

  return {
    valid = #errors == 0,
    errors = errors,
  }
end

-- Recursively validate an AST and collect errors
local function validate_ast_recursive(node, path, errors, options)
  -- Validate current node
  local result = M.validate_node(node, path, options)
  for _, err in ipairs(result.errors) do
    table.insert(errors, err)
    if not options.strict then
      return false
    end
  end

  -- Validate children if present
  if node.children and type(node.children) == "table" then
    for i, child in ipairs(node.children) do
      local child_path = path .. ".children[" .. i .. "]"
      local continue = validate_ast_recursive(child, child_path, errors, options)
      if not continue and not options.strict then
        return false
      end
    end
  end

  -- Validate body.children if present (for proc, if, while, etc.)
  if node.body and type(node.body) == "table" and node.body.children then
    for i, child in ipairs(node.body.children) do
      local child_path = path .. ".body.children[" .. i .. "]"
      local continue = validate_ast_recursive(child, child_path, errors, options)
      if not continue and not options.strict then
        return false
      end
    end
  end

  -- Validate then_body.children if present (for if statements)
  if node.then_body and type(node.then_body) == "table" and node.then_body.children then
    for i, child in ipairs(node.then_body.children) do
      local child_path = path .. ".then_body.children[" .. i .. "]"
      local continue = validate_ast_recursive(child, child_path, errors, options)
      if not continue and not options.strict then
        return false
      end
    end
  end

  -- Validate else_body.children if present (for if statements)
  if node.else_body and type(node.else_body) == "table" and node.else_body.children then
    for i, child in ipairs(node.else_body.children) do
      local child_path = path .. ".else_body.children[" .. i .. "]"
      local continue = validate_ast_recursive(child, child_path, errors, options)
      if not continue and not options.strict then
        return false
      end
    end
  end

  -- Validate elseif_branches if present
  if node.elseif_branches and type(node.elseif_branches) == "table" then
    for i, branch in ipairs(node.elseif_branches) do
      if branch.body and type(branch.body) == "table" and branch.body.children then
        for j, child in ipairs(branch.body.children) do
          local child_path = path .. ".elseif_branches[" .. i .. "].body.children[" .. j .. "]"
          local continue = validate_ast_recursive(child, child_path, errors, options)
          if not continue and not options.strict then
            return false
          end
        end
      end
    end
  end

  -- Validate switch cases if present
  if node.cases and type(node.cases) == "table" then
    for i, case in ipairs(node.cases) do
      if case.body and type(case.body) == "table" and case.body.children then
        for j, child in ipairs(case.body.children) do
          local child_path = path .. ".cases[" .. i .. "].body.children[" .. j .. "]"
          local continue = validate_ast_recursive(child, child_path, errors, options)
          if not continue and not options.strict then
            return false
          end
        end
      end
    end
  end

  return true
end

-- Validate an entire AST
function M.validate_ast(ast, options)
  options = options or { strict = true }
  local errors = {}

  validate_ast_recursive(ast, "root", errors, options)

  return {
    valid = #errors == 0,
    errors = errors,
  }
end

-- Validate a TCL file by parsing it and validating the AST
function M.validate_file(filepath)
  -- Check if file exists
  if vim.fn.filereadable(filepath) == 0 then
    return {
      valid = false,
      errors = {
        {
          message = "File not found or not readable: " .. filepath,
          path = "file",
          node_type = nil,
        },
      },
    }
  end

  -- Parse the file
  local parser = require "tcl-lsp.parser.ast"
  local ast, parse_err = parser.parse_file(filepath)

  if parse_err then
    return {
      valid = false,
      errors = {
        {
          message = "Parse error: " .. parse_err,
          path = "parse",
          node_type = nil,
        },
      },
    }
  end

  if not ast then
    return {
      valid = false,
      errors = {
        {
          message = "Parser returned nil AST",
          path = "parse",
          node_type = nil,
        },
      },
    }
  end

  -- Validate the AST
  return M.validate_ast(ast, { strict = true })
end

return M
