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

	-- Check syntax using file-based approach
	local config = require("tcl-lsp.config") and require("tcl-lsp.config").get()
		or { tclsh_cmd = "tclsh", syntax_check_mode = "package_aware" }
	local syntax_errors = M.check_syntax_file_based(filepath, config.tclsh_cmd, config.syntax_check_mode)
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

-- File-based syntax checking (no -c flag needed)
function M.check_syntax_file_based(filepath, tclsh_cmd, mode)
	tclsh_cmd = tclsh_cmd or "tclsh"
	mode = mode or "package_aware"
	local errors = {}

	-- First, check if the file exists and is readable
	local file = io.open(filepath, "r")
	if not file then
		table.insert(errors, {
			line = 1,
			col = 1,
			message = "Cannot read file: " .. filepath,
			severity = vim.diagnostic.severity.ERROR,
			source = "tcl-lsp",
		})
		return errors
	end

	local original_content = file:read("*all")
	file:close()

	if mode == "disabled" then
		return {}
	elseif mode == "parse_only" then
		return M.check_syntax_parse_only(original_content)
	end

	-- Create a temporary validation script
	local temp_dir = vim.fn.tempname()
	vim.fn.mkdir(temp_dir, "p")
	local temp_script = temp_dir .. "/validate.tcl"
	local temp_output = temp_dir .. "/output.txt"

	local script_content
	if mode == "package_aware" then
		script_content = M.create_package_aware_validator(filepath, temp_output)
	else
		script_content = M.create_simple_validator(filepath, temp_output)
	end

	-- Write the validation script
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

	-- Execute tclsh with the validation script
	local cmd = string.format("%s %s 2>&1", vim.fn.shellescape(tclsh_cmd), vim.fn.shellescape(temp_script))

	local output = vim.fn.system(cmd)
	local exit_code = vim.v.shell_error

	-- Read the structured output if it was created
	local output_file = io.open(temp_output, "r")
	if output_file then
		local structured_output = output_file:read("*all")
		output_file:close()

		-- Parse structured output
		for line in structured_output:gmatch("[^\r\n]+") do
			if line:match("^ERROR:") then
				local line_num, error_msg = line:match("^ERROR:(%d+):(.*)$")
				if line_num and error_msg then
					table.insert(errors, {
						line = tonumber(line_num),
						col = 1,
						message = error_msg:gsub("^%s+", ""):gsub("%s+$", ""),
						severity = vim.diagnostic.severity.ERROR,
						source = "tclsh",
					})
				end
			end
		end
	end

	-- If no structured output, parse the regular output
	if #errors == 0 and exit_code ~= 0 then
		for line in output:gmatch("[^\r\n]+") do
			local line_num = M.extract_line_number(line) or 1
			if not line:match("^%s*$") then -- Skip empty lines
				table.insert(errors, {
					line = line_num,
					col = 1,
					message = line,
					severity = vim.diagnostic.severity.ERROR,
					source = "tclsh",
				})
			end
		end
	end

	-- Clean up temporary files
	vim.fn.delete(temp_dir, "rf")

	return errors
end

