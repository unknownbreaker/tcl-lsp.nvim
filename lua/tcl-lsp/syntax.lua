local utils = require("tcl-lsp.utils")
local config = require("tcl-lsp.config")
local M = {}

-- Enhanced syntax checking using script files
function M.check_syntax(file_path, tclsh_cmd, callback)
	if not file_path or file_path == "" then
		return false, "No file specified"
	end

	local syntax_script = string.format(
		[[
# Syntax check script
if {[catch {
    # Try to parse the file without executing
    set fp [open "%s" r]
    set content [read $fp]
    close $fp
    
    # Basic syntax check by trying to parse
    if {[catch {info complete $content} complete_result]} {
        puts "SYNTAX_ERROR: $complete_result"
        exit 1
    }
    
    if {!$complete_result} {
        puts "SYNTAX_ERROR: Incomplete script"
        exit 1
    }
    
    # Try to source in a safe interpreter
    set safe_interp [interp create -safe]
    if {[catch {$safe_interp eval $content} safe_error]} {
        interp delete $safe_interp
        # Only report actual syntax errors, not runtime errors
        if {[string match "*syntax error*" $safe_error] || 
            [string match "*missing*" $safe_error] ||
            [string match "*unexpected*" $safe_error]} {
            puts "SYNTAX_ERROR: $safe_error"
            exit 1
        }
    }
    interp delete $safe_interp
    
    puts "SYNTAX_OK"
} err]} {
    puts "SYNTAX_ERROR: $err"
    exit 1
}
]],
		file_path
	)

	utils.execute_tcl_script_async(syntax_script, tclsh_cmd, function(result, success)
		if result then
			if result:match("SYNTAX_OK") then
				return true, "Syntax OK"
			elseif result:match("SYNTAX_ERROR: (.+)") then
				local error_msg = result:match("SYNTAX_ERROR: (.+)")
				return false, error_msg
			end
		end

		callback(false, "Syntax check failed: " .. (result or "unknown error"))
	end)
end

-- Parse syntax errors and create diagnostics
function M.parse_syntax_errors(error_message, file_path)
	if not error_message then
		return {}
	end

	local diagnostics = {}
	local parsed_error = utils.parse_error_message(error_message)

	if parsed_error then
		local diagnostic = {
			range = {
				start = { line = (parsed_error.line or 1) - 1, character = 0 },
				["end"] = { line = (parsed_error.line or 1) - 1, character = -1 },
			},
			severity = vim.diagnostic.severity.ERROR,
			message = parsed_error.message,
			source = "tcl-lsp",
		}
		table.insert(diagnostics, diagnostic)
	else
		-- Fallback for unparseable errors
		local diagnostic = {
			range = {
				start = { line = 0, character = 0 },
				["end"] = { line = 0, character = -1 },
			},
			severity = vim.diagnostic.severity.ERROR,
			message = error_message,
			source = "tcl-lsp",
		}
		table.insert(diagnostics, diagnostic)
	end

	return diagnostics
end

-- Run syntax check on current buffer
function M.syntax_check_current_buffer()
	local file_path, err = utils.get_current_file_path()
	if not file_path then
		utils.notify(err or "No file to check", vim.log.levels.WARN)
		return
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	local success, message = M.check_syntax(file_path, tclsh_cmd)

	if success then
		utils.notify("✅ " .. message, vim.log.levels.INFO)
		-- Clear any existing diagnostics
		vim.diagnostic.reset(vim.api.nvim_create_namespace("tcl-lsp-syntax"))
	else
		utils.notify("❌ " .. message, vim.log.levels.ERROR)

		-- Set diagnostics if enabled
		if config.is_diagnostics_enabled() then
			local diagnostics = M.parse_syntax_errors(message, file_path)
			local namespace = vim.api.nvim_create_namespace("tcl-lsp-syntax")
			vim.diagnostic.set(namespace, 0, diagnostics)
		end
	end
end

-- Check syntax on save (autocmd callback)
function M.check_syntax_on_save()
	if not config.should_syntax_check_on_save() then
		return
	end

	if not utils.is_tcl_file() then
		return
	end

	-- Invalidate cache when file is saved
	local file_path = utils.get_current_file_path()
	if file_path then
		local tcl = require("tcl-lsp.tcl")
		tcl.invalidate_cache(file_path)
	end

	-- Defer to avoid blocking save
	vim.defer_fn(function()
		M.syntax_check_current_buffer()
	end, 100)
end

-- Check syntax on change (autocmd callback)
function M.check_syntax_on_change()
	if not config.should_syntax_check_on_change() then
		return
	end

	if not utils.is_tcl_file() then
		return
	end

	-- Invalidate cache when file changes
	local file_path = utils.get_current_file_path()
	if file_path then
		local tcl = require("tcl-lsp.tcl")
		tcl.invalidate_cache(file_path)
	end

	-- Debounce to avoid too many checks while typing
	local debounced_check = utils.debounce(function()
		M.syntax_check_current_buffer()
	end, 500)

	debounced_check()
end

