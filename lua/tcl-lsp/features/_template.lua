-- lua/tcl-lsp/features/_template.lua
-- Reference template for new feature modules. NOT loaded at runtime.
--
-- Coordinate convention:
--   handle_* receives 0-indexed line/col from cursor position
--   Analyzers expect 1-indexed, so add +1 before calling them
--
-- Standard setup pattern:
--   M.setup() creates a user command + FileType autocmd with buffer-local keymap
--   M.handle_<action>(bufnr, line, col) delegates to analyzer modules

local M = {}

local buffer = require("tcl-lsp.utils.buffer")
local notify = require("tcl-lsp.utils.notify")

--- Handle <action> request
---@param bufnr number Buffer number
---@param line number Line number (0-indexed from cursor)
---@param col number Column number (0-indexed from cursor)
---@return table|nil Result, or nil if not found
function M.handle_action(bufnr, line, col)
  if not buffer.is_valid(bufnr) then
    return nil
  end

  -- Analyzers expect 1-indexed positions
  local result = nil -- analyzer.do_something(bufnr, line + 1, col + 1)
  return result
end

--- Set up <feature> feature
--- Creates user command and registers keymaps for TCL/RVT files
function M.setup()
  vim.api.nvim_create_user_command("TclFeatureName", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = pos[1] - 1 -- Convert to 0-indexed
    local col = pos[2]

    local result = M.handle_action(bufnr, line, col)

    if result then
      -- Use result
    else
      notify.notify("No result found")
    end
  end, { desc = "Description of feature" })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tcl", "rvt" },
    callback = function(args)
      vim.keymap.set("n", "<key>", "<cmd>TclFeatureName<cr>", {
        buffer = args.buf,
        desc = "Description of keymap",
      })
    end,
  })
end

return M
