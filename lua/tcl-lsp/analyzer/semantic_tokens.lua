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

return M
