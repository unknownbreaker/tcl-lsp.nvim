-- lua/tcl-lsp/utils/notify.lua
-- Safe vim.notify wrapper (always deferred via vim.schedule)

local M = {}

--- Send a notification safely from any context.
--- Wraps vim.notify in vim.schedule to avoid E5560 in fast-event contexts.
---@param msg string The message to display
---@param level number|nil vim.log.levels value (default: INFO)
function M.notify(msg, level)
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO)
  end)
end

return M