-- Validate TCL script content (without file)
function M.validate_tcl_content(content, tclsh_cmd)
	if not content or content == "" then
		return false, "No content to validate"
	end

	local validation_script = string.format(
		[[
# Content validation script
set content {%s}

# Basic syntax check by trying to parse
if {[catch {info complete $content} complete_result]} {
    puts "VALIDATION_ERROR: $complete_result"
    exit 1
}

if {!$complete_result} {
    puts "VALIDATION_ERROR: Incomplete script"
    exit 1
}

# Try to parse in a safe interpreter
set safe_interp [interp create -safe]
if {[catch {$safe_interp eval $content} safe_error]} {
    interp delete $safe_interp
    # Only report actual syntax errors, not runtime errors
    if {[string match "*syntax error*" $safe_error] || 
        [string match "*missing*" $safe_error] ||
        [string match "*unexpected*" $safe_error]} {
        puts "VALIDATION_ERROR: $safe_error"
        exit 1
    }
}
interp delete $safe_interp

puts "VALIDATION_OK"
]],
		content:gsub("}", "\\}")
	)

	local result, success = utils.execute_tcl_script(validation_script, tclsh_cmd)

	if result then
		if result:match("VALIDATION_OK") then
			return true, "Content is valid"
		elseif result:match("VALIDATION_ERROR: (.+)") then
			local error_msg = result:match("VALIDATION_ERROR: (.+)")
			return false, error_msg
		end
	end

	return false, "Validation failed: " .. (result or "unknown error")
end

-- Check specific TCL constructs for common errors
function M.check_common_issues(file_path, tclsh_cmd)
	local issue_check_script = string.format(
		[[
# Check for common TCL issues
set file_path "%s"

if {[catch {
    set fp [open $file_path r]
    set content [read $fp]
    close $fp
} err]} {
    puts "ERROR: Cannot read file: $err"
    exit 1
}

set lines [split $content "\n"]
set line_num 0
set issues [list]

foreach line $lines {
    incr line_num
    set trimmed [string trim $line]
    
    # Skip comments and empty lines
    if {$trimmed eq "" || [string index $trimmed 0] eq "#"} {
        continue
    }
    
    # Check for unmatched braces
    set open_braces [regexp -all {\{} $line]
    set close_braces [regexp -all {\}} $line]
    if {$open_braces != $close_braces} {
        puts "ISSUE:warning:$line_num:Unmatched braces in line"
    }
    
    # Check for missing semicolons in control structures
    if {[regexp {^\s*(if|while|for|foreach)} $line] && ![regexp {\{$} $trimmed]} {
        puts "ISSUE:warning:$line_num:Control structure may be missing opening brace"
    }
    
    # Check for deprecated syntax
    if {[regexp {\[expr\s+[^]\]*\]} $line]} {
        puts "ISSUE:hint:$line_num:Consider using expr {...} instead of expr ..."
    }
    
    # Check for potential variable expansion issues
    if {[regexp {\$[a-zA-Z_][a-zA-Z0-9_]*\[} $line]} {
        puts "ISSUE:hint:$line_num:Variable array access may need braces: \${var}[index]"
    }
}

puts "ISSUES_COMPLETE"
]],
		file_path
	)

	local result, success = utils.execute_tcl_script(issue_check_script, tclsh_cmd)

	if not (result and success) then
		return {}
	end

	local issues = {}
	for line in result:gmatch("[^\n]+") do
		local severity, line_num, message = line:match("ISSUE:([^:]+):([^:]+):(.+)")
		if severity and line_num and message then
			local diagnostic_severity = vim.diagnostic.severity.INFO
			if severity == "error" then
				diagnostic_severity = vim.diagnostic.severity.ERROR
			elseif severity == "warning" then
				diagnostic_severity = vim.diagnostic.severity.WARN
			elseif severity == "hint" then
				diagnostic_severity = vim.diagnostic.severity.HINT
			end

			table.insert(issues, {
				range = {
					start = { line = tonumber(line_num) - 1, character = 0 },
					["end"] = { line = tonumber(line_num) - 1, character = -1 },
				},
				severity = diagnostic_severity,
				message = message,
				source = "tcl-lsp-lint",
			})
		end
	end

	return issues
end

-- Run comprehensive syntax and style checks
function M.comprehensive_check(file_path, tclsh_cmd)
	local results = {
		syntax_ok = false,
		syntax_message = "",
		issues = {},
		diagnostics = {},
	}

	-- First run syntax check
	local syntax_ok, syntax_message = M.check_syntax(file_path, tclsh_cmd)
	results.syntax_ok = syntax_ok
	results.syntax_message = syntax_message

	if syntax_ok then
		-- If syntax is OK, check for common issues
		results.issues = M.check_common_issues(file_path, tclsh_cmd)
		results.diagnostics = results.issues
	else
		-- If syntax failed, create error diagnostics
		results.diagnostics = M.parse_syntax_errors(syntax_message, file_path)
	end

	return results
end

-- Set up syntax checking autocmds
function M.setup_autocmds()
	local tcl_group = vim.api.nvim_create_augroup("TclLSP-Syntax", { clear = true })

	-- Auto syntax check on save
	if config.should_syntax_check_on_save() then
		vim.api.nvim_create_autocmd("BufWritePost", {
			pattern = "*.tcl",
			group = tcl_group,
			callback = M.check_syntax_on_save,
		})
	end

	-- Auto syntax check on change (if enabled)
	if config.should_syntax_check_on_change() then
		vim.api.nvim_create_autocmd("TextChanged", {
			pattern = "*.tcl",
			group = tcl_group,
			callback = M.check_syntax_on_change,
		})
	end
end

return M
