local M = {}

local config = require("tcl-lsp.config")
local server = require("tcl-lsp.server")

-- Default configuration
M.config = {
	-- Server settings
	server = {
		cmd = nil, -- Will be auto-detected
		settings = {
			tcl = {
				-- Future: TCL-specific settings
			},
		},
	},

	-- LSP client settings
	on_attach = nil, -- User can override
	capabilities = nil, -- Will use defaults

	-- Auto-install dependencies
	auto_install = {
		tcl = true, -- Check for tclsh
		tcllib = true, -- Check for JSON package
	},

	-- Logging
	log_level = vim.log.levels.WARN,
}

-- Setup function called by users
function M.setup(user_config)
	config = vim.tbl_deep_extend("force", default_config, user_config or {})

	-- Auto-detect the best tclsh if set to "auto" or not specified
	if config.tclsh_cmd == "auto" or config.tclsh_cmd == "tclsh" then
		local best_tclsh, version_or_error = find_best_tclsh()
		if best_tclsh then
			config.tclsh_cmd = best_tclsh
			vim.notify("✅ TCL LSP: Found " .. best_tclsh .. " with JSON " .. version_or_error, vim.log.levels.INFO)
		else
			vim.notify("❌ TCL LSP: No suitable Tcl installation found: " .. version_or_error, vim.log.levels.ERROR)
			vim.notify("💡 Try installing: brew install tcl-tk && install tcllib", vim.log.levels.INFO)
			return
		end
	else
		-- Verify user-specified tclsh
		local has_tcllib, version_or_error = check_tcllib_availability(config.tclsh_cmd)
		if not has_tcllib then
			vim.notify("❌ TCL LSP: Specified tclsh doesn't have tcllib: " .. version_or_error, vim.log.levels.ERROR)
			return
		else
			vim.notify(
				"✅ TCL LSP: Using " .. config.tclsh_cmd .. " with JSON " .. version_or_error,
				vim.log.levels.INFO
			)
		end
	end

	-- Configure diagnostics globally
	vim.diagnostic.config(config.diagnostic_config)

	-- Auto-setup everything if enabled (default: true)
	if config.auto_setup_filetypes then
		setup_filetype_detection()
	end

	if config.auto_setup_commands then
		setup_user_commands()
	end

	if config.auto_setup_autocmds then
		setup_buffer_autocmds()
	end

	-- Show success message with quick start info
	local success_msg = string.format([[
🎉 TCL LSP ready! Quick commands:
  :TclCheck - Check syntax
  :TclInfo - System info  
  :TclJsonTest - Test JSON
  <leader>tc - Syntax check
  K - Hover docs (in .tcl files)
]])

	vim.notify(success_msg, vim.log.levels.INFO)
end -- lua/tcl-lsp/init.lua
-- Updated TCL LSP plugin to use script files instead of -c flag

local M = {}

-- Default configuration - everything enabled and configured for best experience
local default_config = {
	hover = true,
	diagnostics = true,
	symbol_navigation = true,
	completion = false,
	symbol_update_on_change = false,
	diagnostic_config = {
		virtual_text = {
			spacing = 4,
			prefix = "●",
			source = "if_many",
		},
		signs = {
			text = {
				[vim.diagnostic.severity.ERROR] = "✗",
				[vim.diagnostic.severity.WARN] = "▲",
				[vim.diagnostic.severity.HINT] = "⚑",
				[vim.diagnostic.severity.INFO] = "»",
			},
		},
		underline = true,
		update_in_insert = false,
		severity_sort = true,
		float = {
			focusable = false,
			style = "minimal",
			border = "rounded",
			source = "if_many",
			header = "",
			prefix = "",
		},
	},
	tclsh_cmd = "auto", -- Auto-detect the best tclsh
	syntax_check_on_save = true,
	syntax_check_on_change = false,
	keymaps = {
		hover = "K",
		syntax_check = "<leader>tc",
		goto_definition = "gd",
		find_references = "gr",
		document_symbols = "gO",
		workspace_symbols = "<leader>tw",
	},
	-- Auto-setup features
	auto_setup_filetypes = true,
	auto_setup_commands = true,
	auto_setup_autocmds = true,
}

local config = {}

-- Helper function to execute Tcl scripts using temporary files
-- This replaces all uses of `tclsh -c` with proper script files
local function execute_tcl_script(script_content, tclsh_cmd)
	tclsh_cmd = tclsh_cmd or config.tclsh_cmd or "tclsh"

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

-- Check if tcllib JSON package is available
local function check_tcllib_availability(tclsh_cmd)
	local test_script = [[
if {[catch {package require json} err]} {
    puts "ERROR: $err"
    exit 1
} else {
    puts "OK"
    puts "JSON_VERSION:[package provide json]"
}
]]

	local result, success = execute_tcl_script(test_script, tclsh_cmd)
	if result and success and result:match("OK") then
		local version = result:match("JSON_VERSION:([%d%.]+)")
		return true, version
	else
		return false, result
	end
