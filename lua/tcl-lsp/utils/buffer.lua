-- lua/tcl-lsp/utils/buffer.lua
-- Buffer validation helper

local M = {}

--- Check if a buffer number is valid.
---@param bufnr number|nil Buffer number
---@return boolean True if bufnr is non-nil and points to a valid buffer
function M.is_valid(bufnr)
  if not bufnr then
    return false
  end
  return vim.api.nvim_buf_is_valid(bufnr)
end

return M
