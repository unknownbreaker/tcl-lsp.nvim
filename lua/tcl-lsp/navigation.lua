local semantic = require("tcl-lsp.semantic")
local utils = require("tcl-lsp.utils")
local config = require("tcl-lsp.config")
local tcl = require("tcl-lsp.tcl")
local M = {}

-- DEBUG: Enhanced goto_definition with comprehensive logging
function M.goto_definition()
	print("=== DEBUG: goto_definition START (with REAL semantic engine) ===")

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
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

	-- TRY SEMANTIC CROSS-FILE RESOLUTION FIRST
	print("DEBUG: Attempting cross-file semantic resolution...")
	local workspace_symbols = semantic.resolve_symbol_across_workspace(word, file_path, cursor_line, tclsh_cmd)

	if workspace_symbols and #workspace_symbols > 0 then
		print("DEBUG: Semantic engine found", #workspace_symbols, "candidates across workspace")

		-- Filter for exact matches first
		local exact_matches = {}
		local partial_matches = {}

		for _, symbol in ipairs(workspace_symbols) do
			print("DEBUG: Candidate:", symbol.name, "in", symbol.source_file or "current file", "at line", symbol.line)
			if symbol.name == word or symbol.qualified_name == word then
				table.insert(exact_matches, symbol)
			else
				table.insert(partial_matches, symbol)
			end
		end

		local matches = #exact_matches > 0 and exact_matches or partial_matches
		print("DEBUG: Found", #exact_matches, "exact matches and", #partial_matches, "partial matches")

		if #matches == 1 then
			local match = matches[1]
			print("DEBUG: Single match found - jumping to symbol")

			-- If the symbol is in a different file, open that file first
			if match.source_file and match.source_file ~= file_path then
				print("DEBUG: Opening external file:", match.source_file)
				vim.cmd("edit " .. vim.fn.fnameescape(match.source_file))
			end

			-- Jump to the symbol location
			vim.api.nvim_win_set_cursor(0, { match.line, 0 })

			local file_indicator = match.source_file == file_path and ""
				or " (in " .. vim.fn.fnamemodify(match.source_file, ":t") .. ")"
			local import_indicator = match.is_imported and " [imported]" or ""

			utils.notify(
				string.format(
					"Found %s '%s' at line %d%s%s (semantic)",
					match.type,
					match.name,
					match.line,
					file_indicator,
					import_indicator
				),
				vim.log.levels.INFO
			)
			return
		elseif #matches > 1 then
			print("DEBUG: Multiple matches found, showing choices")
			M.show_cross_file_semantic_choices(matches, word)
			return
		end
	end

	print("DEBUG: Semantic engine found no results, falling back to single-file analysis")

	-- FALLBACK TO SINGLE-FILE ANALYSIS
	local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
	if not symbols then
		utils.notify("Failed to analyze file with TCL", vim.log.levels.ERROR)
		return
	end

	print("DEBUG: Found", #symbols, "symbols in current file")

	-- Try smart resolution first
	local resolution = tcl.resolve_symbol(word, file_path, cursor_line, tclsh_cmd)
	local matches = {}

	if resolution and resolution.resolutions then
		print("DEBUG: Using smart resolution")
		matches = M.find_matching_symbols(symbols, resolution.resolutions, word)
	end

	-- Fallback to simple matching
	if #matches == 0 then
		print("DEBUG: No smart matches, trying simple matching")
		for _, symbol in ipairs(symbols) do
			if symbol.name == word or utils.symbols_match(symbol.name, word) then
				table.insert(matches, {
					symbol = symbol,
					priority = (symbol.name == word) and 10 or 5,
					resolution = { type = "fallback", name = word },
				})
			end
		end
	end

	print("DEBUG: Total matches in current file:", #matches)

	if #matches == 0 then
		print("DEBUG: No matches found anywhere")
		utils.notify("Definition of '" .. word .. "' not found", vim.log.levels.WARN)
	elseif #matches == 1 then
		print("DEBUG: Found single match in current file")
		local match = matches[1]
		vim.api.nvim_win_set_cursor(0, { match.symbol.line, 0 })
		utils.notify(
			string.format("Found %s '%s' at line %d", match.symbol.type, match.symbol.name, match.symbol.line),
			vim.log.levels.INFO
		)
	else
		print("DEBUG: Multiple matches in current file")
		M.show_simple_symbol_choices(matches, word)
	end

	print("=== DEBUG: goto_definition END ===")
end

function M.show_cross_file_semantic_choices(symbols, query)
	print("DEBUG: Showing", #symbols, "cross-file semantic choices")

	local choices = {}

	-- Sort by source file (current file first) then by line number
	table.sort(symbols, function(a, b)
		local current_file = utils.get_current_file_path()
		local a_is_current = (a.source_file == current_file)
		local b_is_current = (b.source_file == current_file)

		if a_is_current and not b_is_current then
			return true
		elseif not a_is_current and b_is_current then
			return false
		else
			return a.line < b.line
		end
	end)

	for i, symbol in ipairs(symbols) do
		local context_info = ""
		if symbol.scope and symbol.scope ~= "" then
			context_info = " [" .. symbol.scope .. "]"
		end
		if symbol.namespace_context and symbol.namespace_context ~= "" then
			context_info = context_info .. " (ns: " .. symbol.namespace_context .. ")"
		end

		-- File information
		local current_file = utils.get_current_file_path()
		local file_info = ""
		if symbol.source_file == current_file then
			file_info = " (current file)"
		else
			local file_name = vim.fn.fnamemodify(symbol.source_file, ":t")
			file_info = " (in " .. file_name .. ")"
		end

		-- Import/visibility information
		local access_info = ""
		if symbol.is_imported then
			access_info = " [imported]"
		elseif symbol.visibility == "public" then
			access_info = " [public]"
		elseif symbol.visibility == "private" then
			access_info = " [private]"
		end

		table.insert(
			choices,
			string.format(
				"%d. %s '%s'%s at line %d%s%s (semantic)",
				i,
				symbol.type,
				symbol.name,
				context_info,
				symbol.line,
				file_info,
				access_info
			)
		)
	end

	vim.ui.select(choices, {
		prompt = "Multiple definitions found for '" .. query .. "' across workspace:",
	}, function(choice, idx)
		if idx then
			local selected_symbol = symbols[idx]

			-- Open the file if it's different from current
			local current_file = utils.get_current_file_path()
			if selected_symbol.source_file ~= current_file then
				vim.cmd("edit " .. vim.fn.fnameescape(selected_symbol.source_file))
			end

			-- Jump to the symbol
			vim.api.nvim_win_set_cursor(0, { selected_symbol.line, 0 })

			local file_indicator = selected_symbol.source_file == current_file and ""
				or " in " .. vim.fn.fnamemodify(selected_symbol.source_file, ":t")

			utils.notify(
				string.format(
					"Jumped to %s '%s' at line %d%s (semantic)",
					selected_symbol.type,
					selected_symbol.name,
					selected_symbol.line,
					file_indicator
				),
				vim.log.levels.INFO
			)
		end
	end)
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
