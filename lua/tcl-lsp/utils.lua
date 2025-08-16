-- lua/tcl-lsp/utils.lua
-- Helper functions for TCL LSP

local M = {}

-- Helper function to execute Tcl scripts using temporary files
function M.execute_tcl_script(script_content, tclsh_cmd)
	tclsh_cmd = tclsh_cmd or "tclsh"

	-- Create temporary file
	local temp_file = os.tmpname() .. ".tcl"
	local file = io.open(temp_file, "w")
	if not file then
		vim.notify("Failed to create temporary Tcl script file", vim.log.levels.ERROR)
		return nil, false
	end

	-- Write script content
	file:write(script_content)
	file:close()

	-- Execute script
	local cmd = tclsh_cmd .. " " .. vim.fn.shellescape(temp_file) .. " 2>&1"
	local handle = io.popen(cmd)
	local result = handle:read("*a")
	local success = handle:close()

	-- Cleanup
	os.remove(temp_file)

	return result, success
end

function M.execute_tcl_script_async(script_content, tclsh_cmd, callback)
	tclsh_cmd = tclsh_cmd or "tclsh"

	-- Use Neovim's job API instead of io.popen
	local job_id = vim.fn.jobstart({ tclsh_cmd }, {
		stdin = "pipe",
		stdout_buffered = true,
		stderr_buffered = true,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				callback(job_output, exit_code == 0)
			end)
		end,
		on_stdout = function(_, data)
			job_output = table.concat(data, "\n")
		end,
	})

	-- Send script directly via stdin (no temp file!)
	vim.fn.chansend(job_id, script_content)
	vim.fn.chanclose(job_id, "stdin")
end

-- Check if tcllib JSON package is available
function M.check_tcllib_availability(tclsh_cmd)
	local test_script = [[
if {[catch {package require json} err]} {
    puts "ERROR: $err"
    exit 1
} else {
    puts "OK"
    puts "JSON_VERSION:[package provide json]"
}
]]

	local result, success = M.execute_tcl_script(test_script, tclsh_cmd)
	if result and success and result:match("OK") then
		local version = result:match("JSON_VERSION:([%d%.]+)")
		return true, version
	else
		return false, result
	end
end

-- Find the best available tclsh with tcllib support
function M.find_best_tclsh()
	local candidates = {
		"tclsh",
		"tclsh8.6",
		"tclsh8.5",
		"/opt/homebrew/bin/tclsh",
		"/opt/homebrew/bin/tclsh8.6",
		"/opt/homebrew/Cellar/tcl-tk@8/8.6.16/bin/tclsh8.6",
		"/opt/local/bin/tclsh",
		"/opt/local/bin/tclsh8.6",
		"/usr/local/bin/tclsh",
		"/usr/local/bin/tclsh8.6",
		"/usr/bin/tclsh",
		"/usr/bin/tclsh8.6",
		"/usr/bin/tclsh8.5",
	}

	for _, tclsh_cmd in ipairs(candidates) do
		-- Check if command exists
		local check_cmd = "command -v " .. tclsh_cmd .. " >/dev/null 2>&1"
		if os.execute(check_cmd) == 0 then
			-- Test if it has tcllib
			local has_tcllib, version_or_error = M.check_tcllib_availability(tclsh_cmd)
			if has_tcllib then
				return tclsh_cmd, version_or_error
			end
		end
	end

	return nil, "No tclsh with tcllib found"
end

-- Auto-setup filetype detection
function M.setup_filetype_detection()
	vim.filetype.add({
		extension = {
			tcl = "tcl",
			tk = "tcl",
			itcl = "tcl",
			itk = "tcl",
			rvt = "tcl", -- Rivet template files
			tcllib = "tcl", -- Tcllib files
		},
		filename = {
			[".tclshrc"] = "tcl",
			[".wishrc"] = "tcl",
			["tclIndex"] = "tcl",
		},
		pattern = {
			[".*%.tcl%.in$"] = "tcl", -- Template files
			[".*%.tk%.in$"] = "tcl", -- Tk template files
		},
	})
end

-- Get current file path with validation
function M.get_current_file_path()
	local file_path = vim.api.nvim_buf_get_name(0)
	if not file_path or file_path == "" then
		return nil, "No file to analyze"
	end
	return file_path, nil
end

-- Get word under cursor
function M.get_word_under_cursor()
	local word = vim.fn.expand("<cword>")
	if not word or word == "" then
		return nil, "No word under cursor"
	end
	return word, nil
end

-- Get word under cursor including namespace qualifiers
function M.get_qualified_word_under_cursor()
	-- Get the current line and cursor position
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1 -- Convert to 1-based indexing

	-- Find the boundaries of the qualified symbol (including ::)
	local start_pos = col
	local end_pos = col

	-- Move backwards to find the start
	while start_pos > 1 do
		local char = line:sub(start_pos - 1, start_pos - 1)
		if char:match("[a-zA-Z0-9_:]") then
			start_pos = start_pos - 1
		else
			break
		end
	end

	-- Move forwards to find the end
	while end_pos <= #line do
		local char = line:sub(end_pos, end_pos)
		if char:match("[a-zA-Z0-9_:]") then
			end_pos = end_pos + 1
		else
			break
		end
	end

	local qualified_word = line:sub(start_pos, end_pos - 1)

	-- Clean up the word (remove leading/trailing colons)
	qualified_word = qualified_word:gsub("^:+", ""):gsub(":+$", "")

	if not qualified_word or qualified_word == "" then
		return nil, "No qualified word under cursor"
	end

	return qualified_word, nil
