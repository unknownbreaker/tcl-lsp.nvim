-- lua/tcl-lsp/features/completion.lua
-- Context-aware autocompletion for TCL/RVT files

local extractor = require("tcl-lsp.analyzer.extractor")
local builtins = require("tcl-lsp.data.builtins")
local packages = require("tcl-lsp.data.packages")
local index = require("tcl-lsp.analyzer.index")
local config = require("tcl-lsp.config")

local M = {}

--- Map symbol types to LSP CompletionItemKind
local KIND_MAP = {
  proc = vim.lsp.protocol.CompletionItemKind.Function,
  variable = vim.lsp.protocol.CompletionItemKind.Variable,
  builtin = vim.lsp.protocol.CompletionItemKind.Keyword,
  namespace = vim.lsp.protocol.CompletionItemKind.Module,
  package = vim.lsp.protocol.CompletionItemKind.Module,
}

--- Build a completion item from a symbol
---@param symbol table Symbol with name, type fields
---@return table LSP completion item
function M.build_completion_item(symbol)
  return {
    label = symbol.name,
    kind = KIND_MAP[symbol.type] or vim.lsp.protocol.CompletionItemKind.Text,
    detail = symbol.type,
    insertText = symbol.name,
  }
end

--- Detect completion context from line text
---@param line_text string The line text
---@param col number Column position (1-indexed)
---@return string Context type: "variable", "namespace", "package", or "command"
function M.detect_context(line_text, col)
  local before_cursor = line_text:sub(1, col)

  -- Check for variable context: $varname
  if before_cursor:match("%$[%w_]*$") then
    return "variable"
  end

  -- Check for namespace context: ::ns:: or ::ns::name
  if before_cursor:match("::[%w_:]*$") then
    return "namespace"
  end

  -- Check for package require context
  if before_cursor:match("package%s+require%s+[%w_:]*$") then
    return "package"
  end

  return "command"
end

--- Extract symbols from buffer for completion
---@param bufnr number Buffer number
---@param filepath string File path
---@return table List of symbols
function M.get_file_symbols(bufnr, filepath)
  local cache = require("tcl-lsp.utils.cache")
  local ast = cache.parse(bufnr, filepath)
  if not ast then
    return {}
  end

  return extractor.extract_symbols(ast, filepath)
end

--- Get all completions for the given position
---@param bufnr number Buffer number
---@param line number Line number (1-indexed)
---@param col number Column number (0-indexed)
---@param filepath string File path
---@return table List of completion items
function M.get_completions(bufnr, line, col, filepath)
  local items = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local code = table.concat(lines, "\n")
  local all_lines = vim.split(code, "\n", { plain = true })
  local line_text = all_lines[line] or ""

  -- Detect context
  local context = M.detect_context(line_text, col)

  -- Get symbols from current file
  local file_symbols = M.get_file_symbols(bufnr, filepath)

  -- Get symbols from index (project-wide)
  local index_symbols = {}
  for _, symbol in pairs(index.symbols) do
    table.insert(index_symbols, symbol)
  end

  if context == "variable" then
    -- Variables only
    for _, sym in ipairs(file_symbols) do
      if sym.type == "variable" then
        table.insert(items, M.build_completion_item(sym))
      end
    end
    for _, sym in ipairs(index_symbols) do
      if sym.type == "variable" then
        table.insert(items, M.build_completion_item(sym))
      end
    end
  elseif context == "package" then
    -- Packages only
    for _, pkg_name in ipairs(packages) do
      table.insert(items, {
        label = pkg_name,
        kind = vim.lsp.protocol.CompletionItemKind.Module,
        detail = "package",
        insertText = pkg_name,
      })
    end
  elseif context == "namespace" then
    -- Namespace-qualified procs and namespaces
    for _, sym in ipairs(file_symbols) do
      if sym.type == "proc" or sym.type == "namespace" then
        table.insert(items, M.build_completion_item(sym))
      end
    end
    for _, sym in ipairs(index_symbols) do
      if sym.type == "proc" or sym.type == "namespace" then
        table.insert(items, M.build_completion_item(sym))
      end
    end
  else
    -- Command context: procs, builtins, namespaces
    for _, sym in ipairs(file_symbols) do
      if sym.type == "proc" or sym.type == "namespace" then
        table.insert(items, M.build_completion_item(sym))
      end
    end
    for _, sym in ipairs(index_symbols) do
      if sym.type == "proc" or sym.type == "namespace" then
        table.insert(items, M.build_completion_item(sym))
      end
    end
    for _, builtin in ipairs(builtins.list) do
      table.insert(items, M.build_completion_item(builtin))
    end
  end

  return items
end

--- Omnifunc for TCL completion
---@param findstart number 1 to find start, 0 to get completions
---@param base string Prefix to complete (when findstart=0)
---@return number|table Start column or completion items
function M.omnifunc(findstart, base)
  if findstart == 1 then
    -- Find start of completion
    local line = vim.fn.getline(".")
    local col = vim.fn.col(".") - 1

    -- Walk backwards to find start of word
    while col > 0 do
      local char = line:sub(col, col)
      if char:match("[%w_:]") or char == "$" then
        col = col - 1
      else
        break
      end
    end

    return col
  else
    -- Get completions
    local cfg = config.get()
    if not cfg.completion.enabled then
      return {}
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = pos[1]
    local col = pos[2]
    local filepath = vim.api.nvim_buf_get_name(bufnr)

    local items = M.get_completions(bufnr, line, col, filepath)

    -- Filter by base prefix
    if base and base ~= "" then
      local filtered = {}
      local base_lower = base:lower()
      for _, item in ipairs(items) do
        if item.label:lower():sub(1, #base) == base_lower then
          table.insert(filtered, item)
        end
      end
      items = filtered
    end

    -- Convert to omnifunc format
    local results = {}
    for _, item in ipairs(items) do
      table.insert(results, {
        word = item.insertText,
        abbr = item.label,
        kind = item.detail,
        menu = "[TCL]",
      })
    end

    return results
  end
end

--- Set up completion for TCL files
function M.setup()
  -- Set omnifunc for TCL files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tcl", "rvt" },
    callback = function(args)
      vim.bo[args.buf].omnifunc = "v:lua.require'tcl-lsp.features.completion'.omnifunc"
    end,
  })
end

return M
