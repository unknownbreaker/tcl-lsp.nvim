-- lua/tcl-lsp/analyzer/extractor.lua
-- Symbol Extractor - extracts symbols (procs, variables, namespaces) from parsed AST

local M = {}

local variable = require("tcl-lsp.utils.variable")
local visitor = require("tcl-lsp.analyzer.visitor")
local namespace_util = require("tcl-lsp.utils.namespace")

function M.extract_symbols(ast, filepath)
  local symbols = {}

  visitor.walk(ast, {
    namespace_eval = function(node, ctx)
      table.insert(symbols, {
        type = "namespace",
        name = node.name,
        qualified_name = ctx.new_namespace,
        file = ctx.filepath,
        range = node.range,
        scope = ctx.namespace,
      })
    end,

    proc = function(node, ctx)
      local proc_name = node.name
      local qualified = namespace_util.qualify(proc_name, ctx.namespace)

      table.insert(symbols, {
        type = "proc",
        name = proc_name,
        qualified_name = qualified,
        file = ctx.filepath,
        range = node.range,
        params = node.params,
        scope = ctx.namespace,
      })
    end,

    set = function(node, ctx)
      local var_name = variable.safe_var_name(node.var_name)
      if not var_name then
        return
      end

      table.insert(symbols, {
        type = "variable",
        name = var_name,
        qualified_name = namespace_util.qualify(var_name, ctx.namespace),
        file = ctx.filepath,
        range = node.range,
        scope = ctx.namespace,
      })
    end,

    variable = function(node, ctx)
      local var_name = variable.safe_var_name(node.name)
      if not var_name then
        return
      end

      table.insert(symbols, {
        type = "variable",
        name = var_name,
        qualified_name = namespace_util.qualify(var_name, ctx.namespace),
        file = ctx.filepath,
        range = node.range,
        scope = ctx.namespace,
      })
    end,
  }, filepath)

  return symbols
end

return M
