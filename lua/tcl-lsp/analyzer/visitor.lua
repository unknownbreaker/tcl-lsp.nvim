-- lua/tcl-lsp/analyzer/visitor.lua
-- Shared AST walk for all analyzer modules.
-- Traverses: children, body, then_body, else_body, elseif branches, switch cases.

local M = {}

local limits = require("tcl-lsp.utils.limits")
local namespace_util = require("tcl-lsp.utils.namespace")

--- Walk an AST tree, calling handlers for matching node types.
---
--- @param root table The AST root node
--- @param handlers table<string, function> Map of node_type -> function(node, ctx)
---   ctx fields: filepath, namespace (parent), depth, visit(sub_node), new_namespace (namespace_eval only)
--- @param filepath string The source file path
--- @param opts table|nil Optional: { namespace = string (default "::") }
function M.walk(root, handlers, filepath, opts)
  opts = opts or {}
  local initial_namespace = opts.namespace or "::"

  local function visit_node(node, current_namespace, depth)
    if not node then
      return
    end

    depth = depth or 0
    if depth > limits.MAX_DEPTH then
      return
    end

    -- Expose a visit function for handlers that need to recurse into sub-nodes
    local ctx = {
      filepath = filepath,
      namespace = current_namespace,
      depth = depth,
      visit = function(sub_node)
        visit_node(sub_node, current_namespace, depth + 1)
      end,
    }

    -- namespace_eval: compute child namespace, call handler, recurse body, return early
    if node.type == "namespace_eval" then
      local ns_name = node.name
      if type(ns_name) ~= "string" then
        return
      end

      local new_namespace = namespace_util.qualify(ns_name, current_namespace)

      ctx.new_namespace = new_namespace

      local handler = handlers["namespace_eval"]
      if handler then
        handler(node, ctx)
      end

      -- Recurse into body with the new namespace
      if node.body and type(node.body) == "table" and node.body.children then
        for _, child in ipairs(node.body.children) do
          visit_node(child, new_namespace, depth + 1)
        end
      end
      return
    end

    -- Call type-specific handler
    local handler = handlers[node.type]
    if handler then
      handler(node, ctx)
    end

    -- Recurse into children
    if node.children and type(node.children) == "table" then
      for _, child in ipairs(node.children) do
        visit_node(child, current_namespace, depth + 1)
      end
    end

    -- Recurse into body (for procs)
    if node.body and type(node.body) == "table" and node.body.children then
      for _, child in ipairs(node.body.children) do
        visit_node(child, current_namespace, depth + 1)
      end
    end

    -- Recurse into control-flow bodies (if/else/elseif/switch)
    if node.then_body and type(node.then_body) == "table" and node.then_body.children then
      for _, child in ipairs(node.then_body.children) do
        visit_node(child, current_namespace, depth + 1)
      end
    end
    if node.else_body and type(node.else_body) == "table" and node.else_body.children then
      for _, child in ipairs(node.else_body.children) do
        visit_node(child, current_namespace, depth + 1)
      end
    end
    if node["elseif"] and type(node["elseif"]) == "table" then
      for _, branch in ipairs(node["elseif"]) do
        if branch.body and type(branch.body) == "table" and branch.body.children then
          for _, child in ipairs(branch.body.children) do
            visit_node(child, current_namespace, depth + 1)
          end
        end
      end
    end
    if node.cases and type(node.cases) == "table" then
      for _, case in ipairs(node.cases) do
        if case.body and type(case.body) == "table" and case.body.children then
          for _, child in ipairs(case.body.children) do
            visit_node(child, current_namespace, depth + 1)
          end
        end
      end
    end
  end

  visit_node(root, initial_namespace, 0)
end

return M