end

-- Find the best available tclsh with tcllib support
local function find_best_tclsh()
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
			local has_tcllib, version_or_error = check_tcllib_availability(tclsh_cmd)
			if has_tcllib then
				return tclsh_cmd, version_or_error
			end
		end
	end

	return nil, "No tclsh with tcllib found"
end

-- Enhanced syntax checking using script files
local function check_syntax(file_path, tclsh_cmd)
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

	local result, success = execute_tcl_script(syntax_script, tclsh_cmd)

	if result then
		if result:match("SYNTAX_OK") then
			return true, "Syntax OK"
		elseif result:match("SYNTAX_ERROR: (.+)") then
			local error_msg = result:match("SYNTAX_ERROR: (.+)")
			return false, error_msg
		end
	end

	return false, "Syntax check failed: " .. (result or "unknown error")
end

-- Get Tcl system information
local function get_tcl_info(tclsh_cmd)
	local info_script = [[
puts "TCL_VERSION:[info patchlevel]"
puts "TCL_LIBRARY:[info library]"
puts "TCL_EXECUTABLE:[info nameofexecutable]"

if {![catch {package require json}]} {
    puts "JSON_VERSION:[package provide json]"
} else {
    puts "JSON_VERSION:NOT_AVAILABLE"
}

puts "AUTO_PATH_START"
foreach path $auto_path {
    puts "PATH:$path"
}
puts "AUTO_PATH_END"
]]

	local result, success = execute_tcl_script(info_script, tclsh_cmd)
	if not (result and success) then
		return nil
	end

	local info = {}
	info.tcl_version = result:match("TCL_VERSION:([^\n]+)")
	info.tcl_library = result:match("TCL_LIBRARY:([^\n]+)")
	info.tcl_executable = result:match("TCL_EXECUTABLE:([^\n]+)")
	info.json_version = result:match("JSON_VERSION:([^\n]+)")

	info.auto_path = {}
	local in_path_section = false
	for line in result:gmatch("[^\n]+") do
		if line == "AUTO_PATH_START" then
			in_path_section = true
		elseif line == "AUTO_PATH_END" then
			in_path_section = false
		elseif in_path_section and line:match("^PATH:(.+)") then
			table.insert(info.auto_path, line:match("^PATH:(.+)"))
		end
	end

	return info
end

-- Test JSON functionality
local function test_json_functionality(tclsh_cmd)
	local json_test_script = [[
if {[catch {package require json} err]} {
    puts "JSON_ERROR:$err"
    exit 1
}

set test_data {{"hello": "world", "number": 42, "array": [1, 2, 3]}}
if {[catch {set result [json::json2dict $test_data]} err]} {
    puts "JSON_PARSE_ERROR:$err"
    exit 1
} else {
    puts "JSON_SUCCESS"
    puts "RESULT:$result"
}
]]

	local result, success = execute_tcl_script(json_test_script, tclsh_cmd)

	if result and success then
		if result:match("JSON_SUCCESS") then
			local parsed_result = result:match("RESULT:([^\n]+)")
			return true, parsed_result
		elseif result:match("JSON_ERROR:(.+)") then
			return false, result:match("JSON_ERROR:(.+)")
		elseif result:match("JSON_PARSE_ERROR:(.+)") then
			return false, "Parse error: " .. result:match("JSON_PARSE_ERROR:(.+)")
		end
	end

	return false, "JSON test failed"
end

-- Auto-setup filetype detection
local function setup_filetype_detection()
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

-- Auto-setup user commands
local function setup_user_commands()
	vim.api.nvim_create_user_command("TclCheck", M.syntax_check, {
		desc = "Check TCL syntax of current file",
	})

	vim.api.nvim_create_user_command("TclInfo", M.show_info, {
		desc = "Show TCL system information",
	})

	vim.api.nvim_create_user_command("TclJsonTest", M.test_json, {
		desc = "Test JSON package functionality",
	})

	vim.api.nvim_create_user_command("TclLspStatus", function()
		local info = get_tcl_info(config.tclsh_cmd)
		if info then
			local status = string.format(
				[[
TCL LSP Status:
  Tcl: %s (%s)
  JSON: %s
  Command: %s
  Auto-detection: %s
]],
				info.tcl_version or "unknown",
				info.tcl_executable or "unknown",
				info.json_version or "not available",
				config.tclsh_cmd,
				config.tclsh_cmd == "auto" and "enabled" or "disabled"
			)
			vim.notify(status, vim.log.levels.INFO)
		end
	end, { desc = "Show TCL LSP status" })
end

