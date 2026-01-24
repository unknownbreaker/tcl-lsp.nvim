-- lua/tcl-lsp/analyzer/semantic_tokens.lua
-- Semantic token extraction for TCL LSP

local M = {}

-- LSP standard token types (indices match LSP spec)
-- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#semanticTokenTypes
M.token_types_legend = {
  "namespace",   -- 0
  "type",        -- 1
  "class",       -- 2
  "enum",        -- 3
  "interface",   -- 4
  "function",    -- 5
  "method",      -- 6
  "property",    -- 7
  "variable",    -- 8
  "string",      -- 9
  "parameter",   -- 10
  "keyword",     -- 11
  "comment",     -- 12
  "operator",    -- 13
  "macro",       -- 14 (custom)
  "decorator",   -- 15 (custom)
}

-- Build reverse lookup (name -> index, 0-based for LSP)
M.token_types = {}
for i, name in ipairs(M.token_types_legend) do
  local key = name
  if name == "function" then
    key = "function_"  -- Lua reserved word
  end
  M.token_types[key] = i - 1
end

-- LSP standard token modifiers (bitmask values)
M.token_modifiers_legend = {
  "declaration",    -- bit 0 (1)
  "definition",     -- bit 1 (2)
  "readonly",       -- bit 2 (4)
  "static",         -- bit 3 (8)
  "deprecated",     -- bit 4 (16)
  "modification",   -- bit 5 (32)
  "defaultLibrary", -- bit 6 (64)
  "documentation",  -- bit 7 (128)
  "async",          -- bit 8 (256)
}

-- Build modifier bitmask lookup
M.token_modifiers = {}
for i, name in ipairs(M.token_modifiers_legend) do
  M.token_modifiers[name] = bit.lshift(1, i - 1)
end

-- Length of "proc " keyword including trailing space
local PROC_KEYWORD_LENGTH = 5

-- Combine multiple modifiers into a single bitmask
function M.combine_modifiers(modifier_names)
  local result = 0
  for _, name in ipairs(modifier_names or {}) do
    if M.token_modifiers[name] then
      result = bit.bor(result, M.token_modifiers[name])
    end
  end
  return result
end

-- Extract semantic tokens from AST
function M.extract_tokens(ast)
  local tokens = {}

  local function visit(node)
    if not node then
      return
    end

    if node.type == "proc" then
      -- Extract proc name token
      -- Note: This assumes "proc name" format with single space.
      -- Qualified names like "proc ::ns::name" will have incorrect start_char.
      -- TODO: Use name_range from AST if available for accurate positioning.
      if node.name and node.range then
        table.insert(tokens, {
          line = node.range.start.line,
          start_char = node.range.start.column + PROC_KEYWORD_LENGTH,
          length = #node.name,
          type = M.token_types.function_,
          modifiers = M.token_modifiers.definition,
        })

        -- Extract parameter tokens
        -- Note: Same limitation as proc name - position calculation assumes
        -- single space separators. Params with defaults or multi-line won't be positioned correctly.
        -- TODO: Use param_range from AST if available for accurate positioning.
        if node.params and #node.params > 0 then
          -- Start after "proc <name> {" = proc_keyword + name_length + space + brace
          local param_offset = PROC_KEYWORD_LENGTH + #node.name + 2 -- +1 space +1 brace

          for _, param in ipairs(node.params) do
            if param.name then
              table.insert(tokens, {
                line = node.range.start.line,
                start_char = node.range.start.column + param_offset,
                length = #param.name,
                type = M.token_types.parameter,
                modifiers = M.token_modifiers.declaration,
                text = param.name,
              })
              -- Move offset: param_name_length + 1 for space separator
              param_offset = param_offset + #param.name + 1
            end
          end
        end
      end
    end

    -- Recurse into children
    if node.children then
      for _, child in ipairs(node.children) do
        visit(child)
      end
    end
    if node.body and node.body.children then
      for _, child in ipairs(node.body.children) do
        visit(child)
      end
    end
  end

  visit(ast)
  return tokens
end

return M