end

-- Create quickfix list from results
function M.create_quickfix_list(items, title)
	local qflist = {}
	for _, item in ipairs(items) do
		table.insert(qflist, {
			bufnr = item.bufnr or vim.api.nvim_get_current_buf(),
			filename = item.filename,
			lnum = item.line or item.lnum,
			text = item.text,
		})
	end

	vim.fn.setqflist(qflist)
	vim.cmd("copen")

	if title then
		vim.notify(title, vim.log.levels.INFO)
	end
end

-- Set buffer-local keymap with description
function M.set_buffer_keymap(mode, lhs, rhs, opts, buffer)
	local default_opts = { buffer = buffer or 0, silent = true }
	local final_opts = vim.tbl_extend("force", default_opts, opts or {})
	vim.keymap.set(mode, lhs, rhs, final_opts)
end

-- Safely get buffer lines
function M.get_buffer_lines(bufnr, start_line, end_line)
	bufnr = bufnr or 0
	start_line = start_line or 0
	end_line = end_line or -1

	local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_line, end_line, false)
	if not ok then
		return nil, "Failed to read buffer lines"
	end

	return lines, nil
end

-- Check if a command exists in PATH
function M.command_exists(cmd)
	local check_cmd = "command -v " .. cmd .. " >/dev/null 2>&1"
	return os.execute(check_cmd) == 0
end

-- Debounce function calls
function M.debounce(func, delay)
	local timer_id = nil
	return function(...)
		local args = { ... }
		if timer_id then
			vim.fn.timer_stop(timer_id)
		end
		timer_id = vim.fn.timer_start(delay, function()
			func(unpack(args))
			timer_id = nil
		end)
	end
end

-- Parse error message to extract line number and description
function M.parse_error_message(error_msg)
	if not error_msg then
		return nil
	end

	-- Try to extract line number from common TCL error formats
	local line_num = error_msg:match("line (%d+)") or error_msg:match("at line (%d+)")
	if line_num then
		line_num = tonumber(line_num)
	end

	-- Clean up error message
	local clean_msg = error_msg:gsub("^[^:]+:%s*", "") -- Remove file prefix
	clean_msg = clean_msg:gsub("\n.*", "") -- Take only first line

	return {
		line = line_num,
		message = clean_msg,
		original = error_msg,
	}
end

-- Check if file exists and is readable
function M.file_exists(file_path)
	if not file_path then
		return false
	end

	local file = io.open(file_path, "r")
	if file then
		file:close()
		return true
	end
	return false
end

-- Get file extension
function M.get_file_extension(file_path)
	if not file_path then
		return nil
	end
	return file_path:match("%.([^%.]+)$")
end

-- Check if current buffer is a TCL file
function M.is_tcl_file(bufnr)
	bufnr = bufnr or 0
	local file_path = vim.api.nvim_buf_get_name(bufnr)
	local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

	if filetype == "tcl" then
		return true
	end

	local ext = M.get_file_extension(file_path)
	local tcl_extensions = { "tcl", "tk", "itcl", "itk", "rvt" }

	for _, tcl_ext in ipairs(tcl_extensions) do
		if ext == tcl_ext then
			return true
		end
	end

	return false
end

-- Show notification with proper formatting
function M.notify(message, level, title)
	level = level or vim.log.levels.INFO

	if title then
		message = title .. ":\n" .. message
	end

	vim.notify(message, level)
end

-- Safe string trim function
function M.trim(str)
	if not str then
		return ""
	end
	return str:match("^%s*(.-)%s*$")
end

-- Split string by delimiter
function M.split(str, delimiter)
	if not str then
		return {}
	end

	delimiter = delimiter or "%s+"
	local result = {}

	-- Handle special case for :: delimiter
	if delimiter == "::" then
		for part in str:gmatch("([^:]+)") do
			if part ~= "" then
				table.insert(result, part)
			end
		end
	else
		for match in str:gmatch("([^" .. delimiter .. "]+)") do
			table.insert(result, match)
		end
	end

	return result
end

-- Parse namespaced symbol name
function M.parse_symbol_name(symbol_name)
	if not symbol_name then
		return nil
	end

	local parts = M.split(symbol_name, "::")
	if #parts > 1 then
		return {
			full_name = symbol_name,
			namespace = table.concat(parts, "::", 1, #parts - 1),
			unqualified = parts[#parts],
			is_qualified = true,
		}
	else
		return {
			full_name = symbol_name,
			namespace = "",
			unqualified = symbol_name,
			is_qualified = false,
		}
	end
end

-- Check if two symbol names could refer to the same symbol
function M.symbols_match(symbol1, symbol2)
	if not symbol1 or not symbol2 then
		return false
	end

	-- Exact match
	if symbol1 == symbol2 then
		return true
	end

	local parsed1 = M.parse_symbol_name(symbol1)
	local parsed2 = M.parse_symbol_name(symbol2)

	-- If both are qualified, they must match exactly
	if parsed1.is_qualified and parsed2.is_qualified then
		return parsed1.full_name == parsed2.full_name
	end

	-- If one is qualified and one isn't, check if unqualified parts match
	if parsed1.is_qualified and not parsed2.is_qualified then
		return parsed1.unqualified == parsed2.unqualified
	end

	if not parsed1.is_qualified and parsed2.is_qualified then
		return parsed1.unqualified == parsed2.unqualified
	end

	-- Both unqualified
	return parsed1.unqualified == parsed2.unqualified
end

return M
