local utils = require("tcl-lsp.utils")
local config = require("tcl-lsp.config")
local tcl = require("tcl-lsp.tcl")
local semantic = require("tcl-lsp.semantic")
local M = {}

-- Enhanced file discovery that actually uses your semantic analysis
local function get_comprehensive_file_list(current_file, tclsh_cmd)
	local files = {}
	local files_set = {}

	-- 1. First priority: Source dependencies (use your existing semantic analysis!)
	if semantic and semantic.build_source_dependencies then
		local dependencies = semantic.build_source_dependencies(current_file, tclsh_cmd)
		for _, file in ipairs(dependencies) do
			if file ~= current_file and utils.file_exists(file) then
				if not files_set[file] then
					table.insert(files, file)
					files_set[file] = true
				end
			end
		end
		print("DEBUG: Found", #dependencies, "source dependencies")
	end

	-- 2. Current directory TCL files with multiple extensions
	local extensions = { "*.tcl", "*.tk", "*.itcl", "*.itk", "*.rvt" }
	for _, ext in ipairs(extensions) do
		local current_dir_files = vim.fn.glob(ext, false, true)
		for _, file in ipairs(current_dir_files) do
			if file ~= current_file and utils.file_exists(file) then
				if not files_set[file] then
					table.insert(files, file)
					files_set[file] = true
				end
			end
		end
	end

	-- 3. Subdirectory search
	for _, ext in ipairs(extensions) do
		local subdir_files = vim.fn.glob("**/" .. ext, false, true)
		for _, file in ipairs(subdir_files) do
			if file ~= current_file and utils.file_exists(file) then
				if not files_set[file] then
					table.insert(files, file)
					files_set[file] = true
				end
			end
		end
	end

	-- 4. Common TCL directories relative to current file
	local current_dir = vim.fn.fnamemodify(current_file, ":h")
	local common_dirs = {
		"lib",
		"src",
		"tcl",
		"scripts",
		"modules",
		"../lib",
		"../src",
		"../tcl",
		"../scripts",
		"../../lib",
		"../../src",
		"../../tcl",
	}

	for _, dir in ipairs(common_dirs) do
		local search_dir = vim.fn.resolve(current_dir .. "/" .. dir)
		if vim.fn.isdirectory(search_dir) == 1 then
			for _, ext in ipairs(extensions) do
				local pattern = search_dir .. "/" .. ext
				local dir_files = vim.fn.glob(pattern, false, true)
				for _, file in ipairs(dir_files) do
					if file ~= current_file and utils.file_exists(file) then
						if not files_set[file] then
							table.insert(files, file)
							files_set[file] = true
						end
					end
				end
			end
		end
	end

	print("DEBUG: Total files to search:", #files)
	for i, file in ipairs(files) do
		print("DEBUG:", i, "->", vim.fn.fnamemodify(file, ":."))
	end

	return files
end

-- Fixed workspace search that actually works
function M.search_workspace_for_definition_comprehensive(symbol_name, current_file, tclsh_cmd)
	print("DEBUG: Searching for", symbol_name, "across workspace")

	local files = get_comprehensive_file_list(current_file, tclsh_cmd)
	local matches = {}

	for _, file in ipairs(files) do
		print("DEBUG: Analyzing file:", vim.fn.fnamemodify(file, ":."))
		local file_symbols = tcl.analyze_tcl_file(file, tclsh_cmd)

		if file_symbols then
			print("DEBUG: Found", #file_symbols, "symbols in", vim.fn.fnamemodify(file, ":t"))
			for _, symbol in ipairs(file_symbols) do
				-- Debug each symbol
				print("DEBUG: Symbol:", symbol.name, "type:", symbol.type, "line:", symbol.line)

				if symbol.name == symbol_name or utils.symbols_match(symbol.name, symbol_name) then
					print("DEBUG: MATCH FOUND:", symbol.name, "in", vim.fn.fnamemodify(file, ":t"))
					table.insert(matches, {
						symbol = symbol,
						file = file,
						priority = (symbol.name == symbol_name) and 10 or 5,
					})
				end
			end
		else
			print("DEBUG: No symbols found in", vim.fn.fnamemodify(file, ":t"))
		end
	end

	print("DEBUG: Total matches found:", #matches)

	if #matches == 0 then
		utils.notify("Definition of '" .. symbol_name .. "' not found in " .. #files .. " files", vim.log.levels.WARN)
	elseif #matches == 1 then
		local match = matches[1]
		vim.cmd("edit " .. match.file)
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
		M.show_simple_workspace_choices(matches, symbol_name)
	end
end

-- Smart TCL go-to-definition using semantic resolution
function M.goto_definition()
	print("DEBUG: goto_definition called")

	-- Try to get qualified word first, fall back to regular word
	local word, err = utils.get_qualified_word_under_cursor()
	if not word then
		word, err = utils.get_word_under_cursor()
		if not word then
			utils.notify(err, vim.log.levels.WARN)
			return
		end
	end

	print("DEBUG: Looking for symbol:", word)

	local file_path, file_err = utils.get_current_file_path()
	if not file_path then
		utils.notify(file_err, vim.log.levels.WARN)
		return
	end

	print("DEBUG: Current file:", file_path)

	local tclsh_cmd = config.get_tclsh_cmd()

	-- Get all symbols from current file first
	local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
	if not symbols then
		utils.notify("Failed to analyze file with TCL", vim.log.levels.ERROR)
		return
	end

	print("DEBUG: Found", #symbols, "symbols in current file")

	-- Quick check: if no symbols found, there might be a parsing issue
	if #symbols == 0 then
		utils.notify("No symbols found in file. Try :TclLspDebug to troubleshoot.", vim.log.levels.WARN)
		return
	end

	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

	-- Try smart resolution first
	local resolution = tcl.resolve_symbol(word, file_path, cursor_line, tclsh_cmd)
	local matches = {}

	if resolution and resolution.resolutions then
		print("DEBUG: Using smart resolution with", #resolution.resolutions, "candidates")
		-- Use smart resolution
		matches = M.find_matching_symbols(symbols, resolution.resolutions, word)
	end

	-- Fallback to simple matching if smart resolution fails or finds nothing
	if #matches == 0 then
		print("DEBUG: Smart resolution failed, trying simple matching")
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

	print("DEBUG: Found", #matches, "matches in current file")

	if #matches == 0 then
		-- Try workspace search if nothing found locally
		utils.notify("Symbol '" .. word .. "' not found in current file, searching workspace...", vim.log.levels.INFO)
		M.search_workspace_for_definition_comprehensive(word, file_path, tclsh_cmd)
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

-- Debug command to test file discovery
function M.debug_file_discovery()
	local file_path, err = utils.get_current_file_path()
	if not file_path then
		utils.notify("No current file: " .. (err or "unknown"), vim.log.levels.ERROR)
		return
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	local files = get_comprehensive_file_list(file_path, tclsh_cmd)

	utils.notify("Found " .. #files .. " files to search:", vim.log.levels.INFO)
	for i, file in ipairs(files) do
		local relative_path = vim.fn.fnamemodify(file, ":.")
		utils.notify(string.format("  %d. %s", i, relative_path), vim.log.levels.INFO)
	end
end

-- Keep all your existing functions but replace the problematic ones
function M.search_workspace_for_definition_simple(symbol_name, current_file, tclsh_cmd)
	-- Use the comprehensive search instead
	M.search_workspace_for_definition_comprehensive(symbol_name, current_file, tclsh_cmd)
end

-- Rest of your existing functions remain the same...
function M.show_simple_symbol_choices(matches, query)
	local choices = {}

	-- Sort by priority first
	table.sort(matches, function(a, b)
		return a.priority > b.priority
	end)

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
			string.format("%d. %s '%s'%s at line %d", i, symbol.type, symbol.name, context_info, symbol.line)
		)
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

function M.show_simple_workspace_choices(matches, query)
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
		table.insert(
			choices,
			string.format(
				"%d. %s '%s' in %s at line %d",
				i,
				match.symbol.type,
				match.symbol.name,
				file_short,
				match.symbol.line
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

function M.symbol_matches_query(symbol_name, query)
	return utils.symbols_match(symbol_name, query)
end

-- Keep all your other existing functions (hover, find_references, etc.)
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

	-- Debug keymap
	utils.set_buffer_keymap(
		"n",
		"<leader>td",
		M.debug_file_discovery,
		vim.tbl_extend("force", opts, { desc = "Debug File Discovery" }),
		bufnr
	)
end

return M