-- Create package-aware validation script
function M.create_package_aware_validator(filepath, output_file)
	return string.format(
		[[
# Package-aware TCL syntax validation
set original_file {%s}
set output_file {%s}
set syntax_only 1

# Override package require to avoid missing package errors
if {[info commands package_original] eq ""} {
    rename package package_original
}

proc package {cmd args} {
    if {$cmd eq "require"} {
        # Just return a dummy version for any package
        return "1.0"
    } else {
        # For other package commands, call the original
        return [eval package_original $cmd $args]
    }
}

# Capture errors and write to output file
set error_output [open $output_file w]

if {[catch {
    # Try to source the original file
    source $original_file
} error_msg error_info]} {
    
    # Check if it's a real syntax error vs. a package/runtime error
    set is_syntax_error 0
    set error_line 1
    
    # Common syntax error patterns
    if {[regexp -i {syntax error|missing|unexpected|invalid command|wrong # args|extra characters} $error_msg]} {
        set is_syntax_error 1
    }
    
    # Extract line number from various error formats
    if {[info exists error_info]} {
        set error_info_dict [dict create {*}$error_info]
        if {[dict exists $error_info_dict -errorline]} {
            set error_line [dict get $error_info_dict -errorline]
        }
    }
    
    # Try to extract line number from error message
    if {[regexp {\(file ".*?" line ([0-9]+)\)} $error_msg match line_num]} {
        set error_line $line_num
    } elseif {[regexp {line ([0-9]+)} $error_msg match line_num]} {
        set error_line $line_num
    }
    
    # Only report if it looks like a real syntax error
    if {$is_syntax_error} {
        puts $error_output "ERROR:$error_line:$error_msg"
        close $error_output
        exit 1
    }
}

close $error_output
puts "SYNTAX_OK"
exit 0
]],
		filepath,
		output_file
	)
end

-- Create simple validation script
function M.create_simple_validator(filepath, output_file)
	return string.format(
		[[
# Simple TCL syntax validation
set original_file {%s}
set output_file {%s}

set error_output [open $output_file w]

if {[catch {
    source $original_file
} error_msg error_info]} {
    
    set error_line 1
    
    # Try to extract line number
    if {[info exists error_info]} {
        set error_info_dict [dict create {*}$error_info]
        if {[dict exists $error_info_dict -errorline]} {
            set error_line [dict get $error_info_dict -errorline]
        }
    }
    
    if {[regexp {line ([0-9]+)} $error_msg match line_num]} {
        set error_line $line_num
    }
    
    puts $error_output "ERROR:$error_line:$error_msg"
    close $error_output
    exit 1
}

close $error_output
puts "SYNTAX_OK"
exit 0
]],
		filepath,
		output_file
	)
end

-- Parse-only syntax checking (doesn't execute code)
function M.check_syntax_parse_only(content)
	local errors = {}
	local lines = vim.split(content, "\n")
	local line_num = 0
	local accumulated = ""
	local brace_depth = 0
	local in_string = false
	local escape_next = false

	for _, line in ipairs(lines) do
		line_num = line_num + 1
		local trimmed = line:match("^%s*(.-)%s*$")

		-- Skip empty lines and comments
		if trimmed == "" or trimmed:match("^#") then
			goto continue
		end

		accumulated = accumulated .. line .. "\n"

		-- Basic brace counting (simplified)
		for i = 1, #line do
			local char = line:sub(i, i)

			if escape_next then
				escape_next = false
			elseif char == "\\" then
				escape_next = true
			elseif char == '"' and not in_string then
				in_string = true
			elseif char == '"' and in_string then
				in_string = false
			elseif not in_string then
				if char == "{" then
					brace_depth = brace_depth + 1
				elseif char == "}" then
					brace_depth = brace_depth - 1
					if brace_depth < 0 then
						table.insert(errors, {
							line = line_num,
							col = i,
							message = "Unmatched closing brace",
							severity = vim.diagnostic.severity.ERROR,
							source = "tcl-parser",
						})
					end
				end
			end
		end

		-- Check if we have a complete command
		if brace_depth == 0 and not in_string then
			-- Try basic TCL parsing
			local ok, result = pcall(function()
				-- Very basic validation - check if it looks like valid TCL structure
				if accumulated:match("^%s*proc%s+") and not accumulated:match("proc%s+%w+%s+{.-}%s+{.*}") then
					error("Incomplete procedure definition")
				end
				return true
			end)

			if not ok then
				table.insert(errors, {
					line = line_num,
					col = 1,
					message = result or "Parse error",
					severity = vim.diagnostic.severity.ERROR,
					source = "tcl-parser",
				})
			end

			accumulated = ""
		end

		::continue::
	end

	-- Check for unclosed braces at end of file
	if brace_depth > 0 then
		table.insert(errors, {
			line = line_num,
			col = 1,
			message = "Unclosed braces at end of file",
			severity = vim.diagnostic.severity.ERROR,
			source = "tcl-parser",
		})
	elseif in_string then
		table.insert(errors, {
			line = line_num,
			col = 1,
			message = "Unclosed string at end of file",
			severity = vim.diagnostic.severity.ERROR,
			source = "tcl-parser",
		})
	end

	return errors
end

-- Extract line number from TCL error message
function M.extract_line_number(error_msg)
	local patterns = {
		"line (%d+)",
		"%(line (%d+)%)",
		"line (%d+):",
		".*:(%d+):",
	}

	for _, pattern in ipairs(patterns) do
		local line_num = error_msg:match(pattern)
		if line_num then
			return tonumber(line_num)
		end
	end

	return nil
end

-- Parse symbols from file content (same as before)
function M.parse_symbols(content, filepath, symbols)
	local lines = vim.split(content, "\n")
	local line_num = 0

	for _, line in ipairs(lines) do
		line_num = line_num + 1
		local original_line = line
		local trimmed = line:match("^%s*(.-)%s*$")

		-- Skip empty lines and comments
		if trimmed == "" or trimmed:match("^#") then
			goto continue
		end

		-- Parse procedure definitions with more precision
		-- Look for: proc name {args} {body} or proc name args body
		local proc_pattern = "^%s*proc%s+([%w_:]+)"
		local proc_name = trimmed:match(proc_pattern)

		if proc_name then
			-- Find the exact column where 'proc' starts
			local proc_start_col = original_line:find("proc")
			-- Find where the procedure name starts
			local name_start_col = original_line:find(proc_name, proc_start_col)

			table.insert(symbols.procedures, {
				name = proc_name,
				line = line_num,
				col = name_start_col or proc_start_col or 1,
				file = filepath,
				type = "procedure",
				range = utils.get_lsp_range(
					line_num - 1,
					(name_start_col or proc_start_col or 1) - 1,
					line_num - 1,
					(name_start_col or proc_start_col or 1) + #proc_name - 1
				),
			})
		end

		-- Parse variable assignments with better precision
		local var_patterns = {
			{ pattern = "^%s*set%s+([%w_:]+)", command = "set" },
			{ pattern = "^%s*variable%s+([%w_:]+)", command = "variable" },
			{ pattern = "^%s*global%s+([%w_:]+)", command = "global" },
		}

		for _, var_pattern in ipairs(var_patterns) do
			local var_name = trimmed:match(var_pattern.pattern)
			if var_name then
				-- Find the exact position of the variable name
				local cmd_start = original_line:find(var_pattern.command)
				local var_start_col = original_line:find(var_name, cmd_start)

				table.insert(symbols.variables, {
					name = var_name,
					line = line_num,
					col = var_start_col or cmd_start or 1,
					file = filepath,
					type = "variable",
					range = utils.get_lsp_range(
						line_num - 1,
						(var_start_col or cmd_start or 1) - 1,
						line_num - 1,
						(var_start_col or cmd_start or 1) + #var_name - 1
					),
				})
				break -- Only match the first pattern
			end
		end

		-- Parse namespace definitions with precision
		local ns_pattern = "^%s*namespace%s+eval%s+([%w_:]+)"
		local ns_name = trimmed:match(ns_pattern)
		if ns_name then
			local ns_cmd_start = original_line:find("namespace")
			local ns_name_start = original_line:find(ns_name, ns_cmd_start)

			table.insert(symbols.namespaces, {
				name = ns_name,
				line = line_num,
				col = ns_name_start or ns_cmd_start or 1,
				file = filepath,
				type = "namespace",
				range = utils.get_lsp_range(
					line_num - 1,
					(ns_name_start or ns_cmd_start or 1) - 1,
					line_num - 1,
					(ns_name_start or ns_cmd_start or 1) + #ns_name - 1
				),
			})
		end

		-- Parse package requirements and provides with precision
		local pkg_patterns = {
			{ pattern = "^%s*package%s+require%s+([%w_:]+)", type = "require" },
			{ pattern = "^%s*package%s+provide%s+([%w_:]+)", type = "provide" },
		}

		for _, pkg_pattern in ipairs(pkg_patterns) do
			local pkg_name = trimmed:match(pkg_pattern.pattern)
			if pkg_name then
				local pkg_cmd_start = original_line:find("package")
				local pkg_name_start = original_line:find(pkg_name, pkg_cmd_start)

				table.insert(symbols.packages, {
					name = pkg_name,
					line = line_num,
					col = pkg_name_start or pkg_cmd_start or 1,
					file = filepath,
					type = "package",
					subtype = pkg_pattern.type,
					range = utils.get_lsp_range(
						line_num - 1,
						(pkg_name_start or pkg_cmd_start or 1) - 1,
						line_num - 1,
						(pkg_name_start or pkg_cmd_start or 1) + #pkg_name - 1
					),
				})
				break
			end
		end

		::continue::
	end
end

-- Also add a helper function to find the exact definition line
-- This ensures we jump to the actual 'proc' line, not a comment above it
function M.find_exact_definition_line(filepath, symbol_name, approximate_line)
	local file = io.open(filepath, "r")
	if not file then
		return approximate_line
	end

	local lines = {}
	for line in file:lines() do
		table.insert(lines, line)
	end
	file:close()

	-- Search around the approximate line for the actual definition
	local search_start = math.max(1, approximate_line - 5)
	local search_end = math.min(#lines, approximate_line + 5)

	for i = search_start, search_end do
		local line = lines[i]
		local trimmed = line:match("^%s*(.-)%s*$")

		-- Skip comments and empty lines
		if not trimmed:match("^#") and trimmed ~= "" then
			-- Check if this line contains the procedure definition
			if trimmed:match("^proc%s+" .. vim.patternescape(symbol_name) .. "%s") then
				return i
			end
		end
	end

	-- If we can't find the exact line, return the approximate one
	return approximate_line
end

-- Main syntax checking function
function M.check_syntax(filepath, tclsh_cmd, mode)
	return M.check_syntax_file_based(filepath, tclsh_cmd, mode)
end

-- Clear symbol cache
function M.clear_cache()
	file_cache = {}
end

-- Get cached symbols without reparsing
function M.get_cached_symbols(filepath)
	local cached = file_cache[filepath]
	return cached and cached.symbols or nil
end

return M
