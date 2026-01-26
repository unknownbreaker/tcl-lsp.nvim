-- lua/tcl-lsp/analyzer/indexer.lua
-- Background Indexer - scans workspace files without blocking the editor
-- Uses parallel parsing for speed (configurable concurrency)

local parser = require("tcl-lsp.parser")
local index = require("tcl-lsp.analyzer.index")
local extractor = require("tcl-lsp.analyzer.extractor")
local ref_extractor = require("tcl-lsp.analyzer.ref_extractor")

local M = {}

-- Number of concurrent parse jobs (adjust based on system)
local PARALLEL_JOBS = 6

M.state = {
  status = "idle", -- idle | scanning | ready
  queued = {},
  total_files = 0,
  indexed_count = 0,
  root_dir = nil,
  pending_refs = {}, -- ASTs stored for second pass reference extraction
  active_jobs = 0, -- Current number of running parse jobs
  shutting_down = false, -- Set to true during cleanup to prevent new jobs
}

function M.reset()
  M.state = {
    status = "idle",
    queued = {},
    total_files = 0,
    indexed_count = 0,
    root_dir = nil,
    pending_refs = {},
    active_jobs = 0,
    shutting_down = false,
  }
end

-- Stop all indexing and prevent new jobs from starting
function M.cleanup()
  M.state.shutting_down = true
  M.state.queued = {}
  M.state.status = "idle"
end

function M.get_status()
  return {
    status = M.state.status,
    total = M.state.total_files,
    indexed = M.state.indexed_count,
    active_jobs = M.state.active_jobs,
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

-- Synchronous index_file (used for single-file re-indexing on save)
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

  -- Parse to AST (sync)
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

-- Async index_file (used for background batch indexing)
-- callback(success) is called when done
function M.index_file_async(filepath, callback)
  -- Remove old symbols from this file
  index.remove_file(filepath)

  -- Read file content
  local f = io.open(filepath, "r")
  if not f then
    callback(false)
    return
  end
  local content = f:read("*all")
  f:close()

  -- Parse to AST asynchronously
  parser.parse_async(content, filepath, function(ast, err)
    if not ast then
      callback(false)
      return
    end

    -- Extract and index symbols
    local symbols = extractor.extract_symbols(ast, filepath)
    for _, symbol in ipairs(symbols) do
      index.add_symbol(symbol)
    end

    -- Store AST for reference extraction in second pass
    table.insert(M.state.pending_refs, { ast = ast, filepath = filepath })

    callback(true)
  end)
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

-- Called when a file finishes indexing
local function on_file_complete()
  -- Ignore callbacks if we're shutting down
  if M.state.shutting_down then
    return
  end

  M.state.indexed_count = M.state.indexed_count + 1
  M.state.active_jobs = M.state.active_jobs - 1

  -- Try to start more jobs
  M.fill_job_slots()
end

-- Start indexing a single file (async)
local function start_file_job(filepath)
  M.state.active_jobs = M.state.active_jobs + 1

  M.index_file_async(filepath, function(success)
    -- Schedule completion handler to avoid deep callback nesting
    vim.schedule(on_file_complete)
  end)
end

-- Fill available job slots with queued files
function M.fill_job_slots()
  -- Don't start new jobs if we're shutting down
  if M.state.shutting_down then
    return
  end

  if M.state.status ~= "scanning" then
    return
  end

  -- Start jobs until we hit the limit or run out of files
  while M.state.active_jobs < PARALLEL_JOBS and #M.state.queued > 0 do
    local file = table.remove(M.state.queued, 1)
    start_file_job(file)
  end

  -- Check if we're done (no active jobs and no queued files)
  if M.state.active_jobs == 0 and #M.state.queued == 0 then
    -- All files indexed, now resolve references
    M.resolve_references()
    M.state.status = "ready"

    -- Notify user
    vim.schedule(function()
      vim.notify(
        string.format("TCL index ready: %d files", M.state.indexed_count),
        vim.log.levels.INFO
      )
    end)
  end
end

function M.start(root_dir)
  M.state.root_dir = root_dir
  M.state.queued = M.find_tcl_files(root_dir)
  M.state.total_files = #M.state.queued
  M.state.indexed_count = 0
  M.state.status = "scanning"
  M.state.pending_refs = {}
  M.state.active_jobs = 0

  if M.state.total_files == 0 then
    M.state.status = "ready"
    return
  end

  -- Start parallel processing
  M.fill_job_slots()
end

-- Legacy function for compatibility
function M.process_next_file()
  M.fill_job_slots()
end

-- Legacy function for compatibility
function M.process_batch()
  M.fill_job_slots()
end

return M
