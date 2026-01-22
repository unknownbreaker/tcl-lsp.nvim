-- lua/tcl-lsp/analyzer/indexer.lua
-- Background Indexer - scans workspace files without blocking the editor

local parser = require("tcl-lsp.parser")
local index = require("tcl-lsp.analyzer.index")
local extractor = require("tcl-lsp.analyzer.extractor")
local ref_extractor = require("tcl-lsp.analyzer.ref_extractor")

local M = {}

local BATCH_SIZE = 5

M.state = {
  status = "idle", -- idle | scanning | ready
  queued = {},
  total_files = 0,
  indexed_count = 0,
  root_dir = nil,
  pending_refs = {}, -- ASTs stored for second pass reference extraction
}

function M.reset()
  M.state = {
    status = "idle",
    queued = {},
    total_files = 0,
    indexed_count = 0,
    root_dir = nil,
    pending_refs = {},
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

  -- Store AST for reference extraction in second pass
  table.insert(M.state.pending_refs, { ast = ast, filepath = filepath })

  return true
end

-- Resolve a reference to its qualified name in the index
-- For calls: tries qualified name, then namespace::name, then ::name
-- For exports: returns the qualified name directly
function M.resolve_ref_target(ref)
  local name = ref.name
  local namespace = ref.namespace or "::"

  -- If already fully qualified (starts with ::), try as-is
  if name:sub(1, 2) == "::" then
    if index.find(name) then
      return name
    end
    return nil
  end

  -- Try namespace::name
  local qualified
  if namespace == "::" then
    qualified = "::" .. name
  else
    qualified = namespace .. "::" .. name
  end
  if index.find(qualified) then
    return qualified
  end

  -- Try global ::name
  qualified = "::" .. name
  if index.find(qualified) then
    return qualified
  end

  return nil
end

-- Second pass: extract references from stored ASTs and resolve to symbols
function M.resolve_references()
  for _, entry in ipairs(M.state.pending_refs) do
    local refs = ref_extractor.extract_references(entry.ast, entry.filepath)
    for _, ref in ipairs(refs) do
      local target = M.resolve_ref_target(ref)
      if target then
        index.add_reference(target, ref)
      end
    end
  end
  -- Clear pending refs after processing
  M.state.pending_refs = {}
end

function M.start(root_dir)
  M.state.root_dir = root_dir
  M.state.queued = M.find_tcl_files(root_dir)
  M.state.total_files = #M.state.queued
  M.state.indexed_count = 0
  M.state.status = "scanning"
  M.state.pending_refs = {} -- Reset for new indexing run

  M.process_batch()
end

function M.process_batch()
  if M.state.status ~= "scanning" then
    return
  end

  for _ = 1, BATCH_SIZE do
    local file = table.remove(M.state.queued, 1)
    if not file then
      -- All files indexed, now resolve references
      M.resolve_references()
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
