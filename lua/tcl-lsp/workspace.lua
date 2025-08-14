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

-- Find symbol definition with scope awareness
function M.find_definition_with_scope(symbol_name, current_file, current_line)
	local all_symbols = M.get_all_symbols()

	-- First, try to find the current procedure scope
	local current_proc = nil
	for _, symbol in ipairs(all_symbols) do
		if symbol.type == "procedure" and symbol.file == current_file then
			-- Check if current line is within this procedure
			-- This is a simplified check - ideally we'd parse the procedure's end
			if current_line >= symbol.line then
				if not current_proc or symbol.line > current_proc.line then
					current_proc = symbol
				end
			end
		end
	end

	local matches = {}

	-- Search priority order:
	-- 1. Parameters of current procedure
	-- 2. Local variables in current procedure
	-- 3. Global variables
	-- 4. Procedures
	-- 5. Other symbols

	for _, symbol in ipairs(all_symbols) do
		if symbol.name == symbol_name then
			local priority = 0

			if symbol.type == "parameter" and current_proc and symbol.scope == current_proc.name then
				priority = 1 -- Highest priority: procedure parameters
			elseif symbol.type == "variable" and current_proc and symbol.scope == current_proc.name then
				priority = 2 -- Local variables in current procedure
			elseif symbol.type == "variable" and symbol.scope == "global" then
				priority = 3 -- Global variables
			elseif symbol.type == "procedure" then
				priority = 4 -- Procedures
			else
				priority = 5 -- Everything else
			end

			table.insert(matches, {
				symbol = symbol,
				priority = priority,
				scope_match = (current_proc and symbol.scope == current_proc.name),
			})
		end
	end

	-- Sort by priority (lower number = higher priority)
	table.sort(matches, function(a, b)
		if a.priority == b.priority then
			-- If same priority, prefer closer line numbers
			return math.abs(a.symbol.line - current_line) < math.abs(b.symbol.line - current_line)
		end
		return a.priority < b.priority
	end)

	return matches[1] and matches[1].symbol or nil
end

-- Enhanced find_definition that uses scope awareness
function M.find_definition(symbol_name, current_file, current_line)
	-- If current_line is provided, use scope-aware search
	if current_line then
		return M.find_definition_with_scope(symbol_name, current_file, current_line)
	end

	-- Fallback to original method
	local all_symbols = M.get_all_symbols()

	local matches = {}

	for _, symbol in ipairs(all_symbols) do
		if symbol.name == symbol_name then
			table.insert(matches, symbol)
		end
	end

	-- Sort by priority: procedures first, then variables, then others
	table.sort(matches, function(a, b)
		local priority = { procedure = 1, parameter = 2, variable = 3, namespace = 4, package = 5 }
		return (priority[a.type] or 6) < (priority[b.type] or 6)
	end)

	return matches[1]
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
