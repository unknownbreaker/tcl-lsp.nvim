local utils = require("tcl-lsp.utils")
local config = require("tcl-lsp.config")
local tcl = require("tcl-lsp.tcl")
local semantic = require("tcl-lsp.semantic")
local M = {}

-- Smart TCL go-to-definition using semantic resolution
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

	-- Debug: Log what we're looking for
	print("DEBUG: Looking for symbol:", word, "in file:", file_path)

	-- First try the enhanced semantic analysis
	local symbols = semantic.analyze_single_file_symbols(file_path, tclsh_cmd)

	-- Fallback to basic analysis if semantic fails
	if not symbols or #symbols == 0 then
		print("DEBUG: Semantic analysis failed or returned no symbols, trying basic analysis")
		symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
	end

	if not symbols then
		utils.notify("Failed to analyze file with TCL", vim.log.levels.ERROR)
		return
	end

	-- Debug: Log what symbols we found
	print("DEBUG: Found", #symbols, "symbols")
	for i, symbol in ipairs(symbols) do
		print(string.format("DEBUG: Symbol %d: %s '%s' at line %d", i, symbol.type, symbol.name, symbol.line))
	end

	if #symbols == 0 then
		utils.notify("No symbols found in file. Run :TclLspDebug for troubleshooting.", vim.log.levels.WARN)
		return
	end

	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

	-- Try smart resolution first using semantic engine
	local resolution = M.smart_resolve_symbol(word, file_path, cursor_line, tclsh_cmd)
	local matches = {}

	if resolution and resolution.candidates then
		-- Use smart resolution results
		print("DEBUG: Smart resolution found", #resolution.candidates, "candidates")
		matches = M.find_matching_symbols_enhanced(symbols, resolution.candidates, word)
	end

	-- Fallback to simple matching if smart resolution fails
	if #matches == 0 then
		print("DEBUG: Smart resolution failed, using fallback matching")
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

	-- Handle results
	if #matches == 0 then
		-- Try workspace search as last resort
		utils.notify("Symbol '" .. word .. "' not found in current file, searching workspace...", vim.log.levels.INFO)
		M.search_workspace_for_definition_enhanced(word, file_path, tclsh_cmd)
	elseif #matches == 1 then
		local match = matches[1]
		vim.api.nvim_win_set_cursor(0, { match.symbol.line, 0 })
		utils.notify(
			string.format("Found %s '%s' at line %d", match.symbol.type, match.symbol.name, match.symbol.line),
			vim.log.levels.INFO
		)
	else
		-- Multiple matches, show choices
		M.show_symbol_choices_enhanced(matches, word)
	end
end

-- Enhanced symbol resolution using both engines
function M.smart_resolve_symbol(symbol_name, file_path, cursor_line, tclsh_cmd)
	-- Try semantic resolution first
	local semantic_candidates = semantic.resolve_symbol_across_workspace(symbol_name, file_path, cursor_line, tclsh_cmd)

	if semantic_candidates and #semantic_candidates > 0 then
		return {
			type = "semantic",
			candidates = semantic_candidates,
			method = "workspace_semantic",
		}
	end

	-- Fallback to basic resolution
	local basic_resolution = tcl.resolve_symbol(symbol_name, file_path, cursor_line, tclsh_cmd)

	if basic_resolution and basic_resolution.resolutions then
		return {
			type = "basic",
			candidates = basic_resolution.resolutions,
			context = basic_resolution.context,
			method = "basic_resolution",
		}
	end

	return nil
end

-- Enhanced symbol matching with better priority handling
function M.find_matching_symbols_enhanced(symbols, candidates, query)
	local matches = {}

	for _, candidate in ipairs(candidates) do
		for _, symbol in ipairs(symbols) do
			local symbol_matches = false
			local match_priority = 0

			-- Enhanced matching logic
			if candidate.name then
				if symbol.name == candidate.name then
					symbol_matches = true
					match_priority = 10 -- Exact match
				elseif symbol.qualified_name == candidate.name then
					symbol_matches = true
					match_priority = 9 -- Qualified exact match
				elseif utils.symbols_match(symbol.name, candidate.name) then
					symbol_matches = true
					match_priority = 7 -- Fuzzy match
				end
			else
				-- Fallback for basic candidates
				if symbol.name == query then
					symbol_matches = true
					match_priority = 8
				elseif utils.symbols_match(symbol.name, query) then
					symbol_matches = true
					match_priority = 6
				end
			end

			if symbol_matches then
				-- Additional priority boosts
				if candidate.scope and symbol.scope == candidate.scope then
					match_priority = match_priority + 2
				end

				if candidate.visibility == "public" then
					match_priority = match_priority + 1
				end

				table.insert(matches, {
					symbol = symbol,
					candidate = candidate,
					priority = match_priority,
					resolution = candidate,
				})
			end
		end
	end

	-- Remove duplicates and sort by priority
	local seen = {}
	local unique_matches = {}

	for _, match in ipairs(matches) do
		local key = match.symbol.name .. ":" .. match.symbol.line
		if not seen[key] then
			seen[key] = true
			table.insert(unique_matches, match)
		end
	end

	table.sort(unique_matches, function(a, b)
		return a.priority > b.priority
	end)

	return unique_matches
end

-- Enhanced workspace search
function M.search_workspace_for_definition_enhanced(symbol_name, current_file, tclsh_cmd)
	-- First try semantic workspace search
	local semantic_matches = semantic.resolve_symbol_across_workspace(symbol_name, current_file, 1, tclsh_cmd)

	if semantic_matches and #semantic_matches > 0 then
		-- Filter to definitions only and group by file
		local definition_matches = {}
		for _, match in ipairs(semantic_matches) do
			if match.source_file and match.source_file ~= current_file then
				table.insert(definition_matches, {
					symbol = match,
					file = match.source_file,
					priority = (match.name == symbol_name) and 10 or 5,
				})
			end
		end

		if #definition_matches > 0 then
			M.show_workspace_choices_enhanced(definition_matches, symbol_name)
			return
		end
	end

	-- Fallback to simple workspace search
	M.search_workspace_for_definition_simple(symbol_name, current_file, tclsh_cmd)
end

-- Enhanced symbol choices display
function M.show_symbol_choices_enhanced(matches, query)
	local choices = {}

	for i, match in ipairs(matches) do
		local symbol = match.symbol
		local context_info = ""
		local method_info = ""

		-- Add context information
		if symbol.namespace_context and symbol.namespace_context ~= "" then
			context_info = " [ns: " .. symbol.namespace_context .. "]"
		elseif symbol.scope and symbol.scope ~= "" then
			context_info = " [" .. symbol.scope .. "]"
		end

		-- Add method information for debugging
		if symbol.method then
			method_info = " (" .. symbol.method .. ")"
		end

		local choice_text = string.format(
			"%d. %s '%s'%s at line %d (priority: %d)%s",
			i,
			symbol.type,
			symbol.name,
			context_info,
			symbol.line,
			match.priority,
			method_info
		)

		table.insert(choices, choice_text)
	end

	vim.ui.select(choices, {
		prompt = "Multiple definitions found for '" .. query .. "':",
	}, function(choice, idx)
		if idx then
			local selected_match = matches[idx]
			vim.api.nvim_win_set_cursor(0, { selected_match.symbol.line, 0 })
			utils.notify(
				string.format(
					"Jumped to %s '%s' at line %d",
					selected_match.symbol.type,
					selected_match.symbol.name,
					selected_match.symbol.line
				),
				vim.log.levels.INFO
			)
		end
	end)
end

-- Enhanced workspace choices display
function M.show_workspace_choices_enhanced(matches, query)
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
		local context_info = ""

		if match.symbol.namespace_context and match.symbol.namespace_context ~= "" then
			context_info = " [ns: " .. match.symbol.namespace_context .. "]"
		elseif match.symbol.scope and match.symbol.scope ~= "" then
			context_info = " [" .. match.symbol.scope .. "]"
		end

		table.insert(
			choices,
			string.format(
				"%d. %s '%s'%s in %s at line %d (priority: %d)",
				i,
				match.symbol.type,
				match.symbol.name,
				context_info,
				file_short,
				match.symbol.line,
				match.priority
			)
		)
	end

	vim.ui.select(choices, {
		prompt = "Multiple definitions found for '" .. query .. "' across workspace:",
	}, function(choice, idx)
		if idx then
			local selected_match = matches[idx]
			vim.cmd("edit " .. selected_match.file)
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
		end
	end)
end

-- Simple workspace search as fallback (keep existing implementation)
function M.search_workspace_for_definition_simple(symbol_name, current_file, tclsh_cmd)
	local files = vim.fn.glob("**/*.tcl", false, true)
	local matches = {}

	for _, file in ipairs(files) do
		if file ~= current_file then -- Skip current file
			local file_symbols = tcl.analyze_tcl_file(file, tclsh_cmd)
			if file_symbols then
				for _, symbol in ipairs(file_symbols) do
					if symbol.name == symbol_name or utils.symbols_match(symbol.name, symbol_name) then
						table.insert(matches, {
							symbol = symbol,
							file = file,
							priority = (symbol.name == symbol_name) and 10 or 5,
						})
					end
				end
			end
		end
	end

	if #matches == 0 then
		utils.notify("Definition of '" .. symbol_name .. "' not found", vim.log.levels.WARN)
	elseif #matches == 1 then
		local match = matches[1]
		vim.cmd("edit " .. match.file)
		vim.api.nvim_win_set_cursor(0, { match.symbol.line, 0 })
		utils.notify(
			string.format(
				"Found %s '%s' in %s at line %d",
				match.symbol.type,
				match.symbol.name,
				match.file,
				match.symbol.line
			),
			vim.log.levels.INFO
		)
	else
		M.show_workspace_choices_enhanced(matches, symbol_name)
	end
end

-- Rest of your existing functions remain the same...
-- [Include all other functions from the original navigation.lua]

-- TCL-powered hover using introspection
function M.hover()
	-- Try to get qualified word first, fall back to regular word
	local word, err = utils.get_qualified_word_under_cursor()
	if not word then
		word, err = utils.get_word_under_cursor()
		if not word then
			return
		end
	end

	local tclsh_cmd = config.get_tclsh_cmd()

	-- First check if it's a built-in TCL command
	local builtin_info = tcl.check_builtin_command(word, tclsh_cmd)
	if builtin_info then
		utils.notify(builtin_info.description, vim.log.levels.INFO)
		return
	end

	-- Fall back to static documentation for common commands
	local doc = tcl.get_command_documentation(word)
	if doc then
		utils.notify(word .. ":\n" .. doc, vim.log.levels.INFO)
		return
	end

	-- Check if it's a user-defined symbol in current file
	local file_path, file_err = utils.get_current_file_path()
	if file_path then
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
		if symbols then
			for _, symbol in ipairs(symbols) do
				if utils.symbols_match(symbol.name, word) then
					utils.notify(
						string.format("User-defined %s: %s\nDefined at line %d", symbol.type, symbol.name, symbol.line),
						vim.log.levels.INFO
					)
					return
				end
			end
		end
	end

	-- No documentation found
	utils.notify("No documentation found for '" .. word .. "'", vim.log.levels.INFO)
end

-- Smart find references using TCL analysis
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

		utils.create_quickfix_list(qflist, "Found " .. #references .. " references to '" .. word .. "'")
	else
		utils.notify("No references found for '" .. word .. "'", vim.log.levels.WARN)
	end
end

-- Set up navigation keymaps for TCL buffers
function M.setup_buffer_keymaps(bufnr)
	local keymaps = config.get_keymaps()
	local opts = { buffer = bufnr, silent = true }

	if keymaps.hover then
		utils.set_buffer_keymap(
			"n",
			keymaps.hover,
			M.hover,
			vim.tbl_extend("force", opts, { desc = "TCL Hover Documentation" }),
			bufnr
		)
	end

	if keymaps.goto_definition then
		utils.set_buffer_keymap(
			"n",
			keymaps.goto_definition,
			M.goto_definition,
			vim.tbl_extend("force", opts, { desc = "TCL Go to Definition" }),
			bufnr
		)
	end

	if keymaps.find_references then
		utils.set_buffer_keymap(
			"n",
			keymaps.find_references,
			M.find_references,
			vim.tbl_extend("force", opts, { desc = "TCL Find References" }),
			bufnr
		)
	end

	-- Additional convenience keymaps
	utils.set_buffer_keymap("n", "<leader>tr", function()
		-- Enhanced workspace references
		M.find_workspace_references()
	end, vim.tbl_extend("force", opts, { desc = "TCL Workspace References" }), bufnr)
end

-- Enhanced workspace references search
function M.find_workspace_references()
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

	-- Try semantic workspace references first
	local all_references = semantic.find_references_across_workspace(word, file_path, tclsh_cmd)

	if not all_references or #all_references == 0 then
		-- Fallback to simple search
		local files = vim.fn.glob("**/*.tcl", false, true)
		all_references = {}

		for _, file in ipairs(files) do
			local references = tcl.find_symbol_references(file, word, tclsh_cmd)
			if references then
				for _, ref in ipairs(references) do
					table.insert(all_references, {
						filename = file,
						line = ref.line,
						text = string.format("[%s] %s", ref.context:gsub("_", " "), ref.text),
					})
				end
			end
		end
	else
		-- Convert semantic results to quickfix format
		local qf_references = {}
		for _, ref in ipairs(all_references) do
			table.insert(qf_references, {
				filename = ref.source_file,
				line = ref.line,
				text = string.format("[%s] %s", ref.context:gsub("_", " "), ref.text),
			})
		end
		all_references = qf_references
	end

	if #all_references > 0 then
		utils.create_quickfix_list(
			all_references,
			"Found " .. #all_references .. " references to '" .. word .. "' across workspace"
		)
	else
		utils.notify("No references found for '" .. word .. "' in workspace", vim.log.levels.WARN)
	end
end

return M