-- Auto-setup keymaps and buffer-local settings
local function setup_buffer_autocmds()
	local tcl_group = vim.api.nvim_create_augroup("TclLSP", { clear = true })

	vim.api.nvim_create_autocmd("FileType", {
		pattern = "tcl",
		group = tcl_group,
		callback = function(ev)
			-- Set TCL-specific buffer options
			vim.opt_local.commentstring = "# %s"
			vim.opt_local.expandtab = true
			vim.opt_local.shiftwidth = 4
			vim.opt_local.tabstop = 4
			vim.opt_local.softtabstop = 4

			-- Set up keymaps if configured
			if config.keymaps then
				local opts = { buffer = ev.buf, silent = true }

				if config.keymaps.syntax_check then
					vim.keymap.set(
						"n",
						config.keymaps.syntax_check,
						M.syntax_check,
						vim.tbl_extend("force", opts, { desc = "TCL Syntax Check" })
					)
				end

				if config.keymaps.hover then
					vim.keymap.set(
						"n",
						config.keymaps.hover,
						vim.lsp.buf.hover,
						vim.tbl_extend("force", opts, { desc = "TCL Hover Documentation" })
					)
				end

				if config.keymaps.goto_definition then
					vim.keymap.set(
						"n",
						config.keymaps.goto_definition,
						vim.lsp.buf.definition,
						vim.tbl_extend("force", opts, { desc = "TCL Go to Definition" })
					)
				end

				if config.keymaps.find_references then
					vim.keymap.set(
						"n",
						config.keymaps.find_references,
						vim.lsp.buf.references,
						vim.tbl_extend("force", opts, { desc = "TCL Find References" })
					)
				end

				if config.keymaps.document_symbols then
					vim.keymap.set(
						"n",
						config.keymaps.document_symbols,
						vim.lsp.buf.document_symbol,
						vim.tbl_extend("force", opts, { desc = "TCL Document Symbols" })
					)
				end

				if config.keymaps.workspace_symbols then
					vim.keymap.set(
						"n",
						config.keymaps.workspace_symbols,
						vim.lsp.buf.workspace_symbol,
						vim.tbl_extend("force", opts, { desc = "TCL Workspace Symbols" })
					)
				end
			end

			-- Additional convenience keymaps
			local buf_opts = { buffer = ev.buf, silent = true }
			vim.keymap.set("n", "<leader>ti", M.show_info, vim.tbl_extend("force", buf_opts, { desc = "TCL Info" }))
			vim.keymap.set(
				"n",
				"<leader>tj",
				M.test_json,
				vim.tbl_extend("force", buf_opts, { desc = "Test TCL JSON" })
			)
			vim.keymap.set(
				"n",
				"<leader>ts",
				M.syntax_check,
				vim.tbl_extend("force", buf_opts, { desc = "TCL Syntax Check" })
			)
		end,
	})

	-- Auto syntax check on save
	if config.syntax_check_on_save then
		vim.api.nvim_create_autocmd("BufWritePost", {
			pattern = "*.tcl",
			group = tcl_group,
			callback = function()
				-- Small delay to ensure file is written
				vim.defer_fn(function()
					M.syntax_check()
				end, 100)
			end,
		})
	end

	-- Auto syntax check on change (if enabled)
	if config.syntax_check_on_change then
		vim.api.nvim_create_autocmd("TextChanged", {
			pattern = "*.tcl",
			group = tcl_group,
			callback = function()
				-- Debounced syntax check
				vim.defer_fn(function()
					M.syntax_check()
				end, 500)
			end,
		})
	end
end

-- Public functions
function M.syntax_check()
	local file_path = vim.api.nvim_buf_get_name(0)
	if not file_path or file_path == "" then
		vim.notify("No file to check", vim.log.levels.WARN)
		return
	end

	local success, message = check_syntax(file_path, config.tclsh_cmd)

	if success then
		vim.notify("✅ " .. message, vim.log.levels.INFO)
	else
		vim.notify("❌ " .. message, vim.log.levels.ERROR)
	end
end

function M.show_info()
	local info = get_tcl_info(config.tclsh_cmd)
	if not info then
		vim.notify("Failed to get Tcl info", vim.log.levels.ERROR)
		return
	end

	local info_text = string.format(
		[[
Tcl Version: %s
Executable: %s
Library: %s
JSON Package: %s
Library Paths: %d entries
]],
		info.tcl_version or "unknown",
		info.tcl_executable or "unknown",
		info.tcl_library or "unknown",
		info.json_version or "not available",
		#info.auto_path
	)

	vim.notify(info_text, vim.log.levels.INFO)
end

function M.test_json()
	local success, result = test_json_functionality(config.tclsh_cmd)

	if success then
		vim.notify("✅ JSON test passed\nResult: " .. result, vim.log.levels.INFO)
	else
		vim.notify("❌ JSON test failed: " .. result, vim.log.levels.ERROR)
	end
end

-- Export the module
return M
