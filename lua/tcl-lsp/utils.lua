local M = {}

-- Find all TCL files in workspace
function M.find_tcl_files(root_dir)
	local files = {}
	root_dir = root_dir or vim.fn.getcwd()

	-- Use vim.fs.find for better cross-platform support
	local tcl_files = vim.fs.find(function(name, path)
		return name:match("%.tcl$") or name:match("%.rvt$") or name:match("%.tk$") or name:match("%.itcl$")
	end, {
		limit = math.huge,
		type = "file",
		path = root_dir,
	})

	return tcl_files
end

-- Get word at cursor position (helper for LSP methods)
function M.get_word_at_position(line, character)
	if not line or character < 0 or character > #line then
		return nil
	end

	-- Find the start of the word (go backwards from cursor)
	local start_pos = character
	while start_pos > 0 do
		local char = line:sub(start_pos, start_pos)
		if not char:match("[%w_:]") then
			start_pos = start_pos + 1
			break
		end
		start_pos = start_pos - 1
	end

	-- If we went all the way to the beginning, start at position 1
	if start_pos <= 0 then
		start_pos = 1
	end

	-- Find the end of the word (go forwards from cursor)
	local end_pos = character + 1
	while end_pos <= #line do
		local char = line:sub(end_pos, end_pos)
		if not char:match("[%w_:]") then
			end_pos = end_pos - 1
			break
		end
		end_pos = end_pos + 1
	end

	-- If we went past the end, use the line length
	if end_pos > #line then
		end_pos = #line
	end

	-- Extract the word
	if start_pos <= end_pos then
		local word = line:sub(start_pos, end_pos)
		return word ~= "" and word or nil
	end

	return nil
end

-- Convert file path to LSP URI
function M.path_to_uri(path)
	if vim.fn.has("win32") == 1 then
		path = path:gsub("\\", "/")
		return "file:///" .. path
	else
		return "file://" .. path
	end
end

-- Convert LSP URI to file path
function M.uri_to_path(uri)
	local path = uri:gsub("^file://", "")
	if vim.fn.has("win32") == 1 then
		path = path:gsub("^/", ""):gsub("/", "\\")
	end
	return path
end

-- Get LSP position from vim cursor
function M.get_lsp_position(bufnr, row, col)
	bufnr = bufnr or 0
	local cursor = vim.api.nvim_win_get_cursor(0)
	row = row or cursor[1] - 1 -- LSP is 0-indexed
	col = col or cursor[2] -- LSP is 0-indexed

	return {
		line = row,
		character = col,
	}
end

-- Get LSP range from vim positions
function M.get_lsp_range(start_line, start_col, end_line, end_col)
	return {
		start = { line = start_line, character = start_col },
		["end"] = { line = end_line or start_line, character = end_col or start_col },
	}
end

-- Check if tclsh is available
function M.check_tclsh(tclsh_cmd)
	tclsh_cmd = tclsh_cmd or "tclsh"

	-- Create a simple test script
	local temp_file = vim.fn.tempname() .. ".tcl"
	local test_script = 'puts "TCL_TEST_OK"\nexit 0'

	-- Write the test script
	local file = io.open(temp_file, "w")
	if not file then
		return false, "Cannot create temporary test file"
	end

	file:write(test_script)
	file:close()

	-- Run tclsh with the test script
	local cmd = string.format("%s %s 2>&1", vim.fn.shellescape(tclsh_cmd), vim.fn.shellescape(temp_file))

	local handle = io.popen(cmd)
	if not handle then
		vim.fn.delete(temp_file)
		return false, "Cannot execute " .. tclsh_cmd
	end

	local result = handle:read("*a")
	local success = handle:close()

	-- Clean up
	vim.fn.delete(temp_file)

	if success and result:match("TCL_TEST_OK") then
		return true, nil
	else
		return false, "tclsh test failed: " .. (result or "unknown error")
	end
end

-- Cache management for symbols
M.cache = {}

function M.cache_get(key)
	return M.cache[key]
end

function M.cache_set(key, value, ttl)
	M.cache[key] = {
		value = value,
		timestamp = vim.loop.now(),
		ttl = ttl or 5000, -- 5 seconds default
	}
end

function M.cache_is_valid(key)
	local entry = M.cache[key]
	if not entry then
		return false
	end

	local now = vim.loop.now()
	return (now - entry.timestamp) < entry.ttl
end

function M.cache_clear()
	M.cache = {}
end

-- File modification time checking
function M.get_file_mtime(filepath)
	local stat = vim.loop.fs_stat(filepath)
	return stat and stat.mtime.sec or 0
end

-- Debounce function for rapid changes
function M.debounce(func, delay)
	local timer = nil
	return function(...)
		local args = { ... }
		if timer then
			timer:stop()
		end
		timer = vim.defer_fn(function()
			func(unpack(args))
		end, delay)
	end
end

return M
