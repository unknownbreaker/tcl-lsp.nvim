local M = {}
local utils = require("tcl-lsp.utils")

function M.handle(params)
	local uri = params.textDocument.uri
	local position = params.position

	local filepath = utils.uri_to_path(uri)
	local bufnr = vim.uri_to_bufnr(uri)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local line = lines[position.line + 1] or ""

	local word = utils.get_word_at_position(line, position.character)
	if not word then
		return nil
	end

	-- Find definition in workspace
	local workspace = require("tcl-lsp.workspace")
	local definition = workspace.find_definition(word, filepath)

	if definition then
		return {
			uri = utils.path_to_uri(definition.file),
			range = definition.range or utils.get_lsp_range(definition.line - 1, definition.col - 1),
		}
	end

	return nil
end

return M
