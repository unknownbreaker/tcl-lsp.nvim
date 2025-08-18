local utils = require("tcl-lsp.utils")
local config = require("tcl-lsp.config")
local tcl = require("tcl-lsp.tcl")
local M = {}

-- Enhanced document symbols using TCL analysis
function M.document_symbols()
	local file_path, err = utils.get_current_file_path()
	if not file_path then
		utils.notify(err, vim.log.levels.WARN)
		return
	end

	local tclsh_cmd = config.get_tclsh_cmd()

	tcl.analyze_tcl_file_async(file_path, tclsh_cmd, function(symbols)
		if not symbols or #symbols == 0 then
			utils.notify("No symbols found in current file", vim.log.levels.WARN)
			return
		end

		-- Group symbols by type
		local grouped = {}
		for _, symbol in ipairs(symbols) do
			if not grouped[symbol.type] then
				grouped[symbol.type] = {}
			end
			table.insert(grouped[symbol.type], symbol)
		end

		-- Create quickfix list with grouped symbols
		local qflist = {}
		local type_order = { "procedure", "variable", "global", "namespace", "package", "source" }

		for _, type_name in ipairs(type_order) do
			local type_symbols = grouped[type_name]
			if type_symbols then
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
					table.insert(qflist, {
						bufnr = vim.api.nvim_get_current_buf(),
						lnum = symbol.line,
						text = string.format("  %s: %s", symbol.name, utils.trim(symbol.text)),
					})
				end
			end
		end

		utils.create_quickfix_list(
			qflist,
			string.format("Found %d symbols in %d categories", #symbols, vim.tbl_count(grouped))
		)
	end)
end

-- Enhanced workspace symbols using TCL analysis
function M.workspace_symbols(query)
	if not query then
		vim.ui.input({ prompt = "Symbol name: " }, function(input)
			if input and input ~= "" then
				M.search_workspace_symbols(input)
			end
		end)
	else
		M.search_workspace_symbols(query)
	end
end

-- Search for symbols across workspace
function M.search_workspace_symbols(query)
	local tclsh_cmd = config.get_tclsh_cmd()

	-- Search in all .tcl files in current directory and subdirectories
	local files = vim.fn.glob("**/*.tcl", false, true)
	local matches = {}

	for _, file in ipairs(files) do
		local symbols = tcl.analyze_tcl_file(file, tclsh_cmd)
		if symbols then
			for _, symbol in ipairs(symbols) do
				if utils.symbols_match(symbol.name, query) then
					table.insert(matches, {
						file = file,
						symbol = symbol,
					})
				end
			end
		end
	end

	if #matches > 0 then
		local qflist = {}

		-- Sort matches: exact matches first, then qualified matches, then local matches
		table.sort(matches, function(a, b)
			local a_exact = (a.symbol.name == query)
			local b_exact = (b.symbol.name == query)

			if a_exact and not b_exact then
				return true
			end
			if not a_exact and b_exact then
				return false
			end

			-- Both exact or both partial, sort by type priority
			local type_priority = {
				procedure = 1,
				namespace = 2,
				variable = 3,
				global = 4,
				package = 5,
				package_provide = 6,
				source = 7,
			}

			local a_priority = type_priority[a.symbol.type] or 99
			local b_priority = type_priority[b.symbol.type] or 99

			if a_priority ~= b_priority then
				return a_priority < b_priority
			end

			-- Same type, sort by file name
			return a.file < b.file
		end)

		for _, match in ipairs(matches) do
			local symbol_desc = match.symbol.name
			if match.symbol.name ~= query then
				symbol_desc = symbol_desc .. " (matches " .. query .. ")"
			end

			table.insert(qflist, {
				filename = match.file,
				lnum = match.symbol.line,
				text = string.format("[%s] %s: %s", match.symbol.type, symbol_desc, utils.trim(match.symbol.text)),
			})
		end

		utils.create_quickfix_list(qflist, "Found " .. #matches .. " matches for '" .. query .. "'")
	else
		utils.notify("No matches found for '" .. query .. "'", vim.log.levels.WARN)
	end
end

-- Get all symbols from a file
function M.get_file_symbols(file_path, tclsh_cmd)
	if not utils.file_exists(file_path) then
		return nil, "File does not exist"
	end

	local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
	if not symbols then
		return nil, "Failed to analyze file"
	end

	return symbols, nil
end

-- Get symbols by type from current file
function M.get_symbols_by_type(symbol_type)
	local file_path, err = utils.get_current_file_path()
	if not file_path then
		return nil, err
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	local symbols, symbol_err = M.get_file_symbols(file_path, tclsh_cmd)

	if not symbols then
		return nil, symbol_err
	end

	local filtered_symbols = {}
	for _, symbol in ipairs(symbols) do
		if symbol.type == symbol_type then
			table.insert(filtered_symbols, symbol)
		end
	end

	return filtered_symbols, nil
end

-- List all procedures in current file
function M.list_procedures()
	local procedures, err = M.get_symbols_by_type("procedure")
	if not procedures then
		utils.notify(err or "Failed to get procedures", vim.log.levels.ERROR)
		return
	end

	if #procedures == 0 then
		utils.notify("No procedures found in current file", vim.log.levels.INFO)
		return
	end

	local qflist = {}
	for _, proc in ipairs(procedures) do
		table.insert(qflist, {
			bufnr = vim.api.nvim_get_current_buf(),
			lnum = proc.line,
			text = string.format("proc %s: %s", proc.name, utils.trim(proc.text)),
		})
	end

	utils.create_quickfix_list(qflist, "Found " .. #procedures .. " procedures")
end

-- List all variables in current file
function M.list_variables()
	local variables, err = M.get_symbols_by_type("variable")
	if not variables then
		utils.notify(err or "Failed to get variables", vim.log.levels.ERROR)
		return
	end

	if #variables == 0 then
		utils.notify("No variables found in current file", vim.log.levels.INFO)
		return
	end

	local qflist = {}
	for _, var in ipairs(variables) do
		table.insert(qflist, {
			bufnr = vim.api.nvim_get_current_buf(),
			lnum = var.line,
			text = string.format("var %s: %s", var.name, utils.trim(var.text)),
		})
	end

	utils.create_quickfix_list(qflist, "Found " .. #variables .. " variables")
end

-- List all namespaces in current file
function M.list_namespaces()
	local namespaces, err = M.get_symbols_by_type("namespace")
	if not namespaces then
		utils.notify(err or "Failed to get namespaces", vim.log.levels.ERROR)
		return
	end

	if #namespaces == 0 then
		utils.notify("No namespaces found in current file", vim.log.levels.INFO)
		return
	end

	local qflist = {}
	for _, ns in ipairs(namespaces) do
		table.insert(qflist, {
			bufnr = vim.api.nvim_get_current_buf(),
			lnum = ns.line,
			text = string.format("namespace %s: %s", ns.name, utils.trim(ns.text)),
		})
	end

	utils.create_quickfix_list(qflist, "Found " .. #namespaces .. " namespaces")
end

-- Get symbol under cursor with full context
function M.get_symbol_under_cursor()
	local word, err = utils.get_word_under_cursor()
	if not word then
		return nil, err
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

	-- Find the symbol
	for _, symbol in ipairs(symbols) do
		if symbol.name == word then
			-- Add additional context
			local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
			symbol.is_at_cursor = (symbol.line == cursor_line)
			symbol.file = file_path
			return symbol, nil
		end
	end

	return nil, "Symbol not found"
end

-- Build symbol index for workspace
function M.build_workspace_index()
	local tclsh_cmd = config.get_tclsh_cmd()
	local files = vim.fn.glob("**/*.tcl", false, true)
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

	for _, file in ipairs(files) do
		local symbols = tcl.analyze_tcl_file(file, tclsh_cmd)
		if symbols then
			index.files[file] = {
				path = file,
				symbols = symbols,
				symbol_count = #symbols,
				last_modified = vim.fn.getftime(file),
			}

			for _, symbol in ipairs(symbols) do
				-- Add file reference to symbol
				symbol.file = file

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

	return index
end

-- Search symbols with fuzzy matching
function M.fuzzy_symbol_search(query)
	if not query or query == "" then
		return {}
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	local files = vim.fn.glob("**/*.tcl", false, true)
	local matches = {}

	-- Convert query to lowercase for case-insensitive matching
	local query_lower = query:lower()

	for _, file in ipairs(files) do
		local symbols = tcl.analyze_tcl_file(file, tclsh_cmd)
		if symbols then
			for _, symbol in ipairs(symbols) do
				local symbol_lower = symbol.name:lower()

				-- Exact match gets highest score
				if symbol_lower == query_lower then
					table.insert(matches, { symbol = symbol, file = file, score = 100 })
				-- Starts with query gets high score
				elseif symbol_lower:sub(1, #query_lower) == query_lower then
					table.insert(matches, { symbol = symbol, file = file, score = 80 })
				-- Contains query gets medium score
				elseif symbol_lower:find(query_lower, 1, true) then
					table.insert(matches, { symbol = symbol, file = file, score = 60 })
				-- Fuzzy match gets low score
				else
					local score = M.calculate_fuzzy_score(symbol_lower, query_lower)
					if score > 30 then
						table.insert(matches, { symbol = symbol, file = file, score = score })
					end
				end
			end
		end
	end

	-- Sort by score (highest first)
	table.sort(matches, function(a, b)
		return a.score > b.score
	end)

	return matches
end

-- Calculate fuzzy matching score
function M.calculate_fuzzy_score(text, query)
	if #query == 0 then
		return 0
	end
	if #text == 0 then
		return 0
	end

	local score = 0
	local query_idx = 1
	local consecutive = 0

	for i = 1, #text do
		if query_idx <= #query and text:sub(i, i) == query:sub(query_idx, query_idx) then
			score = score + 1 + consecutive
			consecutive = consecutive + 1
			query_idx = query_idx + 1

			if query_idx > #query then
				-- All characters matched
				score = score + (#query * 2) -- Bonus for complete match
				break
			end
		else
			consecutive = 0
		end
	end

	-- Normalize score based on query length and text length
	if query_idx > #query then
		score = (score / #text) * 100
	else
		score = 0 -- Incomplete match
	end

	return math.floor(score)
end

-- Interactive symbol picker
function M.symbol_picker()
	vim.ui.input({ prompt = "Search symbols: " }, function(query)
		if not query or query == "" then
			return
		end

		local matches = M.fuzzy_symbol_search(query)

		if #matches == 0 then
			utils.notify("No symbols found matching '" .. query .. "'", vim.log.levels.WARN)
			return
		end

		-- Show top matches in quickfix
		local qflist = {}
		local max_results = math.min(#matches, 20) -- Limit results

		for i = 1, max_results do
			local match = matches[i]
			table.insert(qflist, {
				filename = match.file,
				lnum = match.symbol.line,
				text = string.format(
					"[%s] %s (score: %d): %s",
					match.symbol.type,
					match.symbol.name,
					match.score,
					utils.trim(match.symbol.text)
				),
			})
		end

		utils.create_quickfix_list(
			qflist,
			string.format("Found %d matches for '%s' (showing top %d)", #matches, query, max_results)
		)
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
