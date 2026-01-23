-- lua/tcl-lsp/features/diagnostics.lua
-- Diagnostics feature - surfaces parser syntax errors

local parser = require("tcl-lsp.parser")

local M = {}

-- Diagnostic namespace (created in setup)
local ns = nil

-- Setup diagnostics feature
function M.setup()
  ns = vim.api.nvim_create_namespace("tcl-lsp")

  -- Configure diagnostic display
  vim.diagnostic.config({
    virtual_text = { source = "if_many" },
    signs = true,
    underline = true,
  }, ns)

  -- Register autocmd for on-save diagnostics
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("TclLspDiagnostics", { clear = true }),
    pattern = { "*.tcl", "*.rvt" },
    callback = function(args)
      M.check_buffer(args.buf)
    end,
  })
end

-- Check buffer for syntax errors and publish diagnostics
function M.check_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Ensure namespace exists
  if not ns then
    ns = vim.api.nvim_create_namespace("tcl-lsp")
  end

  -- Get buffer content
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok then
    return
  end

  local content = table.concat(lines, "\n")
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  -- Parse and get errors (wrapped in pcall for safety)
  local ok, result = pcall(parser.parse_with_errors, content, filepath)
  if not ok or not result or type(result) ~= "table" then
    return
  end

  local diagnostics = {}

  for _, err in ipairs(result.errors or {}) do
    -- Skip non-table entries (malformed errors)
    if type(err) ~= "table" then
      goto continue
    end

    -- Convert 1-indexed parser lines to 0-indexed diagnostic lines
    local start_line = (err.range and err.range.start_line or 1) - 1
    local start_col = (err.range and err.range.start_col or 1) - 1
    local end_line = (err.range and err.range.end_line or err.range and err.range.start_line or 1) - 1
    local end_col = (err.range and err.range.end_col or err.range and err.range.start_col or 1) - 1

    -- Clamp to valid values
    start_line = math.max(0, start_line)
    start_col = math.max(0, start_col)
    end_line = math.max(0, end_line)
    end_col = math.max(0, end_col)

    table.insert(diagnostics, {
      lnum = start_line,
      col = start_col,
      end_lnum = end_line,
      end_col = end_col,
      message = err.message or "Syntax error",
      severity = vim.diagnostic.severity.ERROR,
      source = "tcl-lsp",
    })
    ::continue::
  end

  vim.diagnostic.set(ns, bufnr, diagnostics)
end

-- Clear diagnostics for a buffer
function M.clear(bufnr)
  if ns then
    -- Wrap in pcall to handle invalid buffers gracefully
    pcall(vim.diagnostic.reset, ns, bufnr)
  end
end

-- Get the namespace (for testing)
function M.get_namespace()
  return ns
end

return M
