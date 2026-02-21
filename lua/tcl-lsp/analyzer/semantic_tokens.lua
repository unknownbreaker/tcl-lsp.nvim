-- lua/tcl-lsp/analyzer/semantic_tokens.lua
-- Semantic token extraction for TCL LSP

local M = {}

local variable = require("tcl-lsp.utils.variable")

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

-- Length of "set " keyword including trailing space
local SET_KEYWORD_LENGTH = 4

-- TCL built-in commands (keywords with defaultLibrary modifier)
-- Commands that get their own node type
local BUILTIN_NODE_TYPES = {
  ["if"] = true,
  ["while"] = true,
  ["for"] = true,
  foreach = true,
  switch = true,
  proc = true,
  set = true,
  global = true,
  upvar = true,
  variable = true,
  array = true,
  namespace_eval = true,
  namespace_export = true,
  package_require = true,
  package_provide = true,
  source = true,
  expr = true,
  list = true,
  lappend = true,
  puts = true,
}

-- Commands that become generic "command" nodes
local BUILTIN_COMMANDS = {
  ["return"] = true,
  ["break"] = true,
  continue = true,
  catch = true,
  try = true,
  throw = true,
  error = true,
  lindex = true,
  llength = true,
  lsort = true,
  lsearch = true,
  lrange = true,
  lreplace = true,
  string = true,
  regexp = true,
  regsub = true,
  split = true,
  join = true,
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
  info = true,
  rename = true,
  interp = true,
  after = true,
  update = true,
  vwait = true,
}

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

    -- Extract variable tokens from set commands
    -- Note: Position calculation assumes "set varname" format with single space.
    -- TODO: Use var_range from AST if available for accurate positioning.
    if node.type == "set" then
      local var_name = variable.safe_var_name(node.var_name)
      if var_name and node.range then
        table.insert(tokens, {
          line = node.range.start.line,
          start_char = node.range.start.column + SET_KEYWORD_LENGTH,
          length = #var_name,
          type = M.token_types.variable,
          modifiers = M.token_modifiers.modification,
          text = var_name,
        })
      end
    end

    -- Extract keyword tokens for builtin commands
    -- Handle nodes with specific types (if, while, for, foreach, etc.)
    if BUILTIN_NODE_TYPES[node.type] and node.range then
      -- Get the keyword name from node type (e.g., "if", "while")
      -- For compound types like "namespace_eval", extract just "namespace"
      local keyword = node.type
      if keyword:find("_") then
        keyword = keyword:match("^([^_]+)")
      end
      table.insert(tokens, {
        line = node.range.start.line,
        start_char = node.range.start.column,
        length = #keyword,
        type = M.token_types.keyword,
        modifiers = M.token_modifiers.defaultLibrary,
        text = keyword,
      })
    end

    -- Handle generic command nodes that are builtins (puts, return, break, etc.)
    if node.type == "command" and node.name and BUILTIN_COMMANDS[node.name] and node.range then
      table.insert(tokens, {
        line = node.range.start.line,
        start_char = node.range.start.column,
        length = #node.name,
        type = M.token_types.keyword,
        modifiers = M.token_modifiers.defaultLibrary,
        text = node.name,
      })
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
    -- Handle if statement bodies (then_body, else_body, elseif)
    if node.then_body and node.then_body.children then
      for _, child in ipairs(node.then_body.children) do
        visit(child)
      end
    end
    if node.else_body and node.else_body.children then
      for _, child in ipairs(node.else_body.children) do
        visit(child)
      end
    end
    if node["elseif"] then
      for _, branch in ipairs(node["elseif"]) do
        if branch.body and branch.body.children then
          for _, child in ipairs(branch.body.children) do
            visit(child)
          end
        end
      end
    end
    -- Handle switch cases
    if node.cases then
      for _, case in ipairs(node.cases) do
        if case.body and case.body.children then
          for _, child in ipairs(case.body.children) do
            visit(child)
          end
        end
      end
    end
  end

  visit(ast)
  return tokens
end

-- Encode tokens to LSP semantic tokens format
-- Returns flat array: [deltaLine, deltaStartChar, length, tokenType, tokenModifiers, ...]
function M.encode_tokens(tokens)
  -- Sort by position
  table.sort(tokens, function(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return a.start_char < b.start_char
  end)

  local result = {}
  local prev_line = 1
  local prev_char = 0

  for _, token in ipairs(tokens) do
    local delta_line = token.line - prev_line
    local delta_char = delta_line == 0 and (token.start_char - prev_char) or token.start_char

    table.insert(result, delta_line)
    table.insert(result, delta_char)
    table.insert(result, token.length)
    table.insert(result, token.type)
    table.insert(result, token.modifiers)

    prev_line = token.line
    prev_char = token.start_char
  end

  return result
end

return M
