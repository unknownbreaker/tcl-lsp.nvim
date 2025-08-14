local M = {}
local utils = require("tcl-lsp.utils")
local parser = require("tcl-lsp.parser")

-- Get all symbols from workspace
function M.get_all_symbols(root_dir)
	root_dir = root_dir or vim.fn.getcwd()
	local cache_key = "workspace_symbols_" .. root_dir

	-- Check cache first
	if utils.cache_is_valid(cache_key) then
		local cached = utils.cache_get(cache_key)
		return cached.value
	end

	local all_symbols = {}
	local files = utils.find_tcl_files(root_dir)

	for _, file in ipairs(files) do
		local symbols = parser.parse_file(file)

		-- Flatten all symbol types into one array
		for _, symbol_list in pairs(symbols) do
			if type(symbol_list) == "table" then
				for _, symbol in ipairs(symbol_list) do
					table.insert(all_symbols, symbol)
				end
			end
		end
	end

	-- Cache the result
	utils.cache_set(cache_key, all_symbols, 10000) -- 10 second cache

	return all_symbols
end

-- Find symbol definition
function M.find_definition(symbol_name, current_file, current_line)
	local all_symbols = M.get_all_symbols()

	-- Find what procedure we're currently in (if any)
	local current_proc = nil
	if current_line then
		for _, symbol in ipairs(all_symbols) do
			if symbol.type == "procedure" and symbol.file == current_file and symbol.line <= current_line then
				-- This is a simple heuristic - assumes we're in the last procedure before current line
				if not current_proc or symbol.line > current_proc.line then
					current_proc = symbol
				end
			end
		end
	end

	-- Collect all matches
	local matches = {}

	for _, symbol in ipairs(all_symbols) do
		if symbol.name == symbol_name then
			local priority = 10 -- Default priority

			-- Prioritize based on scope and type
			if symbol.type == "procedure" then
				priority = 1 -- Procedures have high priority
			elseif symbol.type == "variable" then
				if current_proc and symbol.scope == current_proc.name then
					priority = 2 -- Local variables in current procedure
				elseif symbol.scope == "global" then
					priority = 3 -- Global variables
				else
					priority = 4 -- Variables in other scopes
				end
			else
				priority = 5 -- Other symbol types
			end

			table.insert(matches, {
				symbol = symbol,
				priority = priority,
				distance = current_line and math.abs(symbol.line - current_line) or 1000,
			})
		end
	end

	if #matches == 0 then
		return nil
	end

	-- Sort by priority first, then by distance
	table.sort(matches, function(a, b)
		if a.priority == b.priority then
			return a.distance < b.distance
		end
		return a.priority < b.priority
	end)

	return matches[1].symbol
end

-- Find all references to a symbol
function M.find_references(symbol_name, include_declaration)
	include_declaration = include_declaration ~= false
	local references = {}
	local files = utils.find_tcl_files()

	for _, filepath in ipairs(files) do
		local file_refs = M.find_references_in_file(filepath, symbol_name, include_declaration)
		for _, ref in ipairs(file_refs) do
			table.insert(references, ref)
		end
	end

	return references
end

-- Find references in a specific file
function M.find_references_in_file(filepath, symbol_name, include_declaration)
	local references = {}
	local file = io.open(filepath, "r")
	if not file then
		return references
	end

	local content = file:read("*all")
	file:close()

	local line_num = 0
	for line in content:gmatch("[^\r\n]+") do
		line_num = line_num + 1

		-- Find all occurrences of the symbol in this line
		local start_pos = 1
		while true do
			local pos = line:find(symbol_name, start_pos, true)
			if not pos then
				break
			end

			-- Check if it's a whole word (not part of another identifier)
			local before_char = pos > 1 and line:sub(pos - 1, pos - 1) or " "
			local after_char = line:sub(pos + #symbol_name, pos + #symbol_name)

			if not before_char:match("[%w_:]") and not (after_char and after_char:match("[%w_:]")) then
				table.insert(references, {
					uri = utils.path_to_uri(filepath),
					range = utils.get_lsp_range(line_num - 1, pos - 1, line_num - 1, pos + #symbol_name - 1),
					context = line:match("^%s*(.-)%s*$"), -- trimmed line
				})
			end

			start_pos = pos + 1
		end
	end

	return references
end

return M
