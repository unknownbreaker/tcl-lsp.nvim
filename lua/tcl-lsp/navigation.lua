local utils = require("tcl-lsp.utils")
local config = require("tcl-lsp.config")
local tcl = require("tcl-lsp.tcl")
local semantic = require("tcl-lsp.semantic") -- ADD this line at the top
local M = {}

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

	-- TRY CROSS-FILE SEMANTIC RESOLUTION FIRST
	local workspace_symbols = semantic.resolve_symbol_across_workspace(word, file_path, cursor_line, tclsh_cmd)

	if workspace_symbols and #workspace_symbols > 0 then
		print("DEBUG: Using cross-file semantic goto_definition - found", #workspace_symbols, "candidates")

		-- Filter for exact matches first
		local exact_matches = {}
		local partial_matches = {}

		for _, symbol in ipairs(workspace_symbols) do
			if symbol.name == word or symbol.qualified_name == word then
				table.insert(exact_matches, symbol)
			else
				table.insert(partial_matches, symbol)
			end
		end

		local matches = #exact_matches > 0 and exact_matches or partial_matches

		if #matches == 1 then
			local match = matches[1]

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
			M.show_cross_file_symbol_choices(matches, word)
			return
		end
	end

	print("DEBUG: Falling back to existing goto_definition logic")

	-- FALLBACK TO EXISTING LOGIC (unchanged from before)
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

-- Show cross-file symbol choices with file information
function M.show_cross_file_symbol_choices(symbols, query)
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
			-- Both in same category, sort by line number
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

		local method_info = ""
		if symbol.method then
			method_info = " (" .. symbol.method .. ")"
		end

		table.insert(
			choices,
			string.format(
				"%d. %s '%s'%s at line %d%s%s%s",
				i,
				symbol.type,
				symbol.name,
				context_info,
				symbol.line,
				file_info,
				access_info,
				method_info
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
					"Jumped to %s '%s' at line %d%s (%s)",
					selected_symbol.type,
					selected_symbol.name,
					selected_symbol.line,
					file_indicator,
					selected_symbol.method or "unknown"
				),
				vim.log.levels.INFO
			)
		end
	end)
end

function M.find_references()
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

	-- TRY CROSS-FILE SEMANTIC REFERENCE FINDING FIRST
	local workspace_refs = semantic.find_references_across_workspace(word, file_path, tclsh_cmd)

	if workspace_refs and #workspace_refs > 0 then
		print("DEBUG: Using cross-file semantic reference finding - found", #workspace_refs, "references")

		local qflist = {}
		for _, ref in ipairs(workspace_refs) do
			local file_name = ref.source_file or file_path
			local file_display = vim.fn.fnamemodify(file_name, ":t")
			local context_desc = ref.context:gsub("_", " ")
			local external_indicator = ref.is_external and " [ext]" or ""

			table.insert(qflist, {
				filename = file_name,
				lnum = ref.line,
				text = string.format("[%s%s] %s", context_desc, external_indicator, ref.text),
			})
		end

		utils.create_quickfix_list(
			qflist,
			"Found " .. #workspace_refs .. " references to '" .. word .. "' across workspace"
		)
		return
	end

	-- FALLBACK TO EXISTING SINGLE-FILE REFERENCE FINDING
	print("DEBUG: Falling back to single-file reference finding")

	local references = tcl.find_symbol_references(file_path, word, tclsh_cmd)

	if not references then
		utils.notify("Failed to analyze references", vim.log.levels.ERROR)
		return
	end

	if #references > 0 then
		local qflist = {}
		for _, ref in ipairs(references) do
			local desc = ref.context:gsub("_", " ")
			table.insert(qflist, {
				bufnr = vim.api.nvim_get_current_buf(),
				lnum = ref.line,
				text = string.format("[%s] %s", desc, ref.text),
			})
		end

		utils.create_quickfix_list(qflist, "Found " .. #references .. " references to '" .. word .. "' in current file")
	else
		utils.notify("No references found for '" .. word .. "'", vim.log.levels.WARN)
	end
end

return M
