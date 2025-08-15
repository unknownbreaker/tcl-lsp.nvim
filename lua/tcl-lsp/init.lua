local config = require("tcl-lsp.config")
local utils = require("tcl-lsp.utils")
local tcl = require("tcl-lsp.tcl")
local syntax = require("tcl-lsp.syntax")
local navigation = require("tcl-lsp.navigation")
local symbols = require("tcl-lsp.symbols")

local M = {}

-- Auto-setup user commands
local function setup_user_commands()
	vim.api.nvim_create_user_command("TclCheck", function()
		syntax.syntax_check_current_buffer()
	end, {
		desc = "Check TCL syntax of current file",
	})

	vim.api.nvim_create_user_command("TclInfo", function()
		M.show_info()
	end, {
		desc = "Show TCL system information",
	})

	vim.api.nvim_create_user_command("TclJsonTest", function()
		M.test_json()
	end, {
		desc = "Test JSON package functionality",
	})

	vim.api.nvim_create_user_command("TclSymbols", function()
		symbols.document_symbols()
	end, {
		desc = "Show TCL symbols in current file",
	})

	vim.api.nvim_create_user_command("TclWorkspaceSymbols", function(opts)
		if opts.args and opts.args ~= "" then
			symbols.search_workspace_symbols(opts.args)
		else
			symbols.workspace_symbols()
		end
	end, {
		desc = "Search TCL symbols in workspace",
		nargs = "?",
	})

	vim.api.nvim_create_user_command("TclProcedures", function()
		symbols.list_procedures()
	end, {
		desc = "List all procedures in current file",
	})

	vim.api.nvim_create_user_command("TclVariables", function()
		symbols.list_variables()
	end, {
		desc = "List all variables in current file",
	})

	vim.api.nvim_create_user_command("TclNamespaces", function()
		symbols.list_namespaces()
	end, {
		desc = "List all namespaces in current file",
	})

	vim.api.nvim_create_user_command("TclFuzzySymbols", function()
		symbols.symbol_picker()
	end, {
		desc = "Fuzzy search for symbols",
	})

	vim.api.nvim_create_user_command("TclLspStatus", function()
		M.show_status()
	end, {
		desc = "Show TCL LSP status",
	})

	vim.api.nvim_create_user_command("TclLspReload", function()
		M.reload()
	end, {
		desc = "Reload TCL LSP configuration",
	})

	vim.api.nvim_create_user_command("TclLspCache", function(opts)
		if opts.args == "clear" then
			tcl.clear_all_caches()
			utils.notify("✅ TCL LSP: All caches cleared", vim.log.levels.INFO)
		elseif opts.args == "stats" then
			local stats = tcl.get_cache_stats()
			local stats_msg = string.format(
				[[
TCL LSP Cache Statistics:
  File cache entries: %d
  Resolution cache entries: %d
  Estimated memory usage: %s
]],
				stats.file_cache_entries,
				stats.resolution_cache_entries,
				stats.total_memory_usage
			)
			utils.notify(stats_msg, vim.log.levels.INFO)
		else
			utils.notify("Usage: :TclLspCache [clear|stats]", vim.log.levels.INFO)
		end
	end, {
		desc = "Manage TCL LSP caches (clear|stats)",
		nargs = "?",
	})
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

			-- Set up navigation keymaps
			if config.is_symbol_navigation_enabled() then
				navigation.setup_buffer_keymaps(ev.buf)
				symbols.setup_buffer_keymaps(ev.buf)
			end

			-- Set up syntax checking keymap
			local keymaps = config.get_keymaps()
			if keymaps.syntax_check then
				utils.set_buffer_keymap(
					"n",
					keymaps.syntax_check,
					syntax.syntax_check_current_buffer,
					{ desc = "TCL Syntax Check" },
					ev.buf
				)
			end

			-- Additional convenience keymaps
			utils.set_buffer_keymap("n", "<leader>ti", M.show_info, { desc = "TCL Info" }, ev.buf)
			utils.set_buffer_keymap("n", "<leader>tj", M.test_json, { desc = "Test TCL JSON" }, ev.buf)
			utils.set_buffer_keymap(
				"n",
				"<leader>ts",
				syntax.syntax_check_current_buffer,
				{ desc = "TCL Syntax Check" },
				ev.buf
			)
		end,
	})

	-- Set up syntax checking autocmds
	syntax.setup_autocmds()
end

