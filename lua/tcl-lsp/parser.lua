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

-- Syntax checker that handles missing packages
function M.check_syntax_with_tclsh(filepath, tclsh_cmd)
	tclsh_cmd = tclsh_cmd or "tclsh"
	local errors = {}

	-- Create a package-aware validation script
	local temp_script = vim.fn.tempname() .. ".tcl"
	local script_content = string.format(
		[[
# Package-aware TCL syntax validation script
set original_file {%s}
set syntax_only 1

# Override package require to avoid missing package errors
rename package package_original
proc package {cmd args} {
    if {$cmd eq "require"} {
        # Just return a dummy version for any package
        return "1.0"
    } else {
        # For other package commands, call the original
        return [eval package_original $cmd $args]
    }
}

# Override other commands that might cause issues in syntax-only mode
proc source {filename} {
    # In syntax-only mode, don't actually source other files
    if {[info exists ::syntax_only]} {
        return
    }
    # Otherwise, call the real source
    return [source_original $filename]
}

# Capture all errors
if {[catch {
    # Try to parse/source the file
    source $original_file
} error_msg error_info]} {
    
    # Filter out package-related errors that we don't care about
    set filtered_errors {}
    
    # Check if it's a real syntax error vs. a package/runtime error
    set is_syntax_error 0
    set error_line 1
    
    # Common syntax error patterns
    if {[regexp -i {syntax error|missing|unexpected|invalid command|wrong # args} $error_msg]} {
        set is_syntax_error 1
    }
    
    # Extract line number from various error formats
    if {[info exists error_info]} {
        if {[regexp {\(file ".*?" line ([0-9]+)\)} $error_info match line_num]} {
            set error_line $line_num
        } elseif {[regexp {line ([0-9]+)} $error_info match line_num]} {
            set error_line $line_num
        }
    }
    
    # Also try to get line number from error message
    if {[regexp {line ([0-9]+)} $error_msg match line_num]} {
        set error_line $line_num
    }
    
    # Only report if it looks like a real syntax error
    if {$is_syntax_error} {
        puts stderr "TCL_SYNTAX_ERROR:$error_line:$error_msg"
        exit 1
    } else {
        # It's probably a runtime/package error, not a syntax error
        puts "TCL_SYNTAX_OK_RUNTIME_ERROR:$error_msg"
        exit 0
    }
}

# If we get here, syntax is completely OK
puts "TCL_SYNTAX_OK"
exit 0
]],
		filepath
	)

	-- Write and execute the validation script
	local script_file = io.open(temp_script, "w")
	if not script_file then
		table.insert(errors, {
			line = 1,
			col = 1,
			message = "Cannot create temporary validation script",
			severity = vim.diagnostic.severity.ERROR,
			source = "tcl-lsp",
		})
		return errors
	end

	script_file:write(script_content)
	script_file:close()

	-- Execute the validation script
	local cmd = string.format("%s %s 2>&1", vim.fn.shellescape(tclsh_cmd), vim.fn.shellescape(temp_script))

	local output = vim.fn.system(cmd)
	local exit_code = vim.v.shell_error

	-- Clean up temp file
	vim.fn.delete(temp_script)

	-- Parse the output
	for line in output:gmatch("[^\r\n]+") do
		if line:match("^TCL_SYNTAX_ERROR:") then
			local line_num, error_msg = line:match("^TCL_SYNTAX_ERROR:(%d+):(.*)$")
			if line_num and error_msg then
				table.insert(errors, {
					line = tonumber(line_num),
					col = 1,
					message = error_msg:gsub("^%s+", ""):gsub("%s+$", ""),
					severity = vim.diagnostic.severity.ERROR,
					source = "tclsh",
				})
			end
		elseif line:match("^TCL_SYNTAX_OK") then
			-- Syntax is OK, even if there were runtime errors
			break
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

function M.safe_parse_file(filepath)
	-- Disable treesitter temporarily for this file if it's causing issues
	local bufnr = vim.fn.bufnr(filepath)
	local ts_disabled = false

	if bufnr ~= -1 then
		-- Check if treesitter is causing issues
		local ok, _ = pcall(vim.treesitter.get_parser, bufnr, "tcl")
		if not ok then
			-- Disable treesitter for this buffer temporarily
			vim.b[bufnr].ts_highlight = false
			ts_disabled = true
		end
	end

	-- Parse the file normally
	local result = M.parse_file(filepath)

	-- Re-enable treesitter if we disabled it
	if ts_disabled and bufnr ~= -1 then
		vim.b[bufnr].ts_highlight = nil
	end

	return result
end

function M.check_syntax(filepath, tclsh_cmd, mode)
	mode = mode or "package_aware"

	if mode == "disabled" then
		return {}
	elseif mode == "parse_only" then
		return M.check_syntax_only(filepath, tclsh_cmd)
	elseif mode == "package_aware" then
		return M.check_syntax_with_tclsh(filepath, tclsh_cmd)
	elseif mode == "full" then
		-- Original method - will fail on missing packages
		return M.check_syntax_original(filepath, tclsh_cmd)
	else
		return M.check_syntax_with_tclsh(filepath, tclsh_cmd)
	end
end
return M
