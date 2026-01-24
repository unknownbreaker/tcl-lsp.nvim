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

return M
