-- LSP handlers and buffer setup for tcl-lsp.nvim

local M = {}

-- TCL command documentation
local tcl_docs = {
	set = "**set** - Set the value of a variable\n\nSyntax: `set varName ?value?`\n\nIf value is specified, set the variable to that value. If value is omitted, return the current value.",
	puts = "**puts** - Write text to output\n\nSyntax: `puts ?-nonewline? ?channelId? string`\n\nWrite string to the specified channel (stdout by default).",
	["if"] = "**if** - Conditional execution\n\nSyntax: `if expr1 ?then? body1 elseif expr2 ?then? body2 ... ?else? ?bodyN?`\n\nExecute body1 if expr1 is true, otherwise check elseif conditions.",
	["for"] = "**for** - Loop construct\n\nSyntax: `for start test next body`\n\nExecute start, then repeatedly test condition, execute body, and run next until test is false.",
	["while"] = "**while** - While loop\n\nSyntax: `while test body`\n\nRepeatedly execute body while test evaluates to true.",
	proc = "**proc** - Define a procedure\n\nSyntax: `proc name args body`\n\nDefine a new procedure with given name, argument list, and body.",
	["return"] = "**return** - Return from procedure\n\nSyntax: `return ?-code code? ?-errorinfo info? ?-errorcode code? ?value?`\n\nReturn from current procedure with optional value.",
	source = "**source** - Evaluate a script file\n\nSyntax: `source fileName`\n\nRead and evaluate the contents of fileName as a Tcl script.",
	package = "**package** - Package management\n\nSyntax: `package option ?arg ...?`\n\nManage Tcl packages. Common options: require, provide, names, versions.",
	namespace = "**namespace** - Namespace operations\n\nSyntax: `namespace option ?arg ...?`\n\nManage namespaces. Options include: eval, current, children, parent, etc.",
	list = "**list** - Create and manipulate lists\n\nSyntax: `list ?value value ...?`\n\nCreate a properly formatted list from the given arguments.",
	dict = "**dict** - Dictionary operations\n\nSyntax: `dict option ?arg ...?`\n\nManipulate dictionary values. Options: create, get, set, keys, values, etc.",
	string = "**string** - String manipulation\n\nSyntax: `string option arg ?arg ...?`\n\nString operations: length, index, range, match, map, etc.",
	file = "**file** - File system operations\n\nSyntax: `file option name ?arg ...?`\n\nFile operations: exists, readable, writable, size, dirname, etc.",
	glob = "**glob** - Pattern matching for filenames\n\nSyntax: `glob ?switches? pattern ?pattern ...?`\n\nReturn list of filenames matching given patterns.",
	regexp = "**regexp** - Regular expression matching\n\nSyntax: `regexp ?switches? exp string ?matchVar? ?subMatchVar ...?`\n\nMatch regular expression against string.",
	regsub = "**regsub** - Regular expression substitution\n\nSyntax: `regsub ?switches? exp string subSpec ?varName?`\n\nPerform regular expression substitution.",
	switch = "**switch** - Multi-way branch\n\nSyntax: `switch ?options? string pattern body ?pattern body ...?`\n\nExecute body for first matching pattern.",
	catch = "**catch** - Exception handling\n\nSyntax: `catch script ?varName?`\n\nExecute script and catch any errors.",
	error = "**error** - Generate an error\n\nSyntax: `error message ?info? ?code?`\n\nGenerate an error with given message.",
	eval = "**eval** - Evaluate a string as script\n\nSyntax: `eval arg ?arg ...?`\n\nConcatenate arguments and evaluate as Tcl script.",
	expr = "**expr** - Evaluate mathematical expressions\n\nSyntax: `expr arg ?arg ...?`\n\nEvaluate mathematical expression and return result.",
	format = "**format** - Format strings\n\nSyntax: `format formatString ?arg ...?`\n\nFormat string using printf-style format specifiers.",
	scan = "**scan** - Parse strings\n\nSyntax: `scan string format ?varName ...?`\n\nParse string according to format specifiers.",
	split = "**split** - Split strings into lists\n\nSyntax: `split string ?splitChars?`\n\nSplit string into list using splitChars as delimiters.",
	join = "**join** - Join list elements into string\n\nSyntax: `join list ?joinString?`\n\nJoin list elements with joinString (space by default).",
	lappend = "**lappend** - Append elements to list\n\nSyntax: `lappend varName ?value ...?`\n\nAppend values to list variable.",
	llength = "**llength** - Get list length\n\nSyntax: `llength list`\n\nReturn number of elements in list.",
	lindex = "**lindex** - Get list element by index\n\nSyntax: `lindex list ?index...?`\n\nReturn element at specified index(es).",
	lrange = "**lrange** - Extract range from list\n\nSyntax: `lrange list first last`\n\nReturn elements from first to last index.",
	lsearch = "**lsearch** - Search list for element\n\nSyntax: `lsearch ?options? list pattern`\n\nSearch for pattern in list and return index.",
	lsort = "**lsort** - Sort list elements\n\nSyntax: `lsort ?options? list`\n\nReturn sorted copy of list.",

	-- Rivet-specific commands
	include = '**include** - Rivet include directive\n\nSyntax: `<%@ include file="filename.rvt" %>`\n\nInclude another Rivet template file.',
	parse = '**parse** - Rivet parse directive\n\nSyntax: `<%@ parse file="filename.rvt" %>`\n\nParse and execute another Rivet template file.',
	hputs = "**hputs** - Rivet HTML output\n\nSyntax: `hputs string`\n\nOutput string directly to HTML without escaping.",
	hesc = "**hesc** - HTML escape\n\nSyntax: `hesc string`\n\nEscape HTML special characters in string.",
	makeurl = "**makeurl** - Create URL\n\nSyntax: `makeurl ?-noamp? file ?arg value ...?`\n\nCreate a URL with optional query parameters.",
	import_keyvalue_pairs = "**import_keyvalue_pairs** - Import form data\n\nSyntax: `import_keyvalue_pairs`\n\nImport form data into TCL variables.",
	var_qs = "**var_qs** - Query string variable\n\nSyntax: `var_qs varname ?default?`\n\nGet query string variable value.",
	var_post = "**var_post** - POST variable\n\nSyntax: `var_post varname ?default?`\n\nGet POST form variable value.",
}

