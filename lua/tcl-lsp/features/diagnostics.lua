-- lua/tcl-lsp/features/diagnostics.lua
-- Diagnostics feature - surfaces parser syntax errors

local M = {}

-- Diagnostic namespace (created in setup)
local ns = nil

-- Track if setup was called (to warn on fallback)
local setup_called = false

-- Setup diagnostics feature
function M.setup()
  ns = vim.api.nvim_create_namespace("tcl-lsp")
  setup_called = true

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

  -- Ensure namespace exists (with warning if setup wasn't called)
  if not ns then
    ns = vim.api.nvim_create_namespace("tcl-lsp")
    if not setup_called then
      vim.schedule(function()
        vim.notify(
          "tcl-lsp: diagnostics.setup() was not called. Some features may not work correctly.",
          vim.log.levels.WARN
        )
      end)
    end
  end

  -- Get filepath (protected)
  local filepath_ok, filepath = pcall(vim.api.nvim_buf_get_name, bufnr)
  if not filepath_ok then
    filepath = ""
  end

  -- Parse buffer (cached by changedtick)
  local cache = require("tcl-lsp.utils.cache")
  local parse_ok, result = pcall(cache.parse_with_errors, bufnr, filepath)
  if not parse_ok then
    local err_msg = tostring(result)
    vim.schedule(function()
      if err_msg:match("timeout") then
        vim.notify(
          string.format("tcl-lsp: Parser timed out for %s. File may be too large or complex.", filepath),
          vim.log.levels.WARN
        )
      else
        vim.notify(
          string.format("tcl-lsp: Parser failed for %s: %s", filepath, err_msg),
          vim.log.levels.WARN
        )
      end
    end)
    return
  end

  if not result or type(result) ~= "table" then
    vim.schedule(function()
      vim.notify(
        string.format("tcl-lsp: Parser returned invalid result for %s", filepath),
        vim.log.levels.WARN
      )
    end)
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

    -- Handle nil or empty message
    local message = err.message
    if not message or message == "" then
      message = "Syntax error"
    end

    table.insert(diagnostics, {
      lnum = start_line,
      col = start_col,
      end_lnum = end_line,
      end_col = end_col,
      message = message,
      severity = vim.diagnostic.severity.ERROR,
      source = "tcl-lsp",
    })
    ::continue::
  end

  -- Set diagnostics (wrapped in pcall for safety)
  local set_ok, set_err = pcall(vim.diagnostic.set, ns, bufnr, diagnostics)
  if not set_ok then
    vim.schedule(function()
      vim.notify(
        string.format("tcl-lsp: Failed to set diagnostics: %s", tostring(set_err)),
        vim.log.levels.ERROR
      )
    end)
  end
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
