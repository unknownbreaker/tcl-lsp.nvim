local M = {}
local utils = require("tcl-lsp.utils")

function M.handle(params)
	local uri = params.textDocument.uri
	local position = params.position
	local context = params.context or {}

	local filepath = utils.uri_to_path(uri)
	local bufnr = vim.uri_to_bufnr(uri)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local line = lines[position.line + 1] or ""

	local word = utils.get_word_at_position(line, position.character)
	if not word then
		return {}
	end

	-- Find all references
	local workspace = require("tcl-lsp.workspace")
	local references = workspace.find_references(word, context.includeDeclaration)

	-- Convert to LSP format
	local lsp_references = {}
	for _, ref in ipairs(references) do
		table.insert(lsp_references, {
			uri = ref.uri,
			range = ref.range,
		})
	end

	return lsp_references
end

return M
