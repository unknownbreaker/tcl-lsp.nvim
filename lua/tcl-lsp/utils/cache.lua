-- lua/tcl-lsp/utils/cache.lua
-- Per-buffer AST cache keyed on changedtick
-- Wraps parser.parse() / parse_with_errors() to eliminate redundant tclsh spawns

local parser = require("tcl-lsp.parser")

local M = {}

-- Cache store: { [bufnr] = { changedtick, ast, errors, code } }
local store = {}

-- Stats for debugging
local stats = { hits = 0, misses = 0 }

--- Get cached parse result or re-parse if stale
---@param bufnr number Buffer number
---@param filepath string|nil Optional filepath (defaults to buffer name)
---@return table Cache entry with { ast, errors }
local function get_or_parse(bufnr, filepath)
  -- Guard: invalid bufnr falls through to direct parse
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return { ast = nil, errors = { { message = "Invalid buffer" } } }
  end

  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cached = store[bufnr]

  if cached and cached.changedtick == tick then
    stats.hits = stats.hits + 1
    return cached
  end

  -- Cache miss: re-parse
  stats.misses = stats.misses + 1

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local code = table.concat(lines, "\n")
  filepath = filepath or vim.api.nvim_buf_get_name(bufnr)

  local result = parser.parse_with_errors(code, filepath)

  store[bufnr] = {
    changedtick = tick,
    ast = result.ast,
    errors = result.errors,
    code = code,
  }

  return store[bufnr]
end

--- Parse buffer and return AST (same signature as parser.parse)
--- Returns: ast, err (nil on success, error string on failure)
---@param bufnr number Buffer number
---@param filepath string|nil Optional filepath
---@return table|nil ast
---@return string|nil err
function M.parse(bufnr, filepath)
  local entry = get_or_parse(bufnr, filepath)

  if entry.errors and #entry.errors > 0 then
    -- Has errors: mimic parser.parse() behavior (return nil, error_msg)
    if not entry.ast then
      local msgs = {}
      for _, e in ipairs(entry.errors) do
        table.insert(msgs, e.message or "Unknown error")
      end
      return nil, table.concat(msgs, "; ")
    end
  end

  return entry.ast, nil
end

--- Parse buffer and return result with errors preserved
--- Returns: { ast, errors } (same format as parser.parse_with_errors)
---@param bufnr number Buffer number
---@param filepath string|nil Optional filepath
---@return table { ast = table|nil, errors = table }
function M.parse_with_errors(bufnr, filepath)
  local entry = get_or_parse(bufnr, filepath)
  return { ast = entry.ast, errors = entry.errors or {} }
end

--- Invalidate cache for a single buffer
---@param bufnr number Buffer number to invalidate
function M.invalidate(bufnr)
  store[bufnr] = nil
end

--- Clear entire cache
function M.clear()
  store = {}
end

--- Get cache statistics for debugging
---@return table { hits = number, misses = number, size = number }
function M.stats()
  local size = 0
  for _ in pairs(store) do
    size = size + 1
  end
  return { hits = stats.hits, misses = stats.misses, size = size }
end

--- Reset stats counters (for testing)
function M.reset_stats()
  stats = { hits = 0, misses = 0 }
end

return M
