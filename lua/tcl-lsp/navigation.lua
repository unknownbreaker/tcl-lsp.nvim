local utils = require("tcl-lsp.utils")
local config = require("tcl-lsp.config")
local tcl = require("tcl-lsp.tcl")
local semantic = require("tcl-lsp.semantic") -- ADD this line at the top
local M = {}

-- REPLACE the existing goto_definition function with this enhanced version:
function M.goto_definition()
	-- Try to get qualified word first, fall back to regular word
	local word, err = utils.get_qualified_word_under_cursor()
	if not word then
		word, err = utils.get_word_under_cursor()
		if not word then
			utils.notify(err, vim.log.levels.WARN)
			return
		end
	end

	local file_path, file_err = utils.get_current_file_path()
	if not file_path then
		utils.notify(file_err, vim.log.levels.WARN)
		return
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

	-- TRY SEMANTIC RESOLUTION FIRST
	local semantic_symbols = semantic.resolve_symbol_semantically(word, file_path, cursor_line, tclsh_cmd)

	if semantic_symbols and #semantic_symbols > 0 then
		print("DEBUG: Using semantic goto_definition - found", #semantic_symbols, "candidates")

		-- Find exact matches first
		local exact_matches = {}
		local partial_matches = {}

		for _, symbol in ipairs(semantic_symbols) do
			if symbol.name == word then
				table.insert(exact_matches, symbol)
			else
				table.insert(partial_matches, symbol)
			end
		end

		local matches = #exact_matches > 0 and exact_matches or partial_matches

		if #matches == 1 then
			local match = matches[1]
			vim.api.nvim_win_set_cursor(0, { match.line, 0 })
			utils.notify(
				string.format("Found %s '%s' at line %d (semantic)", match.type, match.name, match.line),
				vim.log.levels.INFO
			)
			return
		elseif #matches > 1 then
			M.show_semantic_symbol_choices(matches, word)
			return
		end
	end

	print("DEBUG: Falling back to existing goto_definition logic")

	-- FALLBACK TO EXISTING LOGIC (unchanged)
	-- Get all symbols from current file first
	local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
	if not symbols then
		utils.notify("Failed to analyze file with TCL", vim.log.levels.ERROR)
		return
	end

	-- Quick check: if no symbols found, there might be a parsing issue
	if #symbols == 0 then
		utils.notify("No symbols found in file. Try :TclLspDebug to troubleshoot.", vim.log.levels.WARN)
		return
	end

	-- Try smart resolution first
	local resolution = tcl.resolve_symbol(word, file_path, cursor_line, tclsh_cmd)
	local matches = {}

	if resolution and resolution.resolutions then
		-- Use smart resolution
		matches = M.find_matching_symbols(symbols, resolution.resolutions, word)
	end

	-- Fallback to simple matching if smart resolution fails or finds nothing
	if #matches == 0 then
		for _, symbol in ipairs(symbols) do
			if symbol.name == word or utils.symbols_match(symbol.name, word) then
				table.insert(matches, {
					symbol = symbol,
					priority = (symbol.name == word) and 10 or 5, -- Prefer exact matches
					resolution = { type = "fallback", name = word },
				})
			end
		end
	end

	if #matches == 0 then
		-- Try workspace search if nothing found locally
		utils.notify("Symbol '" .. word .. "' not found in current file, searching workspace...", vim.log.levels.INFO)
		M.search_workspace_for_definition_simple(word, file_path, tclsh_cmd)
	elseif #matches == 1 then
		local match = matches[1]
		vim.api.nvim_win_set_cursor(0, { match.symbol.line, 0 })
		utils.notify(
			string.format("Found %s '%s' at line %d", match.symbol.type, match.symbol.name, match.symbol.line),
			vim.log.levels.INFO
		)
	else
		-- Multiple matches, show them prioritized
		if resolution and resolution.context then
			M.show_prioritized_symbol_choices(matches, word, resolution.context)
		else
			M.show_simple_symbol_choices(matches, word)
		end
	end
end

-- ADD this new function to handle semantic symbol choices:
function M.show_semantic_symbol_choices(symbols, query)
	local choices = {}

	-- Sort by priority if available, otherwise by line number
	table.sort(symbols, function(a, b)
		if a.priority and b.priority then
			return a.priority > b.priority
		end
		return a.line < b.line
	end)

	for i, symbol in ipairs(symbols) do
		local context_info = ""
		if symbol.scope and symbol.scope ~= "" then
			context_info = " [" .. symbol.scope .. "]"
		end
		if symbol.namespace_context and symbol.namespace_context ~= "" then
			context_info = context_info .. " (ns: " .. symbol.namespace_context .. ")"
		end

		local method_info = symbol.method == "semantic" and " (semantic)" or " (regex)"

		table.insert(
			choices,
			string.format(
				"%d. %s '%s'%s at line %d%s",
				i,
				symbol.type,
				symbol.name,
				context_info,
				symbol.line,
				method_info
			)
		)
	end

	vim.ui.select(choices, {
		prompt = "Multiple definitions found for '" .. query .. "':",
	}, function(choice, idx)
		if idx then
			local selected_symbol = symbols[idx]
			vim.api.nvim_win_set_cursor(0, { selected_symbol.line, 0 })
			utils.notify(
				string.format(
					"Jumped to %s '%s' at line %d (%s)",
					selected_symbol.type,
					selected_symbol.name,
					selected_symbol.line,
					selected_symbol.method or "unknown"
				),
				vim.log.levels.INFO
			)
		end
	end)
end

-- Keep all other existing functions unchanged...
-- (find_matching_symbols, show_prioritized_symbol_choices, etc.)

return M
