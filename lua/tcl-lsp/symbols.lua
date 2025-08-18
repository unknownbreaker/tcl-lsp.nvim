local utils = require("tcl-lsp.utils")
local config = require("tcl-lsp.config")
local tcl = require("tcl-lsp.tcl")

local M = {}

-- Enhanced document symbols using async TCL analysis
function M.document_symbols_async(callback)
	local file_path, err = utils.get_current_file_path()
	if not file_path then
		if callback then
			callback(nil, err)
		end
		return
	end

	local tclsh_cmd = config.get_tclsh_cmd()

	-- Show loading indicator
	utils.notify("Analyzing symbols...", vim.log.levels.INFO)

	tcl.analyze_tcl_file_async(file_path, tclsh_cmd, function(symbols, analysis_err)
		if analysis_err then
			utils.notify("Symbol analysis failed: " .. analysis_err, vim.log.levels.ERROR)
			if callback then
				callback(nil, analysis_err)
			end
			return
		end

		if not symbols or #symbols == 0 then
			-- Try debug analysis as fallback
			utils.notify("No symbols found. Running debug analysis...", vim.log.levels.WARN)

			tcl.debug_symbols_async(file_path, tclsh_cmd, function(debug_info, debug_err)
				if debug_info and debug_info.symbols and #debug_info.symbols > 0 then
					M.display_symbols(debug_info.symbols, file_path)
					if callback then
						callback(debug_info.symbols, nil)
					end
				else
					utils.notify(
						"Debug analysis also found no symbols. Check :TclInfo for setup issues.",
						vim.log.levels.ERROR
					)
					if callback then
						callback(nil, "No symbols found")
					end
				end
			end)
			return
		end

		M.display_symbols(symbols, file_path)
		if callback then
			callback(symbols, nil)
		end
	end)
end

-- Synchronous wrapper for backward compatibility
function M.document_symbols()
	M.document_symbols_async()
end

