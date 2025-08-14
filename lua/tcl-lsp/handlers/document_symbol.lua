local M = {}
local utils = require("tcl-lsp.utils")

function M.handle(params)
	local uri = params.textDocument.uri
	local filepath = utils.uri_to_path(uri)

	local parser = require("tcl-lsp.parser")
	local symbols = parser.parse_file(filepath)

	local document_symbols = {}

	-- Convert symbols to LSP DocumentSymbol format
	local symbol_kinds = {
		procedure = 12, -- Function
		variable = 13, -- Variable
		namespace = 3, -- Namespace
		package = 4, -- Package
	}

	for symbol_type, symbol_list in pairs(symbols) do
		if type(symbol_list) == "table" and symbol_type ~= "errors" then
			for _, symbol in ipairs(symbol_list) do
				table.insert(document_symbols, {
					name = symbol.name,
					kind = symbol_kinds[symbol.type] or 1,
					range = symbol.range or utils.get_lsp_range(symbol.line - 1, symbol.col - 1),
					selectionRange = symbol.range or utils.get_lsp_range(symbol.line - 1, symbol.col - 1),
				})
			end
		end
	end

	return document_symbols
end

return M
