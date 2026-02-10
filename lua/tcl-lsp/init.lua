-- lua/tcl-lsp/init.lua
-- Main plugin entry point

local config = require "tcl-lsp.config"
local server = require "tcl-lsp.server"
local definition = require "tcl-lsp.features.definition"
local references = require "tcl-lsp.features.references"
local hover = require "tcl-lsp.features.hover"
local diagnostics = require "tcl-lsp.features.diagnostics"
local rename = require "tcl-lsp.features.rename"
local highlights = require "tcl-lsp.features.highlights"
local folding = require "tcl-lsp.features.folding"
local formatting = require "tcl-lsp.features.formatting"
local completion = require "tcl-lsp.features.completion"

local M = {}

-- Plugin state
local plugin_state = {
  initialized = false,
  autocommands_created = false,
}

-- Plugin setup
function M.setup(user_config)
  -- Setup configuration
  config.setup(user_config)

  -- Mark as initialized
  plugin_state.initialized = true

  -- Setup autocommands for TCL files (only once)
  if not plugin_state.autocommands_created then
    local tcl_group = vim.api.nvim_create_augroup("TclLsp", { clear = true })

    -- Auto-start LSP for TCL files
    vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
      group = tcl_group,
      pattern = { "*.tcl", "*.rvt" },
      callback = function(args)
        -- FIXED: Renamed from user_config to current_config to avoid shadowing
        local current_config = config.get()
        if current_config.auto_start ~= false then -- Default to true
          vim.defer_fn(function()
            server.start(args.file)
          end, 100) -- Small delay to ensure buffer is fully loaded
        end
      end,
    })

    -- Re-index file on save (only if indexer is enabled)
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = tcl_group,
      pattern = { "*.tcl", "*.rvt" },
      callback = function(args)
        local current_config = config.get()
        local indexer_config = current_config.indexer or {}
        if indexer_config.enabled then
          local indexer = require("tcl-lsp.analyzer.indexer")
          if indexer.get_status().status == "ready" then
            indexer.index_file(args.file)
          end
        end
      end,
    })

    -- Clean up on exit (prevents hang on quit)
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = tcl_group,
      callback = function()
        -- Clear AST cache first
        local cache = require("tcl-lsp.utils.cache")
        cache.clear()
        -- Stop indexer before parser to prevent new parser jobs
        local indexer = require("tcl-lsp.analyzer.indexer")
        if indexer.cleanup then
          indexer.cleanup()
        end
        -- Then stop any running parser jobs
        local parser = require("tcl-lsp.parser")
        if parser.cleanup then
          parser.cleanup()
        end
      end,
    })

    -- Invalidate cache when buffer is deleted
    vim.api.nvim_create_autocmd("BufDelete", {
      group = tcl_group,
      pattern = { "*.tcl", "*.rvt" },
      callback = function(args)
        local cache = require("tcl-lsp.utils.cache")
        cache.invalidate(args.buf)
      end,
    })

    plugin_state.autocommands_created = true
  end

  -- Create user commands
  vim.api.nvim_create_user_command("TclLspStart", function()
    local current_file = vim.api.nvim_buf_get_name(0)
    server.start(current_file)
  end, { desc = "Start TCL LSP server" })

  vim.api.nvim_create_user_command("TclLspStop", function()
    server.stop()
  end, { desc = "Stop TCL LSP server" })

  vim.api.nvim_create_user_command("TclLspRestart", function()
    server.restart()
  end, { desc = "Restart TCL LSP server" })

  vim.api.nvim_create_user_command("TclLspStatus", function()
    local status = server.get_status()
    vim.notify("TCL LSP Status: " .. vim.inspect(status), vim.log.levels.INFO)
  end, { desc = "Show TCL LSP server status" })

  vim.api.nvim_create_user_command("TclIndexStatus", function()
    local indexer = require("tcl-lsp.analyzer.indexer")
    local status = indexer.get_status()
    vim.notify(string.format(
      "Index status: %s (%d/%d files)",
      status.status,
      status.indexed,
      status.total
    ), vim.log.levels.INFO)
  end, { desc = "Show TCL index status" })

  -- Set up go-to-definition feature
  definition.setup()

  -- Set up find-references feature
  references.setup()

  -- Set up hover feature
  hover.setup()

  -- Set up diagnostics feature
  diagnostics.setup()

  -- Set up rename feature
  rename.setup()

  -- Set up semantic highlighting feature
  highlights.setup()

  -- Set up folding feature
  folding.setup()

  -- Set up formatting feature
  formatting.setup()

  -- Set up completion feature
  completion.setup()
end

-- Manual server start (for testing and API)
function M.start(filepath)
  return server.start(filepath)
end

-- Manual server stop (for testing and API)
function M.stop()
  return server.stop()
end

-- Get server status (for testing and API)
function M.status()
  return server.get_status()
end

-- Get current configuration (for testing and API)
function M.config()
  return config.get()
end

-- Check if plugin is initialized (for testing)
function M.is_initialized()
  return plugin_state.initialized
end

-- Get autocommand group for testing
function M.get_augroup_id()
  return plugin_state.augroup_id
end

-- Plugin version information (satisfies test requirement)
M.version = "0.1.0-dev"

-- Get folding ranges for current buffer (for testing and API)
function M.get_folding_ranges(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return folding.get_folding_ranges(bufnr)
end

-- Format current buffer (for testing and API)
function M.format(bufnr)
  return formatting.format_buffer(bufnr)
end

return M
