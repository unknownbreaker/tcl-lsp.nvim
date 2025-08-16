local utils = require("tcl-lsp.utils")
local config = require("tcl-lsp.config")
local tcl = require("tcl-lsp.tcl")
local M = {}

local function calculate_symbol_score(symbol, query, cursor_line, current_context)
	local score = 0

	-- Base score for name matching
	if symbol.name == query then
		score = 100 -- Exact match
	elseif utils.symbols_match(symbol.name, query) then
		score = 50 -- Partial/qualified match
	else
		return 0 -- No match
	end

	-- CRITICAL FIX: Procedure scope bonus/penalty
	if current_context and current_context.procedure then
		if symbol.proc_context == current_context.procedure then
			-- Same procedure - huge bonus for local scope
			score = score + 100
		elseif symbol.proc_context and symbol.proc_context ~= current_context.procedure then
			-- Different procedure - penalty
			score = score - 30
		end
		-- Note: symbols with no proc_context (global scope) get no bonus/penalty
	end

	-- Proximity bonus (closer to cursor gets higher score)
	local distance = math.abs(symbol.line - cursor_line)
	if distance <= 5 then
		score = score + 20
	elseif distance <= 20 then
		score = score + 10
	elseif distance <= 50 then
		score = score + 5
	end

	-- Scope-based bonuses
	if symbol.scope == "local" then
		score = score + 30
	elseif symbol.scope == "namespace" then
		score = score + 20
	elseif symbol.scope == "global" then
		score = score + 10
	end

	-- Namespace context bonus
	if current_context and current_context.namespace then
		if symbol.namespace_context == current_context.namespace then
			score = score + 25
		end
	end

	-- Symbol type priority
	local type_priority = {
		procedure = 5,
		variable = 10,
		array = 8,
		global = 6,
		namespace = 3,
		package = 1,
	}
	score = score + (type_priority[symbol.type] or 0)

	return score
end

