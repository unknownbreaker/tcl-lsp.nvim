-- lua/tcl-lsp/features/definition.lua
-- Go-to-definition feature for TCL LSP

local M = {}

local definitions = require("tcl-lsp.analyzer.definitions")

--- Handle go-to-definition request
---@param bufnr number Buffer number
---@param line number Line number (0-indexed)
---@param col number Column number (0-indexed)
---@return table|nil LSP location format: { uri, range }, or nil if not found
function M.handle_definition(bufnr, line, col)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  return definitions.find_definition(bufnr, line + 1, col + 1)
end

--- Set up go-to-definition feature
--- Creates user command and registers keymaps for TCL/RVT files
function M.setup()
  -- Create user command for go-to-definition
  vim.api.nvim_create_user_command("TclGoToDefinition", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = pos[1] - 1 -- Convert to 0-indexed
    local col = pos[2]

    local result = M.handle_definition(bufnr, line, col)

    if result then
      -- Jump to location
      local uri = result.uri
      local filepath = uri:gsub("^file://", "")
      local target_line = result.range.start.line + 1
      local target_col = result.range.start.character

      -- Open file if different
      if filepath ~= vim.api.nvim_buf_get_name(bufnr) then
        vim.cmd("edit " .. vim.fn.fnameescape(filepath))
      end

      -- Jump to position
      vim.api.nvim_win_set_cursor(0, { target_line, target_col })
    else
      vim.notify("No definition found", vim.log.levels.INFO)
    end
  end, { desc = "Go to TCL definition" })

  -- Set up keymap for TCL files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tcl", "rvt" },
    callback = function(args)
      vim.keymap.set("n", "gd", "<cmd>TclGoToDefinition<cr>", {
        buffer = args.buf,
        desc = "Go to definition",
      })
    end,
  })
end

return M
