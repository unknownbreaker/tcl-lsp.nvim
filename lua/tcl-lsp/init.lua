-- lua/tcl-lsp/init.lua
-- Main plugin entry point

local config = require "tcl-lsp.config"
local server = require "tcl-lsp.server"
local definition = require "tcl-lsp.features.definition"
local references = require "tcl-lsp.features.references"
local hover = require "tcl-lsp.features.hover"
local diagnostics = require "tcl-lsp.features.diagnostics"

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

    -- Re-index file on save
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = tcl_group,
      pattern = { "*.tcl", "*.rvt" },
      callback = function(args)
        local indexer = require("tcl-lsp.analyzer.indexer")
        if indexer.get_status().status == "ready" then
          indexer.index_file(args.file)
        end
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

return M
