local utils = require("tcl-lsp.utils")
local config = require("tcl-lsp.config")
local tcl = require("tcl-lsp.tcl")
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
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

	-- Use smart symbol resolution
	local resolution = tcl.resolve_symbol(word, file_path, cursor_line, tclsh_cmd)
	if not resolution then
		utils.notify("Failed to analyze symbol context", vim.log.levels.ERROR)
		return
	end

	-- Get all symbols from current file
	local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
	if not symbols then
		utils.notify("Failed to analyze file with TCL", vim.log.levels.ERROR)
		return
	end

	-- Find the best matching symbols based on resolution priority
	local matches = M.find_matching_symbols(symbols, resolution.resolutions, word)

	if #matches == 0 then
		-- Try workspace search if nothing found locally
		utils.notify("Symbol '" .. word .. "' not found in current file, searching workspace...", vim.log.levels.INFO)
		M.search_workspace_for_definition_smart(word, file_path, cursor_line, tclsh_cmd)
	elseif #matches == 1 then
		local match = matches[1]
		vim.api.nvim_win_set_cursor(0, { match.symbol.line, 0 })
		utils.notify(
			string.format(
				"Found %s '%s' at line %d (priority: %d)",
				match.symbol.type,
				match.symbol.name,
				match.symbol.line,
				match.priority
			),
			vim.log.levels.INFO
		)
	else
		-- Multiple matches, show them prioritized
		M.show_prioritized_symbol_choices(matches, word, resolution.context)
	end
end

