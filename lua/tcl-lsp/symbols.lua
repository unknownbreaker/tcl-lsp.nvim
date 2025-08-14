-- Symbol navigation and analysis for tcl-lsp.nvim

local M = {}

-- Cache for parsed symbols across buffers
local symbol_cache = {}

-- Parse TCL file to extract symbols (procedures, variables, namespaces)
local function parse_tcl_symbols(content, uri)
	local symbols = {
		procedures = {},
		variables = {},
		namespaces = {},
		sources = {},
		packages = {},
		rivet_tags = {}, -- Rivet-specific constructs
	}

	local lines = vim.split(content, "\n")
	local is_rvt_file = uri and uri:match("%.rvt$")

	for line_num, line in ipairs(lines) do
		local trimmed = vim.trim(line)

		-- Skip comments and empty lines
		if trimmed == "" or trimmed:match("^%s*#") then
			goto continue
		end

		-- Parse procedure definitions: proc name args body
		local proc_match = trimmed:match("^%s*proc%s+([%w_:]+)")
		if proc_match then
			table.insert(symbols.procedures, {
				name = proc_match,
				line = line_num - 1, -- 0-based for LSP
				character = line:find(proc_match) - 1,
				uri = uri,
				kind = vim.lsp.protocol.SymbolKind.Function,
				detail = "procedure",
			})
		end

		-- Parse variable assignments: set varname value
		local var_match = trimmed:match("^%s*set%s+([%w_:]+)")
		if var_match then
			-- Avoid duplicates - only add if not already seen
			local already_exists = false
			for _, var in ipairs(symbols.variables) do
				if var.name == var_match then
					already_exists = true
					break
				end
			end

			if not already_exists then
				table.insert(symbols.variables, {
					name = var_match,
					line = line_num - 1,
					character = line:find(var_match) - 1,
					uri = uri,
					kind = vim.lsp.protocol.SymbolKind.Variable,
					detail = "variable",
				})
			end
		end

		-- Parse namespace definitions: namespace eval name { ... }
		local ns_match = trimmed:match("^%s*namespace%s+eval%s+([%w_:]+)")
		if ns_match then
			table.insert(symbols.namespaces, {
				name = ns_match,
				line = line_num - 1,
				character = line:find(ns_match) - 1,
				uri = uri,
				kind = vim.lsp.protocol.SymbolKind.Namespace,
				detail = "namespace",
			})
		end

		-- Parse source commands: source filename
		local source_match = trimmed:match("^%s*source%s+([%S]+)")
		if source_match then
			table.insert(symbols.sources, {
				name = source_match,
				line = line_num - 1,
				character = line:find(source_match) - 1,
				uri = uri,
				kind = vim.lsp.protocol.SymbolKind.File,
				detail = "source file",
			})
		end

		-- Parse package require: package require packagename
		local pkg_match = trimmed:match("^%s*package%s+require%s+([%w_:]+)")
		if pkg_match then
			table.insert(symbols.packages, {
				name = pkg_match,
				line = line_num - 1,
				character = line:find(pkg_match) - 1,
				uri = uri,
				kind = vim.lsp.protocol.SymbolKind.Package,
				detail = "package",
			})
		end

		-- Rivet-specific parsing for .rvt files
		if is_rvt_file then
			-- Parse Rivet tags: <? tcl_code ?>
			local rivet_code = line:match("<%?(.-)%?>")
			if rivet_code then
				-- Look for procedures and variables within Rivet tags
				local rivet_proc = rivet_code:match("proc%s+([%w_:]+)")
				if rivet_proc then
					table.insert(symbols.procedures, {
						name = rivet_proc,
						line = line_num - 1,
						character = line:find(rivet_proc) - 1,
						uri = uri,
						kind = vim.lsp.protocol.SymbolKind.Function,
						detail = "rivet procedure",
					})
				end

				local rivet_var = rivet_code:match("set%s+([%w_:]+)")
				if rivet_var then
					-- Check for duplicates
					local already_exists = false
					for _, var in ipairs(symbols.variables) do
						if var.name == rivet_var then
							already_exists = true
							break
						end
					end

					if not already_exists then
						table.insert(symbols.variables, {
							name = rivet_var,
							line = line_num - 1,
							character = line:find(rivet_var) - 1,
							uri = uri,
							kind = vim.lsp.protocol.SymbolKind.Variable,
							detail = "rivet variable",
						})
					end
				end
			end

			-- Parse Rivet include/template directives
			local rivet_include = trimmed:match('<%@%s*include%s+file="([^"]+)"')
			if rivet_include then
				table.insert(symbols.rivet_tags, {
					name = rivet_include,
					line = line_num - 1,
					character = line:find(rivet_include) - 1,
					uri = uri,
					kind = vim.lsp.protocol.SymbolKind.File,
					detail = "rivet include",
				})
			end

			-- Parse Rivet parse directives
			local rivet_parse = trimmed:match('<%@%s*parse%s+file="([^"]+)"')
			if rivet_parse then
				table.insert(symbols.rivet_tags, {
					name = rivet_parse,
					line = line_num - 1,
					character = line:find(rivet_parse) - 1,
					uri = uri,
					kind = vim.lsp.protocol.SymbolKind.File,
					detail = "rivet parse",
				})
			end
		end

		::continue::
	end

	return symbols
end

-- Update symbol cache for a buffer
function M.update_symbols(bufnr, uri)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
	local symbols = parse_tcl_symbols(content, uri)

	symbol_cache[uri] = symbols
	return symbols
end

