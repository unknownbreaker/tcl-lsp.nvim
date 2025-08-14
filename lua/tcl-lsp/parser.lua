local M = {}
local utils = require("tcl-lsp.utils")

-- Cache for parsed symbols
local file_cache = {}

-- Parse TCL file for symbols and validate syntax
function M.parse_file(filepath)
	local cache_key = filepath
	local current_mtime = utils.get_file_mtime(filepath)

	-- Check cache
	local cached = file_cache[cache_key]
	if cached and cached.mtime >= current_mtime then
		return cached.symbols
	end

	local symbols = {
		procedures = {},
		variables = {},
		namespaces = {},
		packages = {},
		errors = {},
	}

	-- Read file
	local file = io.open(filepath, "r")
	if not file then
		return symbols
	end

	local content = file:read("*all")
	file:close()

	-- First, check syntax using tclsh
	local config = require("tcl-lsp.config") and require("tcl-lsp.config").get() or { tclsh_cmd = "tclsh" }
	local syntax_errors = M.check_syntax_with_tclsh(filepath, config.tclsh_cmd)
	symbols.errors = syntax_errors

	-- Parse symbols using Lua patterns
	M.parse_symbols(content, filepath, symbols)

	-- Cache results
	file_cache[cache_key] = {
		symbols = symbols,
		mtime = current_mtime,
	}

	return symbols
end

-- Check syntax using tclsh
function M.check_syntax_with_tclsh(filepath, tclsh_cmd)
	tclsh_cmd = tclsh_cmd or "tclsh"
	local errors = {}

	-- Create a simple syntax check script
	local check_script = string.format(
		[[
    if {[catch {source %s} error]} {
      puts stderr "SYNTAX_ERROR:$error"
      exit 1
    }
    exit 0
  ]],
		vim.fn.shellescape(filepath)
	)

	-- Execute tclsh with our check script
	local cmd = string.format("%s -c %s", vim.fn.shellescape(tclsh_cmd), vim.fn.shellescape(check_script))

	local output = vim.fn.system(cmd .. " 2>&1")
	local exit_code = vim.v.shell_error

	if exit_code ~= 0 then
		-- Parse tclsh error output
		for line in output:gmatch("[^\r\n]+") do
			if line:match("SYNTAX_ERROR:") then
				local error_msg = line:gsub("SYNTAX_ERROR:", "")
				local line_num = M.extract_line_number(error_msg)

				table.insert(errors, {
					line = line_num or 1,
					col = 1,
					message = error_msg,
					severity = vim.diagnostic.severity.ERROR,
					source = "tclsh",
				})
			end
		end
	end

	return errors
end

-- Extract line number from TCL error message
function M.extract_line_number(error_msg)
	-- TCL error formats:
	-- "syntax error in expression ... line 5"
	-- "wrong # args ... (line 10)"
	-- "... line 15: ..."

	local patterns = {
		"line (%d+)",
		"%(line (%d+)%)",
		"line (%d+):",
	}

	for _, pattern in ipairs(patterns) do
		local line_num = error_msg:match(pattern)
		if line_num then
			return tonumber(line_num)
		end
	end

	return nil
end

-- Parse symbols from file content
function M.parse_symbols(content, filepath, symbols)
	local line_num = 0
	local in_comment_block = false

	for line in content:gmatch("[^\r\n]+") do
		line_num = line_num + 1
		local trimmed = line:match("^%s*(.-)%s*$")

		-- Skip empty lines and comments
		if trimmed == "" or trimmed:match("^#") then
			goto continue
		end

		-- Parse procedure definitions
		-- Patterns: proc name {args} {body} or proc name args body
		local proc_name, proc_args = trimmed:match("^proc%s+([%w_:]+)%s+{([^}]*)}")
		if not proc_name then
			proc_name = trimmed:match("^proc%s+([%w_:]+)%s+")
		end

		if proc_name then
			local col = line:find(proc_name, 1, true)
			table.insert(symbols.procedures, {
				name = proc_name,
				line = line_num,
				col = col or 1,
				file = filepath,
				type = "procedure",
				args = proc_args,
				range = utils.get_lsp_range(line_num - 1, (col or 1) - 1, line_num - 1, (col or 1) + #proc_name - 1),
			})
		end

		-- Parse variable assignments
		-- Patterns: set varname value, variable varname value, global varname
		local patterns = {
			"^set%s+([%w_:]+)",
			"^variable%s+([%w_:]+)",
			"^global%s+([%w_:]+)",
		}

		for _, pattern in ipairs(patterns) do
			local var_name = trimmed:match(pattern)
			if var_name then
				local col = line:find(var_name, 1, true)
				table.insert(symbols.variables, {
					name = var_name,
					line = line_num,
					col = col or 1,
					file = filepath,
					type = "variable",
					range = utils.get_lsp_range(line_num - 1, (col or 1) - 1, line_num - 1, (col or 1) + #var_name - 1),
				})
				break
			end
		end

		-- Parse namespace definitions
		local ns_name = trimmed:match("^namespace%s+eval%s+([%w_:]+)")
		if ns_name then
			local col = line:find(ns_name, 1, true)
			table.insert(symbols.namespaces, {
				name = ns_name,
				line = line_num,
				col = col or 1,
				file = filepath,
				type = "namespace",
				range = utils.get_lsp_range(line_num - 1, (col or 1) - 1, line_num - 1, (col or 1) + #ns_name - 1),
			})
		end

		-- Parse package requirements and provides
		local pkg_patterns = {
			"^package%s+require%s+([%w_:]+)",
			"^package%s+provide%s+([%w_:]+)",
		}

		for _, pattern in ipairs(pkg_patterns) do
			local pkg_name = trimmed:match(pattern)
			if pkg_name then
				local col = line:find(pkg_name, 1, true)
				table.insert(symbols.packages, {
					name = pkg_name,
					line = line_num,
					col = col or 1,
					file = filepath,
					type = "package",
					range = utils.get_lsp_range(line_num - 1, (col or 1) - 1, line_num - 1, (col or 1) + #pkg_name - 1),
				})
				break
			end
		end

		::continue::
	end
end

-- Clear symbol cache (useful for testing or manual refresh)
function M.clear_cache()
	file_cache = {}
end

-- Get cached symbols without reparsing
function M.get_cached_symbols(filepath)
	local cached = file_cache[filepath]
	return cached and cached.symbols or nil
end

return M
