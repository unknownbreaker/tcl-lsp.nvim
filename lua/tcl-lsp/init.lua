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

	vim.api.nvim_create_user_command("TclLspDebug", function()
		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify(err or "No file to debug", vim.log.levels.WARN)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()
		local symbols = tcl.debug_symbols(file_path, tclsh_cmd)

		if symbols and #symbols > 0 then
			utils.notify("Found " .. #symbols .. " symbols. Check :messages for details.", vim.log.levels.INFO)
		else
			utils.notify("No symbols found! Check :messages for debug info.", vim.log.levels.WARN)
		end
	end, {
		desc = "Debug TCL symbol analysis",
	})

	-- Test cross-file definition finding
	vim.api.nvim_create_user_command("TclTestCrossFile", function()
		local navigation = require("tcl-lsp.navigation")
		local semantic = require("tcl-lsp.semantic")
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file to test: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		local word, word_err = utils.get_word_under_cursor()
		if not word then
			utils.notify("No symbol under cursor: " .. (word_err or "unknown"), vim.log.levels.ERROR)
			return
		end

		utils.notify("Testing cross-file analysis for '" .. word .. "'...", vim.log.levels.INFO)

		-- Test 1: Build source dependencies
		local tclsh_cmd = config.get_tclsh_cmd()
		local dependencies = semantic.build_source_dependencies(file_path, tclsh_cmd)

		utils.notify(string.format("Found %d dependent files:", #dependencies), vim.log.levels.INFO)
		for i, dep in ipairs(dependencies) do
			utils.notify(string.format("  %d. %s", i, dep), vim.log.levels.INFO)
		end

		-- Test 2: Workspace symbol index
		if config.should_index_workspace_symbols() then
			local candidates, index = semantic.find_workspace_symbol_candidates(word, file_path, tclsh_cmd)

			utils.notify(
				string.format("Workspace index: %d files, %d total symbols", index.file_count, index.total_symbols),
				vim.log.levels.INFO
			)

			if #candidates > 0 then
				utils.notify(string.format("Found %d candidates for '%s':", #candidates, word), vim.log.levels.INFO)
				for i, candidate in ipairs(candidates) do
					local symbol = candidate.symbol
					local file_short = vim.fn.fnamemodify(symbol.source_file, ":t")
					utils.notify(
						string.format(
							"  %d. %s '%s' in %s at line %d (score: %d, %s)",
							i,
							symbol.type,
							symbol.name,
							file_short,
							symbol.line,
							candidate.score,
							candidate.match_type
						),
						vim.log.levels.INFO
					)
				end
			else
				utils.notify("No candidates found in workspace index", vim.log.levels.WARN)
			end
		end

		-- Test 3: Enhanced navigation
		local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
		local workspace_matches, searched_files =
			navigation.find_definition_across_workspace(word, file_path, cursor_line)

		utils.notify(
			string.format(
				"Enhanced navigation searched %d files and found %d matches",
				#searched_files,
				#workspace_matches
			),
			vim.log.levels.INFO
		)

		if #workspace_matches > 0 then
			for i, match in ipairs(workspace_matches) do
				local file_short = vim.fn.fnamemodify(match.file, ":t")
				utils.notify(
					string.format(
						"  %d. %s '%s' in %s at line %d (priority: %d, %s)",
						i,
						match.symbol.type,
						match.symbol.name,
						file_short,
						match.symbol.line,
						match.priority,
						match.method
					),
					vim.log.levels.INFO
				)
			end
		end

		-- Test 4: Cross-file references
		local references = semantic.find_references_across_workspace(word, file_path, tclsh_cmd)

		if references and #references > 0 then
			utils.notify(string.format("Found %d cross-file references:", #references), vim.log.levels.INFO)

			local ref_files = {}
			for _, ref in ipairs(references) do
				local file_short = vim.fn.fnamemodify(ref.source_file, ":t")
				if not ref_files[file_short] then
					ref_files[file_short] = 0
				end
				ref_files[file_short] = ref_files[file_short] + 1
			end

			for file_short, count in pairs(ref_files) do
				utils.notify(string.format("  %s: %d references", file_short, count), vim.log.levels.INFO)
			end
		else
			utils.notify("No cross-file references found", vim.log.levels.WARN)
		end

		-- Summary
		utils.notify("Cross-file analysis test complete!", vim.log.levels.INFO)
	end, {
		desc = "Test cross-file definition and reference finding",
	})

	-- Enhanced goto definition command that shows what it's doing
	vim.api.nvim_create_user_command("TclGotoDefinitionVerbose", function()
		local navigation = require("tcl-lsp.navigation")
		local utils = require("tcl-lsp.utils")

		local word, err = utils.get_word_under_cursor()
		if not word then
			utils.notify("No symbol under cursor: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		utils.notify("Searching for definition of '" .. word .. "'...", vim.log.levels.INFO)

		-- Use the enhanced goto definition with verbose output
		navigation.goto_definition()
	end, {
		desc = "Go to definition with verbose output",
	})

	-- Command to show workspace statistics
	vim.api.nvim_create_user_command("TclWorkspaceStats", function()
		local semantic = require("tcl-lsp.semantic")
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file to analyze: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()
		local stats = semantic.get_workspace_stats(file_path, tclsh_cmd)

		local stats_msg = string.format(
			[[
TCL Workspace Statistics:
  Total files analyzed: %d
  Total symbols found: %d
  Namespaces: %d
  External dependencies: %d
  
Configuration:
  Cross-file analysis: %s
  Workspace search: %s
  Max files: %d
  Cache timeout: %d seconds
]],
			stats.total_files,
			stats.total_symbols,
			stats.namespaces,
			stats.external_dependencies,
			config.is_cross_file_analysis_enabled() and "enabled" or "disabled",
			config.is_workspace_search_enabled() and "enabled" or "disabled",
			config.get_cross_file_max_files(),
			config.get_cross_file_cache_timeout()
		)

		utils.notify(stats_msg, vim.log.levels.INFO)
	end, {
		desc = "Show TCL workspace analysis statistics",
	})

	-- Command to clear all caches and rebuild workspace index
	vim.api.nvim_create_user_command("TclRebuildWorkspace", function()
		local semantic = require("tcl-lsp.semantic")
		local tcl = require("tcl-lsp.tcl")
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")

		utils.notify("Clearing all caches and rebuilding workspace index...", vim.log.levels.INFO)

		-- Clear all caches
		semantic.invalidate_workspace_cache()
		tcl.clear_all_caches()

		-- Rebuild workspace index if we have a current file
		local file_path = utils.get_current_file_path()
		if file_path then
			local tclsh_cmd = config.get_tclsh_cmd()
			local index = semantic.build_workspace_symbol_index(file_path, tclsh_cmd)

			utils.notify(
				string.format("Workspace rebuilt: %d files, %d symbols", index.file_count, index.total_symbols),
				vim.log.levels.INFO
			)
		else
			utils.notify("Caches cleared. Open a TCL file to rebuild workspace index.", vim.log.levels.INFO)
		end
	end, {
		desc = "Clear caches and rebuild workspace symbol index",
	})

	-- Command to show files that would be analyzed for current workspace
	vim.api.nvim_create_user_command("TclShowWorkspaceFiles", function()
		local semantic = require("tcl-lsp.semantic")
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file to analyze: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()

		utils.notify("Analyzing workspace files for: " .. vim.fn.fnamemodify(file_path, ":t"), vim.log.levels.INFO)

		-- Get source dependencies
		local dependencies = semantic.build_source_dependencies(file_path, tclsh_cmd)
		utils.notify("Source dependencies (" .. #dependencies .. "):", vim.log.levels.INFO)
		for i, dep in ipairs(dependencies) do
			local relative_path = vim.fn.fnamemodify(dep, ":.")
			utils.notify("  " .. i .. ". " .. relative_path, vim.log.levels.INFO)
		end

		-- Get workspace search files
		local workspace_files = config.get_workspace_search_paths()
		utils.notify("Workspace search files (" .. #workspace_files .. "):", vim.log.levels.INFO)
		for i, file in ipairs(workspace_files) do
			if i <= 20 then -- Limit output
				local relative_path = vim.fn.fnamemodify(file, ":.")
				local is_dependency = vim.tbl_contains(dependencies, file)
				local marker = is_dependency and " (dependency)" or ""
				utils.notify("  " .. i .. ". " .. relative_path .. marker, vim.log.levels.INFO)
			elseif i == 21 then
				utils.notify("  ... and " .. (#workspace_files - 20) .. " more files", vim.log.levels.INFO)
				break
			end
		end
	end, {
		desc = "Show files that would be analyzed in current workspace",
	})

	-- Command to benchmark cross-file analysis performance
	vim.api.nvim_create_user_command("TclBenchmarkCrossFile", function()
		local semantic = require("tcl-lsp.semantic")
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file to benchmark: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()

		utils.notify("Benchmarking cross-file analysis performance...", vim.log.levels.INFO)

		-- Benchmark 1: Source dependencies
		local start_time = vim.loop.hrtime()
		local dependencies = semantic.build_source_dependencies(file_path, tclsh_cmd)
		local deps_time = (vim.loop.hrtime() - start_time) / 1000000 -- Convert to ms

		-- Benchmark 2: Workspace symbol index
		start_time = vim.loop.hrtime()
		local index = semantic.build_workspace_symbol_index(file_path, tclsh_cmd)
		local index_time = (vim.loop.hrtime() - start_time) / 1000000

		-- Benchmark 3: Sample symbol search
		local test_symbols = { "set", "proc", "puts" } -- Common symbols
		local search_times = {}

		for _, symbol in ipairs(test_symbols) do
			start_time = vim.loop.hrtime()
			local candidates = semantic.find_workspace_symbol_candidates(symbol, file_path, tclsh_cmd)
			local search_time = (vim.loop.hrtime() - start_time) / 1000000
			table.insert(search_times, search_time)
		end

		local avg_search_time = 0
		for _, time in ipairs(search_times) do
			avg_search_time = avg_search_time + time
		end
		avg_search_time = avg_search_time / #search_times

		local benchmark_msg = string.format(
			[[
Cross-File Analysis Benchmark Results:
  Source dependencies: %.2f ms (%d files)
  Workspace index build: %.2f ms (%d files, %d symbols)
  Average symbol search: %.2f ms
  
Performance Assessment:
  %s
]],
			deps_time,
			#dependencies,
			index_time,
			index.file_count,
			index.total_symbols,
			avg_search_time,
			(index_time < 1000 and avg_search_time < 100) and "✅ Good performance"
				or (index_time < 3000 and avg_search_time < 300) and "⚠️ Moderate performance"
				or "❌ Slow performance - consider reducing workspace scope"
		)

		utils.notify(benchmark_msg, vim.log.levels.INFO)
	end, {
		desc = "Benchmark cross-file analysis performance",
	})

	-- Test symbol analysis in current file
	vim.api.nvim_create_user_command("TclDebugSymbols", function()
		local utils = require("tcl-lsp.utils")
		local tcl = require("tcl-lsp.tcl")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file to analyze: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

		if not symbols then
			utils.notify("Failed to analyze file", vim.log.levels.ERROR)
			return
		end

		utils.notify("Found " .. #symbols .. " symbols in current file:", vim.log.levels.INFO)
		for i, symbol in ipairs(symbols) do
			local qualified_info = symbol.qualified_name and (" -> " .. symbol.qualified_name) or ""
			local scope_info = symbol.scope and (" [" .. symbol.scope .. "]") or ""
			local namespace_info = symbol.namespace_context and (" {" .. symbol.namespace_context .. "}") or ""

			utils.notify(
				string.format(
					"  %d. %s '%s'%s%s%s at line %d",
					i,
					symbol.type,
					symbol.name,
					qualified_info,
					scope_info,
					namespace_info,
					symbol.line
				),
				vim.log.levels.INFO
			)
		end
	end, {
		desc = "Debug symbols in current file",
	})

	-- Test file discovery
	vim.api.nvim_create_user_command("TclDebugFiles", function()
		local navigation = require("tcl-lsp.navigation")
		navigation.debug_file_discovery()
	end, {
		desc = "Debug file discovery for workspace search",
	})

	-- Test workspace search for a specific symbol
	vim.api.nvim_create_user_command("TclDebugSearch", function(opts)
		local symbol_name = opts.args
		if not symbol_name or symbol_name == "" then
			vim.ui.input({ prompt = "Symbol to search for: " }, function(input)
				if input and input ~= "" then
					M.debug_workspace_search(input)
				end
			end)
			return
		end

		local function debug_workspace_search(search_symbol)
			local utils = require("tcl-lsp.utils")
			local navigation = require("tcl-lsp.navigation")
			local config = require("tcl-lsp.config")

			local file_path, err = utils.get_current_file_path()
			if not file_path then
				utils.notify("No file to search from: " .. (err or "unknown"), vim.log.levels.ERROR)
				return
			end

			local tclsh_cmd = config.get_tclsh_cmd()

			utils.notify("DEBUG: Searching workspace for '" .. search_symbol .. "'", vim.log.levels.INFO)
			navigation.search_workspace_for_definition_comprehensive(search_symbol, file_path, tclsh_cmd)
		end

		debug_workspace_search(symbol_name)
	end, {
		desc = "Debug workspace search for specific symbol",
		nargs = "?",
	})

	-- Test symbol matching
	vim.api.nvim_create_user_command("TclDebugMatch", function()
		local utils = require("tcl-lsp.utils")

		local word, err = utils.get_word_under_cursor()
		if not word then
			utils.notify("No symbol under cursor: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		-- Test different symbol matching scenarios
		local test_symbols = {
			word, -- exact
			"myns::" .. word, -- namespace qualified
			word .. "_test", -- partial
			"other::" .. word, -- different namespace
			string.upper(word), -- case different
		}

		utils.notify("Testing symbol matching for '" .. word .. "':", vim.log.levels.INFO)

		for i, test_symbol in ipairs(test_symbols) do
			local matches = utils.symbols_match(test_symbol, word)
			utils.notify(
				string.format("  %d. '%s' matches '%s': %s", i, test_symbol, word, matches and "YES" or "NO"),
				vim.log.levels.INFO
			)
		end
	end, {
		desc = "Debug symbol matching logic",
	})

	-- Test semantic dependency analysis
	vim.api.nvim_create_user_command("TclDebugDeps", function()
		local utils = require("tcl-lsp.utils")
		local semantic = require("tcl-lsp.semantic")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file to analyze: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()

		if semantic and semantic.build_source_dependencies then
			local dependencies = semantic.build_source_dependencies(file_path, tclsh_cmd)

			utils.notify("Source dependencies for " .. vim.fn.fnamemodify(file_path, ":t") .. ":", vim.log.levels.INFO)
			for i, dep in ipairs(dependencies) do
				local relative_path = vim.fn.fnamemodify(dep, ":.")
				local exists = utils.file_exists(dep) and "✓" or "✗"
				utils.notify(string.format("  %d. %s %s", i, exists, relative_path), vim.log.levels.INFO)
			end
		else
			utils.notify("Semantic dependency analysis not available", vim.log.levels.WARN)
		end
	end, {
		desc = "Debug source dependencies",
	})

	-- All-in-one comprehensive test
	vim.api.nvim_create_user_command("TclDebugAll", function()
		local utils = require("tcl-lsp.utils")

		utils.notify("🔍 Starting comprehensive TCL LSP debug...", vim.log.levels.INFO)

		-- Test 1: Current file symbols
		vim.cmd("TclDebugSymbols")

		-- Test 2: File discovery
		vim.cmd("TclDebugFiles")

		-- Test 3: Dependencies
		vim.cmd("TclDebugDeps")

		-- Test 4: Symbol under cursor
		local word, err = utils.get_word_under_cursor()
		if word then
			utils.notify("🎯 Testing workspace search for '" .. word .. "'...", vim.log.levels.INFO)
			vim.cmd("TclDebugSearch " .. word)
		else
			utils.notify("No symbol under cursor to test search", vim.log.levels.WARN)
		end

		utils.notify("✅ Debug complete!", vim.log.levels.INFO)
	end, {
		desc = "Run all TCL LSP debug tests",
	})

	-- Quick goto definition with debug output
	vim.api.nvim_create_user_command("TclGotoDebug", function()
		local utils = require("tcl-lsp.utils")
		local navigation = require("tcl-lsp.navigation")

		local word, err = utils.get_word_under_cursor()
		if not word then
			utils.notify("No symbol under cursor: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		utils.notify("🎯 Debug goto definition for '" .. word .. "'", vim.log.levels.INFO)

		-- This will use the fixed navigation with debug output
		navigation.goto_definition()
	end, {
		desc = "Go to definition with debug output",
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
		utils.notify(
			"❌ TCL LSP: Failed to initialize TCL environment: " .. (tcl_err or "unknown error"),
			vim.log.levels.ERROR
		)
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
