-- lua/tcl-lsp/analyzer/ref_extractor.lua
-- Reference Extractor - extracts references (calls, exports, aliases) from AST

local M = {}

local builtins = require("tcl-lsp.data.builtins")
local visitor = require("tcl-lsp.analyzer.visitor")

---Extract all references (calls, exports, aliases) from an AST
---@param ast table The AST to extract references from
---@param filepath string The file path of the source file
---@return table[] List of reference objects
function M.extract_references(ast, filepath)
  local refs = {}

  visitor.walk(ast, {
    namespace_export = function(node, ctx)
      for _, export_name in ipairs(node.exports or {}) do
        if type(export_name) == "string" and export_name ~= "*" then
          table.insert(refs, {
            type = "export",
            name = export_name,
            namespace = ctx.namespace,
            file = ctx.filepath,
            range = node.range,
            text = "namespace export " .. export_name,
          })
        end
      end
    end,

    interp_alias = function(node, ctx)
      local alias = node.alias
      local target = node.target
      if type(alias) == "string" then
        table.insert(refs, {
          type = "export",
          name = alias,
          target = target,
          file = ctx.filepath,
          range = node.range,
          text = "interp alias " .. (alias or "") .. " " .. (type(target) == "string" and target or ""),
        })
      end
    end,

    command = function(node, ctx)
      local cmd_name = node.name
      if cmd_name and type(cmd_name) == "string" and not builtins.is_builtin[cmd_name] then
        local args_text = ""
        if node.args and type(node.args) == "table" then
          local str_args = {}
          for i, arg in ipairs(node.args) do
            if i > 5 then
              break
            end
            if type(arg) == "string" then
              table.insert(str_args, arg)
            end
          end
          args_text = table.concat(str_args, " ")
        end
        table.insert(refs, {
          type = "call",
          name = cmd_name,
          namespace = ctx.namespace,
          file = ctx.filepath,
          range = node.range,
          text = cmd_name .. " " .. args_text,
        })
      end
    end,

    command_substitution = function(node, ctx)
      if not node.command then
        return
      end
      local cmd = node.command
      if type(cmd) == "table" then
        local cmd_name = cmd[1]
        if cmd_name and type(cmd_name) == "string" and not builtins.is_builtin[cmd_name] then
          local args = {}
          for i = 2, math.min(#cmd, 6) do
            if type(cmd[i]) == "string" then
              table.insert(args, cmd[i])
            end
          end
          table.insert(refs, {
            type = "call",
            name = cmd_name,
            namespace = ctx.namespace,
            file = ctx.filepath,
            range = node.range,
            text = cmd_name .. " " .. table.concat(args, " "),
          })
        end
      end
    end,

    set = function(node, ctx)
      -- Check for command_substitution in set value
      if node.value and type(node.value) == "table" and node.value.type then
        ctx.visit(node.value)
      end
    end,
  }, filepath)

  return refs
end

return M
