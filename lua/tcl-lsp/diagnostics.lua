-- Diagnostic functionality for tcl-lsp.nvim

local M = {}

-- Diagnostic namespace
local namespace = vim.api.nvim_create_namespace("tcl-lsp")

-- Setup diagnostics configuration
function M.setup(diagnostic_config)
	vim.diagnostic.config(diagnostic_config, namespace)
end

-- Parse TCL error message to extract line number and details
local function parse_tcl_error(error_text)
	local diagnostics = {}

	if not error_text or error_text == "" then
		return diagnostics
	end

	-- Split error text into lines
	local lines = vim.split(error_text, "\n")

	for _, line in ipairs(lines) do
		local trimmed = vim.trim(line)
		if trimmed ~= "" then
			-- Try to extract line number from various TCL error formats
			local line_num = nil
			local message = trimmed

			-- Format: "invalid command name "foo" (line 5)"
			local match = trimmed:match("%(line (%d+)%)")
			if match then
				line_num = tonumber(match) - 1 -- Convert to 0-based
			end

			-- Format: "couldn't read file "foo": no such file or directory"
			-- Format: "syntax error in expression "foo""
			-- Format: "wrong # args: should be "foo bar""

			-- If no line number found, default to line 0
			if not line_num then
				line_num = 0
				-- Try other patterns
				local line_match = trimmed:match("line (%d+)")
				if line_match then
					line_num = tonumber(line_match) - 1
				end
			end

			-- Determine severity based on error content
			local severity = vim.diagnostic.severity.ERROR
			if trimmed:match("warning") or trimmed:match("deprecated") then
				severity = vim.diagnostic.severity.WARN
			end

			table.insert(diagnostics, {
				range = {
					start = { line = line_num, character = 0 },
					["end"] = { line = line_num, character = 100 },
				},
				severity = severity,
				message = message,
				source = "tcl-syntax",
			})
		end
	end

	return diagnostics
end

-- Check TCL syntax using tclsh
function M.check_syntax(bufnr, tclsh_cmd)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
	local temp_file = vim.fn.tempname() .. ".tcl"

	-- Write content to temporary file
	local success = pcall(vim.fn.writefile, vim.split(content, "\n"), temp_file)
	if not success then
		vim.notify("Failed to create temporary file for syntax checking", vim.log.levels.ERROR)
		return
	end

	-- Run tclsh to check syntax
	local cmd = { tclsh_cmd or "tclsh", temp_file }

	vim.system(cmd, {
		stdout = false,
		stderr = true,
		text = true,
		timeout = 5000, -- 5 second timeout
	}, function(result)
		-- Clean up temporary file
		pcall(vim.fn.delete, temp_file)

		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end

			local diagnostics = {}

			if result.code ~= 0 and result.stderr then
				diagnostics = parse_tcl_error(result.stderr)
			end

			-- Set diagnostics
			vim.diagnostic.set(namespace, bufnr, diagnostics)

			-- Notify user of result
			if #diagnostics == 0 then
				vim.notify("TCL syntax: OK", vim.log.levels.INFO)
			else
				vim.notify(string.format("TCL syntax: %d error(s) found", #diagnostics), vim.log.levels.WARN)
			end
		end)
	end)
end

-- Clear diagnostics for a buffer
function M.clear_diagnostics(bufnr)
	vim.diagnostic.set(namespace, bufnr, {})
end

-- Get namespace for external use
function M.get_namespace()
	return namespace
end

-- Manual syntax check with immediate feedback
function M.check_syntax_sync(bufnr, tclsh_cmd)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return {}
	end

	local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
	local temp_file = vim.fn.tempname() .. ".tcl"

	-- Write content to temporary file
	local success = pcall(vim.fn.writefile, vim.split(content, "\n"), temp_file)
	if not success then
		return {}
	end

	-- Run tclsh synchronously
	local cmd = (tclsh_cmd or "tclsh") .. " " .. vim.fn.shellescape(temp_file) .. " 2>&1"
	local result = vim.fn.system(cmd)
	local exit_code = vim.v.shell_error

	-- Clean up
	pcall(vim.fn.delete, temp_file)

	local diagnostics = {}
	if exit_code ~= 0 and result and result ~= "" then
		diagnostics = parse_tcl_error(result)
	end

	return diagnostics
end

return M