-- Initialize TCL environment
local function initialize_tcl_environment(tclsh_cmd)
	-- Auto-detect the best tclsh if set to "auto" or not specified
	if tclsh_cmd == "auto" or tclsh_cmd == "tclsh" then
		local best_tclsh, version_or_error = utils.find_best_tclsh()
		if best_tclsh then
			config.set_value("tclsh_cmd", best_tclsh)
			utils.notify("✅ TCL LSP: Found " .. best_tclsh .. " with JSON " .. version_or_error, vim.log.levels.INFO)
			return best_tclsh, version_or_error
		else
			utils.notify("❌ TCL LSP: No suitable Tcl installation found: " .. version_or_error, vim.log.levels.ERROR)
			utils.notify("💡 Try installing: brew install tcl-tk tcllib", vim.log.levels.INFO)
			return nil, version_or_error
		end
	else
		-- Verify user-specified tclsh
		local has_tcllib, version_or_error = utils.check_tcllib_availability(tclsh_cmd)
		if not has_tcllib then
			utils.notify("❌ TCL LSP: Specified tclsh doesn't have tcllib: " .. version_or_error, vim.log.levels.ERROR)
			return nil, version_or_error
		else
			utils.notify("✅ TCL LSP: Using " .. tclsh_cmd .. " with JSON " .. version_or_error, vim.log.levels.INFO)
			return tclsh_cmd, version_or_error
		end
	end
end