-- Find matching symbols based on resolution priority
function M.find_matching_symbols(symbols, resolutions, query)
	local matches = {}

	for _, resolution in ipairs(resolutions) do
		for _, symbol in ipairs(symbols) do
			local symbol_matches = false

			-- Check if symbol matches this resolution
			if resolution.type == "qualified_name" and symbol.name == resolution.name then
				symbol_matches = true
			elseif
				resolution.type == "namespace_qualified"
				and (symbol.name == resolution.name or symbol.qualified_name == resolution.name)
			then
				symbol_matches = true
			elseif
				resolution.type == "proc_local"
				and symbol.name == query
				and (symbol.scope == "proc_local" or symbol.scope == "local")
			then
				symbol_matches = true
			elseif
				resolution.type == "global"
				and symbol.name == query
				and (symbol.scope == "global" or symbol.type == "global")
			then
				symbol_matches = true
			elseif resolution.type == "package_qualified" and symbol.name == resolution.name then
				symbol_matches = true
			elseif symbol.name == query then -- Fallback exact match
				symbol_matches = true
			end

			if symbol_matches then
				table.insert(matches, {
					symbol = symbol,
					resolution = resolution,
					priority = resolution.priority,
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

-- Show prioritized symbol choices with context
function M.show_prioritized_symbol_choices(matches, query, context)
	local choices = {}

	for i, match in ipairs(matches) do
		local symbol = match.symbol
		local context_info = ""

		if symbol.scope and symbol.scope ~= "" then
			context_info = " [" .. symbol.scope .. "]"
		elseif symbol.context and symbol.context ~= "" then
			context_info = " [ns: " .. symbol.context .. "]"
		end

		table.insert(
			choices,
			string.format(
				"%d. %s '%s'%s at line %d (priority: %d)",
				i,
				symbol.type,
				symbol.name,
				context_info,
				symbol.line,
				match.priority
			)
		)
	end

	local context_str = ""
	if context.namespace then
		context_str = context_str .. "namespace: " .. context.namespace
	end
	if context.proc then
		if context_str ~= "" then
			context_str = context_str .. ", "
		end
		context_str = context_str .. "procedure: " .. context.proc
	end

	local prompt = "Multiple definitions found for '" .. query .. "'"
	if context_str ~= "" then
		prompt = prompt .. " (in " .. context_str .. ")"
	end
	prompt = prompt .. ":"

	vim.ui.select(choices, {
		prompt = prompt,
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

-- Smart workspace search with semantic resolution
function M.search_workspace_for_definition_smart(symbol_name, current_file, cursor_line, tclsh_cmd)
	-- Get resolution for the symbol
	local resolution = tcl.resolve_symbol(symbol_name, current_file, cursor_line, tclsh_cmd)

	local files = vim.fn.glob("**/*.tcl", false, true)
	local matches = {}

	for _, file in ipairs(files) do
		if file ~= current_file then -- Skip current file
			local file_symbols = tcl.analyze_tcl_file(file, tclsh_cmd)
			if file_symbols then
				local file_matches = M.find_matching_symbols(file_symbols, resolution.resolutions, symbol_name)
				for _, match in ipairs(file_matches) do
					table.insert(matches, {
						symbol = match.symbol,
						file = file,
						priority = match.priority,
						resolution = match.resolution,
					})
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
				"Found %s '%s' in %s at line %d (priority: %d)",
				match.symbol.type,
				match.symbol.name,
				match.file,
				match.symbol.line,
				match.priority
			),
			vim.log.levels.INFO
		)
	else
		-- Multiple matches across files
		M.show_workspace_prioritized_choices(matches, symbol_name, resolution.context)
	end
end

-- Show prioritized workspace symbol choices
function M.show_workspace_prioritized_choices(matches, query, context)
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

		if match.symbol.scope and match.symbol.scope ~= "" then
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

-- Check if a symbol name matches a query (handles namespace syntax)
function M.symbol_matches_query(symbol_name, query)
	return utils.symbols_match(symbol_name, query)
end

-- Show multiple symbol choices to user (legacy function for backward compatibility)
function M.show_symbol_choices(symbols, query)
	local choices = {}
	for i, symbol in ipairs(symbols) do
		table.insert(choices, string.format("%d. %s [%s] at line %d", i, symbol.name, symbol.type, symbol.line))
	end

	vim.ui.select(choices, {
		prompt = "Multiple definitions found for '" .. query .. "':",
	}, function(choice, idx)
		if idx then
			local selected_symbol = symbols[idx]
			vim.api.nvim_win_set_cursor(0, { selected_symbol.line, 0 })
			utils.notify(
				string.format(
					"Jumped to %s '%s' at line %d",
					selected_symbol.type,
					selected_symbol.name,
					selected_symbol.line
				),
				vim.log.levels.INFO
			)
		end
	end)
end

-- Search workspace for symbol definition with improved matching
function M.search_workspace_for_definition(symbol_name, current_file, tclsh_cmd)
	-- Search in all TCL files in current directory and subdirectories
	local files = vim.fn.glob("**/*.tcl", false, true)
	local matches = {}

	for _, file in ipairs(files) do
		if file ~= current_file then -- Skip current file
			local file_symbols = tcl.analyze_tcl_file(file, tclsh_cmd)
			if file_symbols then
				for _, symbol in ipairs(file_symbols) do
					if M.symbol_matches_query(symbol.name, symbol_name) then
						table.insert(matches, {
							symbol = symbol,
							file = file,
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
		-- Multiple matches across files
		M.show_workspace_symbol_choices(matches, symbol_name)
	end
end

-- Show multiple workspace symbol choices
function M.show_workspace_symbol_choices(matches, query)
	local choices = {}
	for i, match in ipairs(matches) do
		local file_short = vim.fn.fnamemodify(match.file, ":t")
		table.insert(
			choices,
			string.format(
				"%d. %s [%s] in %s at line %d",
				i,
				match.symbol.name,
				match.symbol.type,
				file_short,
				match.symbol.line
			)
		)
	end

	vim.ui.select(choices, {
		prompt = "Multiple definitions found for '" .. query .. "':",
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

-- Find references across the entire workspace
function M.find_workspace_references()
	-- Try to get qualified word first, fall back to regular word
	local word, err = utils.get_qualified_word_under_cursor()
	if not word then
		word, err = utils.get_word_under_cursor()
		if not word then
			utils.notify(err, vim.log.levels.WARN)
			return
		end
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	local files = vim.fn.glob("**/*.tcl", false, true)
	local all_references = {}

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

	if #all_references > 0 then
		utils.create_quickfix_list(
			all_references,
			"Found " .. #all_references .. " references to '" .. word .. "' across workspace"
		)
	else
		utils.notify("No references found for '" .. word .. "' in workspace", vim.log.levels.WARN)
	end
end

-- Navigate to next/previous reference in quickfix list
function M.next_reference()
	local qf_list = vim.fn.getqflist()
	if #qf_list == 0 then
		utils.notify("No references in quickfix list", vim.log.levels.WARN)
		return
	end

	vim.cmd("cnext")
end

function M.previous_reference()
	local qf_list = vim.fn.getqflist()
	if #qf_list == 0 then
		utils.notify("No references in quickfix list", vim.log.levels.WARN)
		return
	end

	vim.cmd("cprevious")
end

-- Enhanced hover with context information
function M.enhanced_hover()
	local word, err = utils.get_word_under_cursor()
	if not word then
		return
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	local file_path, _ = utils.get_current_file_path()

	local hover_info = {
		symbol = word,
		type = "unknown",
		description = "",
		location = nil,
		references_count = 0,
	}

	-- Check built-in commands first
	local builtin_info = tcl.check_builtin_command(word, tclsh_cmd)
	if builtin_info then
		hover_info.type = builtin_info.type
		hover_info.description = builtin_info.description
	else
		-- Check static documentation
		local doc = tcl.get_command_documentation(word)
		if doc then
			hover_info.type = "documented_command"
			hover_info.description = word .. ":\n" .. doc
		end
	end

	-- If we have a file, check for user-defined symbols
	if file_path then
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
		if symbols then
			for _, symbol in ipairs(symbols) do
				if symbol.name == word then
					hover_info.type = "user_defined_" .. symbol.type
					hover_info.description =
						string.format("User-defined %s: %s\nDefined at line %d", symbol.type, word, symbol.line)
					hover_info.location = { file = file_path, line = symbol.line }
					break
				end
			end
		end

		-- Count references
		local references = tcl.find_symbol_references(file_path, word, tclsh_cmd)
		if references then
			hover_info.references_count = #references
		end
	end

	-- Display enhanced hover information
	local hover_text = hover_info.description
	if hover_info.references_count > 0 then
		hover_text = hover_text .. string.format("\n\nReferences: %d in current file", hover_info.references_count)
	end

	if hover_text ~= "" then
		utils.notify(hover_text, vim.log.levels.INFO)
	else
		utils.notify("No information available for '" .. word .. "'", vim.log.levels.INFO)
	end
end

-- Jump to symbol definition in any open buffer
function M.jump_to_symbol_in_buffers(symbol_name)
	local tclsh_cmd = config.get_tclsh_cmd()

	-- Get all loaded buffers
	local buffers = vim.api.nvim_list_bufs()

	for _, bufnr in ipairs(buffers) do
		if vim.api.nvim_buf_is_loaded(bufnr) and utils.is_tcl_file(bufnr) then
			local buf_name = vim.api.nvim_buf_get_name(bufnr)
			if buf_name and buf_name ~= "" then
				local symbols = tcl.analyze_tcl_file(buf_name, tclsh_cmd)
				if symbols then
					for _, symbol in ipairs(symbols) do
						if symbol.name == symbol_name then
							-- Switch to buffer and jump to line
							vim.api.nvim_set_current_buf(bufnr)
							vim.api.nvim_win_set_cursor(0, { symbol.line, 0 })
							utils.notify(
								string.format(
									"Found %s '%s' in %s at line %d",
									symbol.type,
									symbol_name,
									vim.fn.fnamemodify(buf_name, ":t"),
									symbol.line
								),
								vim.log.levels.INFO
							)
							return true
						end
					end
				end
			end
		end
	end

	return false
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
	utils.set_buffer_keymap(
		"n",
		"<leader>tr",
		M.find_workspace_references,
		vim.tbl_extend("force", opts, { desc = "TCL Workspace References" }),
		bufnr
	)
	utils.set_buffer_keymap(
		"n",
		"<leader>th",
		M.enhanced_hover,
		vim.tbl_extend("force", opts, { desc = "TCL Enhanced Hover" }),
		bufnr
	)
	utils.set_buffer_keymap(
		"n",
		"]r",
		M.next_reference,
		vim.tbl_extend("force", opts, { desc = "Next Reference" }),
		bufnr
	)
	utils.set_buffer_keymap(
		"n",
		"[r",
		M.previous_reference,
		vim.tbl_extend("force", opts, { desc = "Previous Reference" }),
		bufnr
	)
end

return M