-- Get symbols for a specific buffer
function M.get_buffer_symbols(uri)
	return symbol_cache[uri] or {}
end

-- Get all symbols across all loaded buffers
function M.get_all_symbols()
	local all_symbols = {}

	for uri, symbols in pairs(symbol_cache) do
		-- Combine all symbol types
		for _, symbol_list in pairs(symbols) do
			for _, symbol in ipairs(symbol_list) do
				table.insert(all_symbols, symbol)
			end
		end
	end

	return all_symbols
end

-- Find definition of symbol at position
function M.find_definition(uri, position)
	local symbols = symbol_cache[uri]
	if not symbols then
		return nil
	end

	-- Get the word at position
	local bufnr = vim.uri_to_bufnr(uri)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return nil
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local word = M.get_word_at_position(lines, position)

	if not word then
		return nil
	end

	-- Search for definition in current file first
	for _, symbol_list in pairs(symbols) do
		for _, symbol in ipairs(symbol_list) do
			if symbol.name == word then
				return {
					uri = symbol.uri,
					range = {
						start = { line = symbol.line, character = symbol.character },
						["end"] = { line = symbol.line, character = symbol.character + #symbol.name },
					},
				}
			end
		end
	end

	-- Search in other files
	for other_uri, other_symbols in pairs(symbol_cache) do
		if other_uri ~= uri then
			for _, symbol_list in pairs(other_symbols) do
				for _, symbol in ipairs(symbol_list) do
					if symbol.name == word then
						return {
							uri = symbol.uri,
							range = {
								start = { line = symbol.line, character = symbol.character },
								["end"] = { line = symbol.line, character = symbol.character + #symbol.name },
							},
						}
					end
				end
			end
		end
	end

	return nil
end

-- Find all references to a symbol
function M.find_references(uri, position, include_declaration)
	local references = {}

	-- Get the word at position
	local bufnr = vim.uri_to_bufnr(uri)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return references
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local word = M.get_word_at_position(lines, position)

	if not word then
		return references
	end

	-- Search through all cached files
	for file_uri, symbols in pairs(symbol_cache) do
		local file_bufnr = vim.uri_to_bufnr(file_uri)
		if vim.api.nvim_buf_is_valid(file_bufnr) then
			local file_lines = vim.api.nvim_buf_get_lines(file_bufnr, 0, -1, false)

			-- Find all occurrences in this file
			for line_num, line in ipairs(file_lines) do
				local start_pos = 1
				while true do
					local found_pos = line:find("%f[%w_]" .. vim.pesc(word) .. "%f[^%w_]", start_pos)
					if not found_pos then
						break
					end

					-- Skip if this is in a comment
					local before_match = line:sub(1, found_pos - 1)
					if not before_match:match("#") then
						table.insert(references, {
							uri = file_uri,
							range = {
								start = { line = line_num - 1, character = found_pos - 1 },
								["end"] = { line = line_num - 1, character = found_pos - 1 + #word },
							},
						})
					end

					start_pos = found_pos + #word
				end
			end
		end
	end

	return references
end

-- Get document symbols for outline
function M.get_document_symbols(uri)
	local symbols = symbol_cache[uri]
	if not symbols then
		return {}
	end

	local document_symbols = {}

	-- Convert internal symbols to LSP format
	for category, symbol_list in pairs(symbols) do
		for _, symbol in ipairs(symbol_list) do
			table.insert(document_symbols, {
				name = symbol.name,
				kind = symbol.kind,
				detail = symbol.detail,
				range = {
					start = { line = symbol.line, character = symbol.character },
					["end"] = { line = symbol.line, character = symbol.character + #symbol.name },
				},
				selectionRange = {
					start = { line = symbol.line, character = symbol.character },
					["end"] = { line = symbol.line, character = symbol.character + #symbol.name },
				},
			})
		end
	end

	-- Sort by line number
	table.sort(document_symbols, function(a, b)
		return a.range.start.line < b.range.start.line
	end)

	return document_symbols
end

-- Get workspace symbols
function M.get_workspace_symbols(query)
	local workspace_symbols = {}
	local all_symbols = M.get_all_symbols()

	-- Filter symbols by query if provided
	for _, symbol in ipairs(all_symbols) do
		if not query or query == "" or symbol.name:lower():find(query:lower(), 1, true) then
			table.insert(workspace_symbols, {
				name = symbol.name,
				kind = symbol.kind,
				location = {
					uri = symbol.uri,
					range = {
						start = { line = symbol.line, character = symbol.character },
						["end"] = { line = symbol.line, character = symbol.character + #symbol.name },
					},
				},
				containerName = symbol.detail,
			})
		end
	end

	return workspace_symbols
end

-- Utility function to get word at position
function M.get_word_at_position(lines, position)
	local line = lines[position.line + 1]
	if not line then
		return nil
	end

	local char = position.character + 1
	local start_pos = char
	local end_pos = char

	-- Find word boundaries (include : for namespaced symbols)
	while start_pos > 1 and line:sub(start_pos - 1, start_pos - 1):match("[%w_:]") do
		start_pos = start_pos - 1
	end

	while end_pos <= #line and line:sub(end_pos, end_pos):match("[%w_:]") do
		end_pos = end_pos + 1
	end

	if start_pos < end_pos then
		return line:sub(start_pos, end_pos - 1)
	end

	return nil
end

-- Clear symbol cache for a URI
function M.clear_symbols(uri)
	symbol_cache[uri] = nil
end

-- Get symbol cache for debugging
function M.get_cache()
	return symbol_cache
end

return M
