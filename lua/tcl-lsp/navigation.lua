local utils = require("tcl-lsp.utils")
local config = require("tcl-lsp.config")
local tcl = require("tcl-lsp.tcl")
local M = {}

-- Smart TCL go-to-definition using tclsh analysis
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
	local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

	if not symbols then
		utils.notify("Failed to analyze file with TCL", vim.log.levels.ERROR)
		return
	end

	-- Look for matching symbol in current file
	-- Try exact match first, then partial matches
	local exact_match = nil
	local partial_matches = {}

	for _, symbol in ipairs(symbols) do
		if symbol.name == word then
			exact_match = symbol
			break
		elseif M.symbol_matches_query(symbol.name, word) then
			table.insert(partial_matches, symbol)
		end
	end

	if exact_match then
		vim.api.nvim_win_set_cursor(0, { exact_match.line, 0 })
		utils.notify(
			string.format("Found %s '%s' at line %d", exact_match.type, word, exact_match.line),
			vim.log.levels.INFO
		)
		return
	elseif #partial_matches == 1 then
		local match = partial_matches[1]
		vim.api.nvim_win_set_cursor(0, { match.line, 0 })
		utils.notify(string.format("Found %s '%s' at line %d", match.type, match.name, match.line), vim.log.levels.INFO)
		return
	elseif #partial_matches > 1 then
		-- Multiple matches, let user choose
		M.show_symbol_choices(partial_matches, word)
		return
	end

	-- If not found in current file, search workspace
	utils.notify("Symbol '" .. word .. "' not found in current file, searching workspace...", vim.log.levels.INFO)

	M.search_workspace_for_definition(word, file_path, tclsh_cmd)
end

-- Check if a symbol name matches a query (handles namespace syntax)
function M.symbol_matches_query(symbol_name, query)
	return utils.symbols_match(symbol_name, query)
end

-- Show multiple symbol choices to user
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