-- Main setup function
function M.setup(user_config)
	-- Setup configuration
	local cfg = config.setup(user_config)

	-- Validate configuration
	local valid, errors = config.validate()
	if not valid then
		utils.notify("❌ TCL LSP: Configuration errors:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
		return
	end

	-- Initialize TCL environment
	local tclsh_cmd, tcl_info = initialize_tcl_environment(cfg.tclsh_cmd)
	if not tclsh_cmd then
		return
	end

	-- Test TCL environment
	local tcl_ok, tcl_err = tcl.initialize_tcl_environment(tclsh_cmd)
	if not tcl_ok then
		utils.notify("❌ TCL LSP: Failed to initialize TCL environment: " .. tcl_err, vim.log.levels.ERROR)
		return
	end

	-- Configure diagnostics globally if enabled
	if config.is_diagnostics_enabled() then
		vim.diagnostic.config(config.get_diagnostic_config())
	end

	-- Auto-setup everything if enabled (default: true)
	if config.should_auto_setup_filetypes() then
		utils.setup_filetype_detection()
	end

	if config.should_auto_setup_commands() then
		setup_user_commands()
	end

	if config.should_auto_setup_autocmds() then
		setup_buffer_autocmds()
	end

	-- Show success message with quick start info
	local success_msg = string.format(
		[[
🎉 TCL LSP ready! Quick commands:
  :TclCheck - Check syntax
  :TclInfo - System info  
  :TclJsonTest - Test JSON
  :TclSymbols - Document symbols
  :TclWorkspaceSymbols - Search workspace
  %s - Syntax check (in .tcl files)
  %s - Hover docs (in .tcl files)
  %s - Go to definition (in .tcl files)
]],
		cfg.keymaps.syntax_check or "<leader>tc",
		cfg.keymaps.hover or "K",
		cfg.keymaps.goto_definition or "gd"
	)

	utils.notify(success_msg, vim.log.levels.INFO)
end

-- Public API functions
function M.syntax_check()
	syntax.syntax_check_current_buffer()
end

function M.show_info()
	local tclsh_cmd = config.get_tclsh_cmd()
	local info = tcl.get_tcl_info(tclsh_cmd)
	if not info then
		utils.notify("Failed to get Tcl info", vim.log.levels.ERROR)
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

	utils.notify(info_text, vim.log.levels.INFO)
end

function M.test_json()
	local tclsh_cmd = config.get_tclsh_cmd()
	local success, result = tcl.test_json_functionality(tclsh_cmd)

	if success then
		utils.notify("✅ JSON test passed\nResult: " .. result, vim.log.levels.INFO)
	else
		utils.notify("❌ JSON test failed: " .. result, vim.log.levels.ERROR)
	end
end

function M.show_status()
	local cfg = config.get()
	local tclsh_cmd = cfg.tclsh_cmd
	local info = tcl.get_tcl_info(tclsh_cmd)

	local status_info = {
		"TCL LSP Status:",
		"  Configuration: " .. (cfg and "loaded" or "not loaded"),
		"  TCL Command: " .. (tclsh_cmd or "unknown"),
		"  Auto-detection: " .. (cfg.tclsh_cmd == "auto" and "enabled" or "disabled"),
	}

	if info then
		table.insert(status_info, "  TCL Version: " .. (info.tcl_version or "unknown"))
		table.insert(status_info, "  TCL Executable: " .. (info.tcl_executable or "unknown"))
		table.insert(status_info, "  JSON Support: " .. (info.json_version or "not available"))
	end

	table.insert(status_info, "")
	table.insert(status_info, "Features:")
	table.insert(status_info, "  Hover: " .. (cfg.hover and "enabled" or "disabled"))
	table.insert(status_info, "  Diagnostics: " .. (cfg.diagnostics and "enabled" or "disabled"))
	table.insert(status_info, "  Symbol Navigation: " .. (cfg.symbol_navigation and "enabled" or "disabled"))
	table.insert(status_info, "  Syntax Check on Save: " .. (cfg.syntax_check_on_save and "enabled" or "disabled"))

	utils.notify(table.concat(status_info, "\n"), vim.log.levels.INFO)
end

function M.reload()
	-- Clear any existing autocmds
	vim.api.nvim_clear_autocmds({ group = "TclLSP" })
	vim.api.nvim_clear_autocmds({ group = "TclLSP-Syntax" })

	-- Clear any existing user commands
	pcall(vim.api.nvim_del_user_command, "TclCheck")
	pcall(vim.api.nvim_del_user_command, "TclInfo")
	pcall(vim.api.nvim_del_user_command, "TclJsonTest")
	pcall(vim.api.nvim_del_user_command, "TclSymbols")
	pcall(vim.api.nvim_del_user_command, "TclWorkspaceSymbols")
	pcall(vim.api.nvim_del_user_command, "TclProcedures")
	pcall(vim.api.nvim_del_user_command, "TclVariables")
	pcall(vim.api.nvim_del_user_command, "TclNamespaces")
	pcall(vim.api.nvim_del_user_command, "TclFuzzySymbols")
	pcall(vim.api.nvim_del_user_command, "TclLspStatus")
	pcall(vim.api.nvim_del_user_command, "TclLspReload")

	-- Reload configuration with current settings
	local current_config = config.get()
	M.setup(current_config)

	utils.notify("✅ TCL LSP reloaded successfully", vim.log.levels.INFO)
end

-- Get current configuration (for external access)
function M.get_config()
	return config.get()
end

-- Get symbol under cursor (for external integrations)
function M.get_symbol_under_cursor()
	return symbols.get_symbol_under_cursor()
end

-- Find symbol definition (for external integrations)
function M.find_definition(symbol_name, file_path)
	file_path = file_path or utils.get_current_file_path()
	if not file_path then
		return nil, "No file specified"
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	local file_symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

	if not file_symbols then
		return nil, "Failed to analyze file"
	end

	for _, symbol in ipairs(file_symbols) do
		if symbol.name == symbol_name then
			return symbol, nil
		end
	end

	return nil, "Symbol not found"
end

-- Find symbol references (for external integrations)
function M.find_references(symbol_name, file_path)
	file_path = file_path or utils.get_current_file_path()
	if not file_path then
		return nil, "No file specified"
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	return tcl.find_symbol_references(file_path, symbol_name, tclsh_cmd)
end

-- Analyze file and return symbols (for external integrations)
function M.analyze_file(file_path)
	if not file_path then
		return nil, "No file specified"
	end

	local tclsh_cmd = config.get_tclsh_cmd()
	return tcl.analyze_tcl_file(file_path, tclsh_cmd)
end

-- Check if TCL LSP is properly initialized
function M.is_initialized()
	local cfg = config.get()
	return cfg and cfg.tclsh_cmd and cfg.tclsh_cmd ~= "auto"
end

-- Get version information
function M.get_version()
	return {
		version = "1.0.0",
		tcl_lsp = true,
		features = {
			hover = true,
			goto_definition = true,
			find_references = true,
			document_symbols = true,
			workspace_symbols = true,
			syntax_checking = true,
			diagnostics = true,
		},
	}
end

-- Compatibility layer for the original monolithic API
M.find_references = function()
	navigation.find_references()
end

M.document_symbols = function()
	symbols.document_symbols()
end

M.workspace_symbols = function()
	symbols.workspace_symbols()
end

M.smart_goto_tcl_definition = function()
	navigation.goto_definition()
end

M.smart_tcl_hover = function()
	navigation.hover()
end

-- Export the module
return M