-- Display symbols in quickfix list
function M.display_symbols(symbols, file_path)
	-- Group symbols by type for better organization
	local grouped = {}
	local type_counts = {}

	for _, symbol in ipairs(symbols) do
		local symbol_type = symbol.type
		if not grouped[symbol_type] then
			grouped[symbol_type] = {}
			type_counts[symbol_type] = 0
		end
		table.insert(grouped[symbol_type], symbol)
		type_counts[symbol_type] = type_counts[symbol_type] + 1
	end

	-- Create quickfix list with grouped symbols
	local qflist = {}
	local type_order =
		{ "namespace", "procedure", "variable", "namespace_variable", "array", "global", "package", "source" }

	for _, type_name in ipairs(type_order) do
		local type_symbols = grouped[type_name]
		if type_symbols and #type_symbols > 0 then
			-- Add type header
			table.insert(qflist, {
				bufnr = vim.api.nvim_get_current_buf(),
				lnum = 1,
				text = string.format("=== %s (%d) ===", type_name:upper(), #type_symbols),
			})

			-- Sort symbols by line number
			table.sort(type_symbols, function(a, b)
				return a.line < b.line
			end)

			for _, symbol in ipairs(type_symbols) do
				local display_name = symbol.qualified_name or symbol.name
				local context_info = ""

				-- Add context information
				if symbol.namespace_context and symbol.namespace_context ~= "" then
					context_info = context_info .. " [ns:" .. symbol.namespace_context .. "]"
				end
				if symbol.scope and symbol.scope ~= "" and symbol.scope ~= "global" then
					context_info = context_info .. " [" .. symbol.scope .. "]"
				end
				if symbol.args and symbol.args ~= "" then
					context_info = context_info .. " (" .. symbol.args .. ")"
				end

				table.insert(qflist, {
					bufnr = vim.api.nvim_get_current_buf(),
					lnum = symbol.line,
					text = string.format("  %s%s", display_name, context_info),
				})
			end
		end
	end

	if #qflist > 0 then
		utils.create_quickfix_list(
			qflist,
			string.format("Found %d symbols in %d categories", #symbols, vim.tbl_count(grouped))
		)
	else
		utils.notify("No symbols could be displayed", vim.log.levels.WARN)
	end
end

-- Enhanced workspace symbols using async analysis
function M.workspace_symbols_async(query, callback)
	if not query then
		vim.ui.input({ prompt = "Symbol name: " }, function(input)
			if input and input ~= "" then
				M.search_workspace_symbols_async(input, callback)
			end
		end)
	else
		M.search_workspace_symbols_async(query, callback)
	end
end

-- Synchronous wrapper
function M.workspace_symbols(query)
	M.workspace_symbols_async(query)
end

-- Search for symbols across workspace with async analysis
function M.search_workspace_symbols_async(query, callback)
	local tclsh_cmd = config.get_tclsh_cmd()
	local files = vim.fn.glob("**/*.tcl", false, true)

	if #files == 0 then
		utils.notify("No TCL files found in workspace", vim.log.levels.WARN)
		if callback then
			callback({}, nil)
		end
		return
	end

	-- Show progress indicator
	utils.notify(string.format("Searching %d files for '%s'...", #files, query), vim.log.levels.INFO)

	-- Use batch analysis for better performance
	tcl.batch_analyze_files_async(files, tclsh_cmd, function(file_results, err)
		if err then
			utils.notify("Workspace analysis failed: " .. err, vim.log.levels.ERROR)
			if callback then
				callback(nil, err)
			end
			return
		end

		local matches = {}
		for file_path, symbols in pairs(file_results) do
			if symbols then
				for _, symbol in ipairs(symbols) do
					if M.symbol_matches_query(symbol, query) then
						symbol.source_file = file_path
						table.insert(matches, {
							symbol = symbol,
							file = file_path,
							score = M.calculate_match_score(symbol, query),
						})
					end
				end
			end
		end

		if #matches > 0 then
			M.show_workspace_matches(matches, query)
			if callback then
				callback(matches, nil)
			end
		else
			utils.notify("No matches found for '" .. query .. "'", vim.log.levels.WARN)
			if callback then
				callback({}, nil)
			end
		end
	end)
end

-- Synchronous wrapper
function M.search_workspace_symbols(query)
	M.search_workspace_symbols_async(query)
end

-- Check if symbol matches query
function M.symbol_matches_query(symbol, query)
	if not symbol or not query then
		return false
	end

	local name = symbol.name or ""
	local qualified_name = symbol.qualified_name or ""

	-- Exact matches
	if name == query or qualified_name == query then
		return true
	end

	-- Partial matches
	if name:find(query, 1, true) or qualified_name:find(query, 1, true) then
		return true
	end

	-- Unqualified match (for namespace-qualified symbols)
	if qualified_name:match("::" .. query .. "$") then
		return true
	end

	return false
end

-- Calculate match score for sorting
function M.calculate_match_score(symbol, query)
	local score = 0
	local name = symbol.name or ""
	local qualified_name = symbol.qualified_name or ""

	-- Exact name match gets highest score
	if name == query then
		score = score + 100
	elseif qualified_name == query then
		score = score + 95
	elseif name:match("^" .. query) then
		score = score + 80
	elseif qualified_name:match("^" .. query) then
		score = score + 75
	elseif name:find(query, 1, true) then
		score = score + 60
	elseif qualified_name:find(query, 1, true) then
		score = score + 55
	end

	-- Boost score based on symbol type priority
	local type_priority = {
		procedure = 20,
		namespace = 15,
		variable = 10,
		namespace_variable = 8,
		array = 6,
		global = 5,
		package = 3,
		source = 1,
	}
	score = score + (type_priority[symbol.type] or 0)

	-- Boost local file matches
	local current_file = utils.get_current_file_path()
	if current_file and symbol.source_file == current_file then
		score = score + 25
	end

	return score
end

-- Show workspace matches with enhanced formatting
function M.show_workspace_matches(matches, query)
	-- Sort by score (highest first)
	table.sort(matches, function(a, b)
		return a.score > b.score
	end)

	local qflist = {}
	for _, match in ipairs(matches) do
		local symbol = match.symbol
		local file_short = match.file and vim.fn.fnamemodify(match.file, ":t") or "unknown"

		local display_name = symbol.qualified_name or symbol.name
		local context_info = ""

		if symbol.namespace_context and symbol.namespace_context ~= "" then
			context_info = context_info .. " [ns:" .. symbol.namespace_context .. "]"
		end
		if symbol.scope and symbol.scope ~= "" and symbol.scope ~= "global" then
			context_info = context_info .. " [" .. symbol.scope .. "]"
		end

		table.insert(qflist, {
			filename = match.file,
			lnum = symbol.line,
			text = string.format(
				"[%s] %s%s in %s (score: %d)",
				symbol.type,
				display_name,
				context_info,
				file_short,
				match.score
			),
		})
	end

	utils.create_quickfix_list(qflist, string.format("Found %d matches for '%s'", #matches, query))
end

-- Get symbols by type from current file (async version)
function M.get_symbols_by_type_async(symbol_type, callback)
	local file_path, err = utils.get_current_file_path()
	if not file_path then
		if callback then
			callback(nil, err)
		end
		return
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	tcl.analyze_tcl_file_async(file_path, tclsh_cmd, function(symbols, analysis_err)
		if analysis_err then
			if callback then
				callback(nil, analysis_err)
			end
			return
		end

		if not symbols then
			if callback then
				callback(nil, "Failed to analyze file")
			end
			return
		end

		local filtered_symbols = {}
		for _, symbol in ipairs(symbols) do
			if symbol.type == symbol_type then
				table.insert(filtered_symbols, symbol)
			end
		end

		if callback then
			callback(filtered_symbols, nil)
		end
	end)
end

-- Synchronous wrapper
function M.get_symbols_by_type(symbol_type)
	local file_path, err = utils.get_current_file_path()
	if not file_path then
		return nil, err
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

	if not symbols then
		return nil, "Failed to analyze file"
	end

	local filtered_symbols = {}
	for _, symbol in ipairs(symbols) do
		if symbol.type == symbol_type then
			table.insert(filtered_symbols, symbol)
		end
	end

	return filtered_symbols, nil
end

-- List procedures with async support
function M.list_procedures_async(callback)
	M.get_symbols_by_type_async("procedure", function(procedures, err)
		if err then
			utils.notify(err or "Failed to get procedures", vim.log.levels.ERROR)
			if callback then
				callback(nil, err)
			end
			return
		end

		if #procedures == 0 then
			utils.notify("No procedures found in current file", vim.log.levels.INFO)
			if callback then
				callback({}, nil)
			end
			return
		end

		M.display_procedure_list(procedures)
		if callback then
			callback(procedures, nil)
		end
	end)
end

-- Synchronous wrapper
function M.list_procedures()
	M.list_procedures_async()
end

-- Display procedures in quickfix list
function M.display_procedure_list(procedures)
	local qflist = {}
	for _, proc in ipairs(procedures) do
		local display_name = proc.qualified_name or proc.name
		local args_info = proc.args and (" (" .. proc.args .. ")") or ""
		local context_info = ""

		if proc.namespace_context and proc.namespace_context ~= "" then
			context_info = " [ns:" .. proc.namespace_context .. "]"
		end

		table.insert(qflist, {
			bufnr = vim.api.nvim_get_current_buf(),
			lnum = proc.line,
			text = string.format("proc %s%s%s", display_name, args_info, context_info),
		})
	end

	utils.create_quickfix_list(qflist, "Found " .. #procedures .. " procedures")
end

-- List variables with async support
function M.list_variables_async(callback)
	local file_path, err = utils.get_current_file_path()
	if not file_path then
		if callback then
			callback(nil, err)
		end
		return
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	tcl.analyze_tcl_file_async(file_path, tclsh_cmd, function(symbols, analysis_err)
		if analysis_err then
			utils.notify(analysis_err or "Failed to get variables", vim.log.levels.ERROR)
			if callback then
				callback(nil, analysis_err)
			end
			return
		end

		-- Collect all variable types
		local variables = {}
		local variable_types = { "variable", "namespace_variable", "global", "array" }

		for _, symbol in ipairs(symbols or {}) do
			for _, var_type in ipairs(variable_types) do
				if symbol.type == var_type then
					table.insert(variables, symbol)
					break
				end
			end
		end

		if #variables == 0 then
			utils.notify("No variables found in current file", vim.log.levels.INFO)
			if callback then
				callback({}, nil)
			end
			return
		end

		M.display_variable_list(variables)
		if callback then
			callback(variables, nil)
		end
	end)
end

-- Synchronous wrapper
function M.list_variables()
	M.list_variables_async()
end

-- Display variables in quickfix list
function M.display_variable_list(variables)
	local qflist = {}
	for _, var in ipairs(variables) do
		local display_name = var.qualified_name or var.name
		local scope_info = var.scope and (" [" .. var.scope .. "]") or ""
		local context_info = ""

		if var.namespace_context and var.namespace_context ~= "" then
			context_info = " [ns:" .. var.namespace_context .. "]"
		end

		table.insert(qflist, {
			bufnr = vim.api.nvim_get_current_buf(),
			lnum = var.line,
			text = string.format("%s %s%s%s", var.type, display_name, scope_info, context_info),
		})
	end

	utils.create_quickfix_list(qflist, "Found " .. #variables .. " variables")
end

-- List namespaces with async support
function M.list_namespaces_async(callback)
	M.get_symbols_by_type_async("namespace", function(namespaces, err)
		if err then
			utils.notify(err or "Failed to get namespaces", vim.log.levels.ERROR)
			if callback then
				callback(nil, err)
			end
			return
		end

		if #namespaces == 0 then
			utils.notify("No namespaces found in current file", vim.log.levels.INFO)
			if callback then
				callback({}, nil)
			end
			return
		end

		M.display_namespace_list(namespaces)
		if callback then
			callback(namespaces, nil)
		end
	end)
end

-- Synchronous wrapper
function M.list_namespaces()
	M.list_namespaces_async()
end

-- Display namespaces in quickfix list
function M.display_namespace_list(namespaces)
	local qflist = {}
	for _, ns in ipairs(namespaces) do
		table.insert(qflist, {
			bufnr = vim.api.nvim_get_current_buf(),
			lnum = ns.line,
			text = string.format("namespace %s", ns.name),
		})
	end

	utils.create_quickfix_list(qflist, "Found " .. #namespaces .. " namespaces")
end

-- Get symbol under cursor with enhanced context (async version)
function M.get_symbol_under_cursor_async(callback)
	local word, err = utils.get_qualified_word_under_cursor()
	if not word then
		word, err = utils.get_word_under_cursor()
		if not word then
			if callback then
				callback(nil, err)
			end
			return
		end
	end

	local file_path, file_err = utils.get_current_file_path()
	if not file_path then
		if callback then
			callback(nil, file_err)
		end
		return
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	tcl.analyze_tcl_file_async(file_path, tclsh_cmd, function(symbols, analysis_err)
		if analysis_err then
			if callback then
				callback(nil, analysis_err)
			end
			return
		end

		if not symbols then
			if callback then
				callback(nil, "Failed to analyze file")
			end
			return
		end

		-- Find the symbol with context information
		for _, symbol in ipairs(symbols) do
			if
				utils.symbols_match(symbol.name, word)
				or (symbol.qualified_name and utils.symbols_match(symbol.qualified_name, word))
			then
				-- Add cursor context
				local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
				symbol.is_at_cursor = (symbol.line == cursor_line)
				symbol.file = file_path
				if callback then
					callback(symbol, nil)
				end
				return
			end
		end

		if callback then
			callback(nil, "Symbol '" .. word .. "' not found")
		end
	end)
end

-- Synchronous wrapper
function M.get_symbol_under_cursor()
	local word, err = utils.get_qualified_word_under_cursor()
	if not word then
		word, err = utils.get_word_under_cursor()
		if not word then
			return nil, err
		end
	end

	local file_path, file_err = utils.get_current_file_path()
	if not file_path then
		return nil, file_err
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

	if not symbols then
		return nil, "Failed to analyze file"
	end

	-- Find the symbol with context information
	for _, symbol in ipairs(symbols) do
		if
			utils.symbols_match(symbol.name, word)
			or (symbol.qualified_name and utils.symbols_match(symbol.qualified_name, word))
		then
			-- Add cursor context
			local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
			symbol.is_at_cursor = (symbol.line == cursor_line)
			symbol.file = file_path
			return symbol, nil
		end
	end

	return nil, "Symbol '" .. word .. "' not found"
end

-- Interactive symbol picker with async fuzzy search
function M.symbol_picker_async(callback)
	vim.ui.input({ prompt = "Search symbols: " }, function(query)
		if not query or query == "" then
			if callback then
				callback(nil, "No query provided")
			end
			return
		end

		M.search_workspace_symbols_async(query, callback)
	end)
end

-- Synchronous wrapper
function M.symbol_picker()
	M.symbol_picker_async()
end

-- Progress-aware workspace indexing
function M.build_workspace_index_async(callback)
	local files = vim.fn.glob("**/*.tcl", false, true)
	local tclsh_cmd = config.get_tclsh_cmd()

	if #files == 0 then
		utils.notify("No TCL files found in workspace", vim.log.levels.WARN)
		if callback then
			callback({}, nil)
		end
		return
	end

	utils.notify(string.format("Building workspace index for %d files...", #files), vim.log.levels.INFO)

	local index = {
		files = {},
		symbols = {},
		by_type = {
			procedure = {},
			variable = {},
			namespace = {},
			global = {},
			package = {},
			source = {},
		},
		by_name = {},
		total_symbols = 0,
		last_updated = os.time(),
	}

	tcl.batch_analyze_files_async(files, tclsh_cmd, function(file_results, err)
		if err then
			utils.notify("Workspace indexing failed: " .. err, vim.log.levels.ERROR)
			if callback then
				callback(nil, err)
			end
			return
		end

		for file_path, symbols in pairs(file_results) do
			if symbols then
				index.files[file_path] = {
					path = file_path,
					symbols = symbols,
					symbol_count = #symbols,
					last_modified = vim.fn.getftime(file_path),
				}

				for _, symbol in ipairs(symbols) do
					-- Add file reference to symbol
					symbol.file = file_path

					-- Add to main symbols list
					table.insert(index.symbols, symbol)

					-- Add to type-based index
					if index.by_type[symbol.type] then
						table.insert(index.by_type[symbol.type], symbol)
					end

					-- Add to name-based index
					if not index.by_name[symbol.name] then
						index.by_name[symbol.name] = {}
					end
					table.insert(index.by_name[symbol.name], symbol)

					index.total_symbols = index.total_symbols + 1
				end
			end
		end

		utils.notify(
			string.format(
				"Workspace index built: %d symbols in %d files",
				index.total_symbols,
				vim.tbl_count(index.files)
			),
			vim.log.levels.INFO
		)

		if callback then
			callback(index, nil)
		end
	end)
end

-- Set up symbols-related keymaps
function M.setup_buffer_keymaps(bufnr)
	local keymaps = config.get_keymaps()
	local opts = { buffer = bufnr, silent = true }

	if keymaps.document_symbols then
		utils.set_buffer_keymap(
			"n",
			keymaps.document_symbols,
			M.document_symbols,
			vim.tbl_extend("force", opts, { desc = "TCL Document Symbols" }),
			bufnr
		)
	end

	if keymaps.workspace_symbols then
		utils.set_buffer_keymap(
			"n",
			keymaps.workspace_symbols,
			M.workspace_symbols,
			vim.tbl_extend("force", opts, { desc = "TCL Workspace Symbols" }),
			bufnr
		)
	end

	-- Additional symbol navigation keymaps
	utils.set_buffer_keymap(
		"n",
		"<leader>tp",
		M.list_procedures,
		vim.tbl_extend("force", opts, { desc = "List Procedures" }),
		bufnr
	)
	utils.set_buffer_keymap(
		"n",
		"<leader>tv",
		M.list_variables,
		vim.tbl_extend("force", opts, { desc = "List Variables" }),
		bufnr
	)
	utils.set_buffer_keymap(
		"n",
		"<leader>tn",
		M.list_namespaces,
		vim.tbl_extend("force", opts, { desc = "List Namespaces" }),
		bufnr
	)
	utils.set_buffer_keymap(
		"n",
		"<leader>tf",
		M.symbol_picker,
		vim.tbl_extend("force", opts, { desc = "Symbol Fuzzy Finder" }),
		bufnr
	)
end

return M
