-- lua/tcl-lsp/analyzer/indexer.lua
-- Background Indexer - scans workspace files without blocking the editor

local parser = require("tcl-lsp.parser")
local index = require("tcl-lsp.analyzer.index")
local extractor = require("tcl-lsp.analyzer.extractor")

local M = {}

local BATCH_SIZE = 5

M.state = {
  status = "idle", -- idle | scanning | ready
  queued = {},
  total_files = 0,
  indexed_count = 0,
  root_dir = nil,
}

function M.reset()
  M.state = {
    status = "idle",
    queued = {},
    total_files = 0,
    indexed_count = 0,
    root_dir = nil,
  }
end

function M.get_status()
  return {
    status = M.state.status,
    total = M.state.total_files,
    indexed = M.state.indexed_count,
  }
end

function M.find_tcl_files(root_dir)
  local files = {}

  local tcl_files = vim.fn.globpath(root_dir, "**/*.tcl", false, true)
  vim.list_extend(files, tcl_files)

  local rvt_files = vim.fn.globpath(root_dir, "**/*.rvt", false, true)
  vim.list_extend(files, rvt_files)

  return files
end

function M.index_file(filepath)
  -- Remove old symbols from this file
  index.remove_file(filepath)

  -- Read file content
  local f = io.open(filepath, "r")
  if not f then
    return false
  end
  local content = f:read("*all")
  f:close()

  -- Parse to AST
  local ast = parser.parse(content, filepath)
  if not ast then
    return false
  end

  -- Extract and index symbols
  local symbols = extractor.extract_symbols(ast, filepath)
  for _, symbol in ipairs(symbols) do
    index.add_symbol(symbol)
  end

  return true
end

function M.start(root_dir)
  M.state.root_dir = root_dir
  M.state.queued = M.find_tcl_files(root_dir)
  M.state.total_files = #M.state.queued
  M.state.indexed_count = 0
  M.state.status = "scanning"

  M.process_batch()
end

function M.process_batch()
  if M.state.status ~= "scanning" then
    return
  end

  for _ = 1, BATCH_SIZE do
    local file = table.remove(M.state.queued, 1)
    if not file then
      M.state.status = "ready"
      return
    end

    M.index_file(file)
    M.state.indexed_count = M.state.indexed_count + 1
  end

  -- Yield to editor, continue next tick
  vim.defer_fn(M.process_batch, 1)
end

return M
