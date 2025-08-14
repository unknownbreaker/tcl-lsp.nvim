local M = {}
local utils = require("tcl-lsp.utils")

function M.handle(params)
	local uri = params.textDocument.uri
	local position = params.position

	local filepath = utils.uri_to_path(uri)
	local bufnr = vim.uri_to_bufnr(uri)

	-- Safely get buffer lines
	local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
	if not ok or not lines then
		return nil
	end

	local line = lines[position.line + 1] or ""
	local word = utils.get_word_at_position(line, position.character)

	if not word then
		return nil
	end

	-- Find definition in workspace
	local workspace_ok, workspace = pcall(require, "tcl-lsp.workspace")
	if not workspace_ok then
		return nil
	end

	local definition_ok, definition = pcall(workspace.find_definition, word, filepath)
	if not definition_ok or not definition then
		return nil
	end

	-- For procedures, find the exact line to avoid jumping to comments
	local target_line = definition.line
	if definition.type == "procedure" then
		local parser = require("tcl-lsp.parser")
		target_line = parser.find_exact_definition_line(definition.file, definition.name, definition.line)
	end

	return {
		uri = utils.path_to_uri(definition.file),
		range = {
			start = { line = target_line - 1, character = 0 }, -- Jump to beginning of line
			["end"] = { line = target_line - 1, character = 0 },
		},
	}
end

return M