-- Smart and reliable go-to-definition with scope awareness
function M.goto_definition()
	-- Get word under cursor
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

	print("DEBUG: Looking for symbol:", word, "in file:", file_path)

	-- Get symbols from current file
	local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
	if not symbols then
		utils.notify("Failed to analyze file with TCL", vim.log.levels.ERROR)
		return
	end

	print("DEBUG: Found", #symbols, "symbols total")

	if #symbols == 0 then
		utils.notify("No symbols found in file. Run :TclTestSimple to troubleshoot.", vim.log.levels.WARN)
		return
	end

	-- Get current context for smart scope resolution
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local current_context = M.get_current_context(cursor_line, symbols)

	print("DEBUG: Current context:", vim.inspect(current_context))

	-- Find matching symbols with scope-aware scoring
	local matches = {}
	for _, symbol in ipairs(symbols) do
		local match_score = 0
		local match_type = "none"

		-- Basic name matching
		if symbol.name == word then
			match_score = 100
			match_type = "exact"
		elseif symbol.qualified_name == word then
			match_score = 95
			match_type = "qualified_exact"
		elseif utils.symbols_match(symbol.name, word) then
			match_score = 80
			match_type = "fuzzy"
		elseif symbol.name:match("::" .. word .. "$") then
			match_score = 75
			match_type = "unqualified"
		end

		if match_score > 0 then
			-- Apply scope-aware bonus scoring
			match_score = M.apply_scope_bonus(symbol, word, current_context, match_score)

			table.insert(matches, {
				symbol = symbol,
				score = match_score,
				match_type = match_type,
			})
			print("DEBUG: Found match:", symbol.type, symbol.name, "scope:", symbol.scope, "final score:", match_score)
		end
	end

	-- Sort by score (highest first)
	table.sort(matches, function(a, b)
		return a.score > b.score
	end)

	print("DEBUG: Total matches found:", #matches)

	-- Handle results with smarter logic
	if #matches == 0 then
		-- Try workspace search as fallback
		utils.notify("Symbol '" .. word .. "' not found in current file, searching workspace...", vim.log.levels.INFO)
		M.search_workspace_for_definition(word, file_path, tclsh_cmd)
	elseif #matches == 1 then
		-- Single match - jump to it
		local match = matches[1]
		vim.api.nvim_win_set_cursor(0, { match.symbol.line, 0 })
		utils.notify(
			string.format("Found %s '%s' at line %d", match.symbol.type, match.symbol.name, match.symbol.line),
			vim.log.levels.INFO
		)
	else
		-- Multiple matches - check if there's a clear winner
		local best_score = matches[1].score
		local second_best_score = matches[2] and matches[2].score or 0

		-- If the best match is significantly better than the second best, auto-jump
		if best_score > second_best_score + 50 then
			local match = matches[1]
			vim.api.nvim_win_set_cursor(0, { match.symbol.line, 0 })
			utils.notify(
				string.format(
					"Found %s '%s' at line %d (scope: %s)",
					match.symbol.type,
					match.symbol.name,
					match.symbol.line,
					match.symbol.scope
				),
				vim.log.levels.INFO
			)
		else
			-- Show choices for ambiguous matches
			M.show_symbol_choices(matches, word)
		end
	end
end

function M.find_matching_symbols(symbols, resolutions, query)
	local matches = {}
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

	-- Get current context (procedure and namespace we're in)
	local current_context = M.get_current_context(cursor_line, symbols)

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
				-- Use the enhanced scoring function
				local calculated_score = calculate_symbol_score(symbol, query, cursor_line, current_context)

				table.insert(matches, {
					symbol = symbol,
					resolution = resolution,
					priority = calculated_score, -- Use calculated score instead of resolution.priority
				})
			end
		end
	end

	-- Remove duplicates and sort by calculated priority
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

-- Determine current context (what procedure/namespace we're in)
function M.get_current_context(cursor_line, symbols)
	local context = {
		procedure = nil,
		namespace = nil,
		procedure_line = 0,
		namespace_line = 0,
	}

	-- Find the most recent procedure and namespace before cursor
	for _, symbol in ipairs(symbols) do
		if symbol.line <= cursor_line then
			if symbol.type == "procedure" and symbol.line > context.procedure_line then
				context.procedure = symbol.name
				context.procedure_line = symbol.line
			elseif symbol.type == "namespace" and symbol.line > context.namespace_line then
				context.namespace = symbol.name
				context.namespace_line = symbol.line
			end
		end
	end

	return context
end

-- Apply scope-aware bonus scoring
function M.apply_scope_bonus(symbol, target_word, current_context, base_score)
	local bonus = 0

	-- Strong preference for local scope when inside a procedure
	if current_context.procedure ~= "" then
		if symbol.scope == "local" then
			-- Local variables/parameters get highest priority
			if symbol.type == "parameter" then
				bonus = bonus + 200 -- Parameters are most likely
			elseif symbol.type == "local_var" then
				bonus = bonus + 150 -- Local variables are very likely
			elseif symbol.type == "variable" and symbol.scope == "local" then
				bonus = bonus + 100 -- Local scope variables
			end

			-- Bonus if it's in the same procedure context
			if symbol.proc_context == current_context.procedure then
				bonus = bonus + 100
			end
		else
			-- Penalty for non-local symbols when inside a procedure
			bonus = bonus - 50
		end
	end

	-- Namespace context bonuses
	if current_context.namespace ~= "" then
		if symbol.context == current_context.namespace then
			bonus = bonus + 30
		end
	end

	-- Proximity bonus - closer symbols are more likely
	if current_context.procedure_line > 0 then
		local distance = math.abs(symbol.line - current_context.procedure_line)
		if distance < 10 then
			bonus = bonus + (10 - distance) * 5 -- Closer = higher bonus
		end
	end

	-- Symbol type preferences
	if symbol.type == "parameter" then
		bonus = bonus + 50 -- Parameters are often what we're looking for
	elseif symbol.type == "procedure" then
		bonus = bonus + 20 -- Procedures are common targets
	end

	return base_score + bonus
end

-- Simple workspace search
function M.search_workspace_for_definition(symbol_name, current_file, tclsh_cmd)
	local files = vim.fn.glob("**/*.tcl", false, true)
	local matches = {}

	print("DEBUG: Searching", #files, "files for", symbol_name)

	for _, file in ipairs(files) do
		if file ~= current_file then -- Skip current file
			local file_symbols = tcl.analyze_tcl_file(file, tclsh_cmd)
			if file_symbols then
				for _, symbol in ipairs(file_symbols) do
					if symbol.name == symbol_name or utils.symbols_match(symbol.name, symbol_name) then
						table.insert(matches, {
							symbol = symbol,
							file = file,
							score = (symbol.name == symbol_name) and 10 or 5,
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
				vim.fn.fnamemodify(match.file, ":t"),
				match.symbol.line
			),
			vim.log.levels.INFO
		)
	else
		M.show_workspace_choices(matches, symbol_name)
	end
end

function M.show_prioritized_symbol_choices(matches, query, context)
	local choices = {}

	for i, match in ipairs(matches) do
		local symbol = match.symbol
		local context_info = ""

		if symbol.proc_context and symbol.proc_context ~= "" then
			context_info = " [proc: " .. symbol.proc_context .. "]"
		elseif symbol.namespace_context and symbol.namespace_context ~= "" then
			context_info = " [ns: " .. symbol.namespace_context .. "]"
		elseif symbol.scope and symbol.scope ~= "" then
			context_info = " [" .. symbol.scope .. "]"
		end

		table.insert(
			choices,
			string.format(
				"%d. %s '%s'%s at line %d (score: %d)",
				i,
				symbol.type,
				symbol.name,
				context_info,
				symbol.line,
				match.priority -- This will now show the calculated score
			)
		)
	end

	local context_str = ""
	if context and context.namespace then
		context_str = context_str .. "namespace: " .. context.namespace
	end
	if context and context.procedure then
		if context_str ~= "" then
			context_str = context_str .. ", "
		end
		context_str = context_str .. "procedure: " .. context.procedure
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
					"Jumped to %s '%s' at line %d (score: %d)",
					selected_match.symbol.type,
					selected_match.symbol.name,
					selected_match.symbol.line,
					selected_match.priority
				),
				vim.log.levels.INFO
			)
		end
	end)
end

-- Show multiple symbol choices
function M.show_symbol_choices(matches, query)
	-- Sort by score (highest first)
	table.sort(matches, function(a, b)
		return a.score > b.score
	end)

	local choices = {}
	for i, match in ipairs(matches) do
		local symbol = match.symbol
		local context_info = ""

		if symbol.context and symbol.context ~= "" then
			context_info = " [" .. symbol.context .. "]"
		elseif symbol.scope and symbol.scope ~= "" then
			context_info = " [" .. symbol.scope .. "]"
		end

		table.insert(
			choices,
			string.format(
				"%d. %s '%s'%s at line %d (%s match)",
				i,
				symbol.type,
				symbol.name,
				context_info,
				symbol.line,
				match.match_type
			)
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

-- Show workspace choices
function M.show_workspace_choices(matches, query)
	-- Sort by score first, then by file
	table.sort(matches, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
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

-- Simple hover functionality
function M.hover()
	local word, err = utils.get_qualified_word_under_cursor()
	if not word then
		word, err = utils.get_word_under_cursor()
		if not word then
			return
		end
	end

	local tclsh_cmd = config.get_tclsh_cmd()

	-- Check if it's a built-in TCL command
	local builtin_info = tcl.check_builtin_command(word, tclsh_cmd)
	if builtin_info then
		utils.notify(builtin_info.description, vim.log.levels.INFO)
		return
	end

	-- Check static documentation
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

-- Simple find references
function M.find_references()
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

-- Workspace references
function M.find_workspace_references()
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

-- Navigation keymaps
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
