-- lua/tcl-lsp/init.lua
-- Main plugin entry point

local config = require "tcl-lsp.config"
local server = require "tcl-lsp.server"

local M = {}

-- Plugin setup
function M.setup(user_config)
  -- Setup configuration
  config.setup(user_config)

  -- Setup autocommands for TCL files
  local tcl_group = vim.api.nvim_create_augroup("TclLsp", { clear = true })

  -- Auto-start LSP for TCL files
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = tcl_group,
    pattern = { "*.tcl", "*.rvt" },
    callback = function(args)
      if config.get "auto_start" then
        vim.defer_fn(function()
          server.start(args.file)
        end, 100) -- Small delay to ensure buffer is fully loaded
      end
    end,
  })

  -- Create user commands
  vim.api.nvim_create_user_command("TclLspStart", function()
    server.start()
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
end

-- Manual server start (for testing)
function M.start(filepath)
  return server.start(filepath)
end

-- Manual server stop (for testing)
function M.stop()
  return server.stop()
end

-- Get server status (for testing)
function M.status()
  return server.get_status()
end

-- Get current configuration (for testing)
function M.config()
  return config.get()
end

return M
