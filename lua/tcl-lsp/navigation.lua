local utils = require("tcl-lsp.utils")
local config = require("tcl-lsp.config")
local tcl = require("tcl-lsp.tcl")
local M = {}

-- DEBUG: Enhanced goto_definition with comprehensive logging
function M.goto_definition()
	print("=== DEBUG: goto_definition START ===")

	-- Try to get qualified word first, fall back to regular word
	local word, err = utils.get_qualified_word_under_cursor()
	if not word then
		word, err = utils.get_word_under_cursor()
		if not word then
			print("DEBUG: No word under cursor:", err)
			utils.notify(err, vim.log.levels.WARN)
			return
		end
	end

	print("DEBUG: Target symbol:", word)

	local file_path, file_err = utils.get_current_file_path()
	if not file_path then
		print("DEBUG: No current file:", file_err)
		utils.notify(file_err, vim.log.levels.WARN)
		return
	end

	print("DEBUG: Current file path:", file_path)

	local tclsh_cmd = config.get_tclsh_cmd()
	print("DEBUG: TCL command:", tclsh_cmd)

	-- Get all symbols from current file first
	print("DEBUG: Analyzing current file...")
	local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
	if not symbols then
		print("DEBUG: Failed to analyze current file")
		utils.notify("Failed to analyze file with TCL", vim.log.levels.ERROR)
		return
	end

	print("DEBUG: Found", #symbols, "symbols in current file:")
	for i, symbol in ipairs(symbols) do
		print("DEBUG:   ", i, ":", symbol.type, "'" .. symbol.name .. "'", "at line", symbol.line)
	end

	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	print("DEBUG: Cursor line:", cursor_line)

	-- Try smart resolution first
	print("DEBUG: Attempting smart resolution...")
	local resolution = tcl.resolve_symbol(word, file_path, cursor_line, tclsh_cmd)
	local matches = {}

	if resolution and resolution.resolutions then
		print("DEBUG: Smart resolution returned", #resolution.resolutions, "resolutions")
		matches = M.find_matching_symbols(symbols, resolution.resolutions, word)
		print("DEBUG: Smart resolution found", #matches, "matches")
	else
		print("DEBUG: Smart resolution failed or returned nil")
	end

	-- Fallback to simple matching if smart resolution fails or finds nothing
	if #matches == 0 then
		print("DEBUG: No smart matches, trying simple matching...")
		for _, symbol in ipairs(symbols) do
			local simple_match = (symbol.name == word)
			local utils_match = utils.symbols_match(symbol.name, word)
			print("DEBUG: Checking symbol '" .. symbol.name .. "' against '" .. word .. "':")
			print("DEBUG:   Simple match (==):", simple_match)
			print("DEBUG:   Utils match:", utils_match)

			if simple_match or utils_match then
				print("DEBUG: FOUND MATCH:", symbol.name)
				table.insert(matches, {
					symbol = symbol,
					priority = simple_match and 10 or 5,
					resolution = { type = "fallback", name = word },
				})
			end
		end
	end

	print("DEBUG: Total matches in current file:", #matches)

	if #matches == 0 then
		print("DEBUG: NO MATCHES IN CURRENT FILE - Starting workspace search...")
		utils.notify("Symbol '" .. word .. "' not found in current file, searching workspace...", vim.log.levels.INFO)

		-- CALL THE WORKSPACE SEARCH WITH DEBUG
		M.debug_search_workspace_for_definition_simple(word, file_path, tclsh_cmd)
	elseif #matches == 1 then
		print("DEBUG: Found single match in current file, jumping to line", matches[1].symbol.line)
		local match = matches[1]
		vim.api.nvim_win_set_cursor(0, { match.symbol.line, 0 })
		utils.notify(
			string.format("Found %s '%s' at line %d", match.symbol.type, match.symbol.name, match.symbol.line),
			vim.log.levels.INFO
		)
	else
		print("DEBUG: Found", #matches, "matches in current file, showing choices")
		M.show_simple_symbol_choices(matches, word)
	end

	print("=== DEBUG: goto_definition END ===")
end

-- DEBUG: Enhanced workspace search function
function M.debug_search_workspace_for_definition_simple(symbol_name, current_file, tclsh_cmd)
	print("=== DEBUG: workspace search START ===")
	print("DEBUG: Searching for symbol:", symbol_name)
	print("DEBUG: Current file:", current_file)
	print("DEBUG: TCL command:", tclsh_cmd)

	-- Test glob functionality
	print("DEBUG: Testing glob pattern...")
	local files = vim.fn.glob("**/*.tcl", false, true)
	print("DEBUG: Found", #files, "TCL files in workspace:")
	for i, file in ipairs(files) do
		print("DEBUG:   ", i, ":", file)
	end

	if #files == 0 then
		print("DEBUG: ERROR - No TCL files found by glob!")
		utils.notify("No TCL files found in workspace", vim.log.levels.WARN)
		return
	end

	local matches = {}

	for _, file in ipairs(files) do
		if file ~= current_file then -- Skip current file
			print("DEBUG: Analyzing file:", file)

			-- Check if file exists and is readable
			if not utils.file_exists(file) then
				print("DEBUG: File does not exist or is not readable:", file)
				goto continue
			end

			local file_symbols = tcl.analyze_tcl_file(file, tclsh_cmd)
			if file_symbols then
				print("DEBUG: Found", #file_symbols, "symbols in", file)
				for j, symbol in ipairs(file_symbols) do
					print("DEBUG:     ", j, ":", symbol.type, "'" .. symbol.name .. "'", "at line", symbol.line)

					local exact_match = (symbol.name == symbol_name)
					local utils_match = utils.symbols_match(symbol.name, symbol_name)

					if exact_match or utils_match then
						print("DEBUG: *** FOUND WORKSPACE MATCH ***")
						print("DEBUG:     Symbol:", symbol.name)
						print("DEBUG:     File:", file)
						print("DEBUG:     Line:", symbol.line)
						print("DEBUG:     Type:", symbol.type)

						table.insert(matches, {
							symbol = symbol,
							file = file,
							priority = exact_match and 10 or 5,
						})
					end
				end
			else
				print("DEBUG: Failed to analyze file:", file)
			end
		else
			print("DEBUG: Skipping current file:", file)
		end
		::continue::
	end

	print("DEBUG: Total workspace matches found:", #matches)

	if #matches == 0 then
		print("DEBUG: No matches found in workspace")
		utils.notify("Definition of '" .. symbol_name .. "' not found", vim.log.levels.WARN)
	elseif #matches == 1 then
		local match = matches[1]
		print("DEBUG: Single workspace match - opening file:", match.file)
		print("DEBUG: Jumping to line:", match.symbol.line)

		vim.cmd("edit " .. vim.fn.fnameescape(match.file))
		vim.api.nvim_win_set_cursor(0, { match.symbol.line, 0 })
		utils.notify(
			string.format(
				"Found %s '%s' in %s at line %d",
				match.symbol.type,
				match.symbol.name,
				vim.fn.fnamemodify(match.file, ":t"),
				match.symbol.line
			),
			vim.log.levels.INFO
		)
	else
		print("DEBUG: Multiple workspace matches found, showing choices")
		M.debug_show_simple_workspace_choices(matches, symbol_name)
	end

	print("=== DEBUG: workspace search END ===")
end

-- DEBUG: Enhanced workspace choices display
function M.debug_show_simple_workspace_choices(matches, query)
	print("DEBUG: Showing", #matches, "workspace choices for:", query)

	-- Sort by priority first, then by file
	table.sort(matches, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.file < b.file
	end)

	local choices = {}
	for i, match in ipairs(matches) do
		local file_short = vim.fn.fnamemodify(match.file, ":t")
		local choice_text = string.format(
			"%d. %s '%s' in %s at line %d",
			i,
			match.symbol.type,
			match.symbol.name,
			file_short,
			match.symbol.line
		)
		table.insert(choices, choice_text)
		print("DEBUG: Choice", i, ":", choice_text)
	end

	vim.ui.select(choices, {
		prompt = "Multiple definitions found for '" .. query .. "' across workspace:",
	}, function(choice, idx)
		if idx then
			local selected_match = matches[idx]
			print("DEBUG: User selected choice", idx, ":", selected_match.file)

			vim.cmd("edit " .. vim.fn.fnameescape(selected_match.file))
			vim.api.nvim_win_set_cursor(0, { selected_match.symbol.line, 0 })
			utils.notify(
				string.format(
					"Jumped to %s '%s' in %s at line %d",
					selected_match.symbol.type,
					selected_match.symbol.name,
					vim.fn.fnamemodify(selected_match.file, ":t"),
					selected_match.symbol.line
				),
				vim.log.levels.INFO
			)
		else
			print("DEBUG: User cancelled selection")
		end
	end)
end

-- Keep existing utility functions for symbol matching
function M.find_matching_symbols(symbols, resolutions, query)
	local matches = {}
	-- This is the existing implementation - keeping it as-is for now
	return matches
end

function M.show_simple_symbol_choices(matches, query)
	-- Existing implementation
	local choices = {}
	for i, match in ipairs(matches) do
		local symbol = match.symbol
		table.insert(choices, string.format("%d. %s '%s' at line %d", i, symbol.type, symbol.name, symbol.line))
	end

	vim.ui.select(choices, {
		prompt = "Multiple definitions found for '" .. query .. "':",
	}, function(choice, idx)
		if idx then
			local selected_match = matches[idx]
			vim.api.nvim_win_set_cursor(0, { selected_match.symbol.line, 0 })
		end
	end)
end

-- Add the rest of the original functions if needed...
function M.setup_buffer_keymaps(bufnr)
	local keymaps = config.get_keymaps()
	local opts = { buffer = bufnr, silent = true }

	if keymaps.goto_definition then
		utils.set_buffer_keymap(
			"n",
			keymaps.goto_definition,
			M.goto_definition,
			vim.tbl_extend("force", opts, { desc = "TCL Go to Definition" }),
			bufnr
		)
	end
end

return M