-- Get word under cursor
local function get_word_at_position(lines, position)
	local line = lines[position.line + 1]
	if not line then
		return nil
	end

	local char = position.character + 1
	local start_pos = char
	local end_pos = char

	-- Find word boundaries
	while start_pos > 1 and line:sub(start_pos - 1, start_pos - 1):match("[%w_]") do
		start_pos = start_pos - 1
	end

	while end_pos <= #line and line:sub(end_pos, end_pos):match("[%w_]") do
		end_pos = end_pos + 1
	end

	if start_pos < end_pos then
		return line:sub(start_pos, end_pos - 1)
	end

	return nil
end

-- Setup buffer-specific handlers and keymaps
function M.setup_buffer(client, bufnr, opts)
	local config = require("tcl-lsp.config").get()
	local diagnostics = require("tcl-lsp.diagnostics")
	local symbols = require("tcl-lsp.symbols")

	-- Buffer settings
	vim.bo[bufnr].commentstring = "# %s"
	vim.bo[bufnr].shiftwidth = 4
	vim.bo[bufnr].tabstop = 4
	vim.bo[bufnr].expandtab = true
	vim.bo[bufnr].autoindent = true
	vim.bo[bufnr].smartindent = true
	vim.bo[bufnr].syntax = "tcl"

	-- Disable treesitter highlighting to prevent conflicts
	vim.b[bufnr].ts_highlight = false

	-- Setup hover if enabled
	if config.hover then
		vim.keymap.set("n", config.keymaps.hover, function()
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local cursor = vim.api.nvim_win_get_cursor(0)
			local position = { line = cursor[1] - 1, character = cursor[2] }
			local word = get_word_at_position(lines, position)

			if word and tcl_docs[word] then
				vim.lsp.util.open_floating_preview({ tcl_docs[word] }, "markdown", config.float_config)
			else
				vim.notify("No documentation found for: " .. (word or "unknown"), vim.log.levels.INFO)
			end
		end, { buffer = bufnr, desc = "TCL Hover Documentation" })
	end

	-- Setup diagnostics if enabled
	if config.diagnostics then
		-- Syntax check on save
		if config.syntax_check_on_save then
			vim.api.nvim_create_autocmd("BufWritePost", {
				buffer = bufnr,
				callback = function()
					diagnostics.check_syntax(bufnr, config.tclsh_cmd)
				end,
				desc = "TCL syntax check on save",
			})
		end

		-- Syntax check on change (if enabled)
		if config.syntax_check_on_change then
			vim.api.nvim_create_autocmd("TextChanged", {
				buffer = bufnr,
				callback = function()
					diagnostics.check_syntax(bufnr, config.tclsh_cmd)
				end,
				desc = "TCL syntax check on change",
			})
		end

		-- Manual syntax check command
		vim.api.nvim_buf_create_user_command(bufnr, "TclCheck", function()
			diagnostics.check_syntax(bufnr, config.tclsh_cmd)
		end, { desc = "Check TCL syntax manually" })

		-- Manual syntax check keymap
		if config.keymaps.syntax_check then
			vim.keymap.set("n", config.keymaps.syntax_check, ":TclCheck<CR>", {
				buffer = bufnr,
				desc = "Check TCL syntax",
				silent = true,
			})
		end

		-- Initial syntax check
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(bufnr) then
				diagnostics.check_syntax(bufnr, config.tclsh_cmd)
			end
		end)
	end

	-- Additional buffer commands
	vim.api.nvim_buf_create_user_command(bufnr, "TclInfo", function()
		local info = {
			"TCL LSP Buffer Info:",
			"  Buffer: " .. bufnr,
			"  Filetype: " .. vim.bo[bufnr].filetype,
			"  Hover: " .. tostring(config.hover),
			"  Diagnostics: " .. tostring(config.diagnostics),
			"  TCL command: " .. config.tclsh_cmd,
		}
		vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
	end, { desc = "Show TCL LSP info for this buffer" })

	-- Symbol navigation setup
	local uri = vim.uri_from_bufnr(bufnr)

	-- Update symbols when buffer content changes
	local function update_symbols()
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(bufnr) then
				symbols.update_symbols(bufnr, uri)
			end
		end)
	end

	-- Initial symbol parsing
	update_symbols()

	-- Update symbols on save
	vim.api.nvim_create_autocmd("BufWritePost", {
		buffer = bufnr,
		callback = update_symbols,
		desc = "Update TCL symbols on save",
	})

	-- Update symbols on significant changes (optional, can be noisy)
	if config.symbol_update_on_change then
		vim.api.nvim_create_autocmd("TextChanged", {
			buffer = bufnr,
			callback = function()
				-- Debounce updates
				vim.defer_fn(update_symbols, 500)
			end,
			desc = "Update TCL symbols on change",
		})
	end

	-- Symbol navigation keymaps
	if config.symbol_navigation then
		-- Go to definition
		vim.keymap.set("n", "gd", function()
			local cursor = vim.api.nvim_win_get_cursor(0)
			local position = { line = cursor[1] - 1, character = cursor[2] }
			local definition = symbols.find_definition(uri, position)

			if definition then
				vim.lsp.util.jump_to_location(definition, "utf-8")
			else
				local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
				local word = symbols.get_word_at_position(lines, position)
				vim.notify("No definition found for: " .. (word or "unknown"), vim.log.levels.INFO)
			end
		end, { buffer = bufnr, desc = "Go to definition" })

		-- Find references
		vim.keymap.set("n", "gr", function()
			local cursor = vim.api.nvim_win_get_cursor(0)
			local position = { line = cursor[1] - 1, character = cursor[2] }
			local references = symbols.find_references(uri, position, true)

			if #references > 0 then
				vim.lsp.util.set_qflist(vim.lsp.util.locations_to_items(references, "utf-8"))
				vim.cmd("copen")
			else
				local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
				local word = symbols.get_word_at_position(lines, position)
				vim.notify("No references found for: " .. (word or "unknown"), vim.log.levels.INFO)
			end
		end, { buffer = bufnr, desc = "Find references" })

		-- Document symbols (outline)
		vim.keymap.set("n", "gO", function()
			local document_symbols = symbols.get_document_symbols(uri)

			if #document_symbols > 0 then
				-- Create a simple picker for symbols
				local items = {}
				for _, symbol in ipairs(document_symbols) do
					table.insert(items, {
						text = string.format("[%s] %s", symbol.detail, symbol.name),
						lnum = symbol.range.start.line + 1,
						col = symbol.range.start.character + 1,
					})
				end

				vim.fn.setqflist(items)
				vim.cmd("copen")
			else
				vim.notify("No symbols found in current buffer", vim.log.levels.INFO)
			end
		end, { buffer = bufnr, desc = "Document symbols" })
	end

	-- Commands for symbol navigation
	vim.api.nvim_buf_create_user_command(bufnr, "TclSymbols", function()
		local document_symbols = symbols.get_document_symbols(uri)
		local cache = symbols.get_cache()

		print("=== TCL Symbols in current buffer ===")
		if #document_symbols > 0 then
			for _, symbol in ipairs(document_symbols) do
				print(string.format("%s: %s (line %d)", symbol.detail, symbol.name, symbol.range.start.line + 1))
			end
		else
			print("No symbols found")
		end

		print("\n=== Symbol cache info ===")
		local total_files = 0
		local total_symbols = 0
		for file_uri, file_symbols in pairs(cache) do
			total_files = total_files + 1
			for _, symbol_list in pairs(file_symbols) do
				total_symbols = total_symbols + #symbol_list
			end
		end
		print(string.format("Cached files: %d, Total symbols: %d", total_files, total_symbols))
	end, { desc = "Show TCL symbols" })

	vim.api.nvim_buf_create_user_command(bufnr, "TclWorkspaceSymbols", function(opts)
		local query = opts.args
		local workspace_symbols = symbols.get_workspace_symbols(query)

		if #workspace_symbols > 0 then
			local items = {}
			for _, symbol in ipairs(workspace_symbols) do
				local filename = vim.uri_to_fname(symbol.location.uri)
				table.insert(items, {
					filename = filename,
					text = string.format("[%s] %s", symbol.containerName, symbol.name),
					lnum = symbol.location.range.start.line + 1,
					col = symbol.location.range.start.character + 1,
				})
			end

			vim.fn.setqflist(items)
			vim.cmd("copen")
		else
			vim.notify("No workspace symbols found" .. (query ~= "" and " for: " .. query or ""), vim.log.levels.INFO)
		end
	end, {
		desc = "Search workspace symbols",
		nargs = "?",
		complete = function()
			local all_symbols = symbols.get_all_symbols()
			local names = {}
			for _, symbol in ipairs(all_symbols) do
				table.insert(names, symbol.name)
			end
			return names
		end,
	})

	-- Clean up symbols when buffer is closed
	vim.api.nvim_create_autocmd("BufDelete", {
		buffer = bufnr,
		callback = function()
			symbols.clear_symbols(uri)
		end,
		desc = "Clean up TCL symbols on buffer close",
	})
end

return M
