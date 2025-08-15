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

	vim.api.nvim_create_user_command("TclTestCorrected", function()
		local utils = require("tcl-lsp.utils")
		local tcl = require("tcl-lsp.tcl")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file to analyze: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		utils.notify("Testing corrected TCL analysis on: " .. vim.fn.fnamemodify(file_path, ":t"), vim.log.levels.INFO)

		local tclsh_cmd = config.get_tclsh_cmd()

		-- Clear cache to force fresh analysis
		tcl.invalidate_cache(file_path)

		-- Run the corrected analysis
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

		if not symbols then
			utils.notify("❌ Analysis failed - check :messages for details", vim.log.levels.ERROR)
			return
		end

		if #symbols == 0 then
			utils.notify("⚠️  No symbols found - file might be empty or have syntax issues", vim.log.levels.WARN)

			-- Show first few lines of file for debugging
			local lines = vim.api.nvim_buf_get_lines(0, 0, 10, false)
			utils.notify("First 10 lines of file:", vim.log.levels.INFO)
			for i, line in ipairs(lines) do
				if line:trim() ~= "" and not line:match("^%s*#") then
					utils.notify(string.format("  %d: %s", i, line), vim.log.levels.INFO)
				end
			end
			return
		end

		utils.notify("✅ Found " .. #symbols .. " symbols:", vim.log.levels.INFO)

		-- Group symbols by type for better display
		local by_type = {}
		for _, symbol in ipairs(symbols) do
			if not by_type[symbol.type] then
				by_type[symbol.type] = {}
			end
			table.insert(by_type[symbol.type], symbol)
		end

		-- Display grouped results
		for type_name, type_symbols in pairs(by_type) do
			utils.notify(string.format("  %s (%d):", type_name, #type_symbols), vim.log.levels.INFO)

			for i, symbol in ipairs(type_symbols) do
				local qualified_info = symbol.qualified_name and (" -> " .. symbol.qualified_name) or ""
				utils.notify(
					string.format("    %d. '%s'%s at line %d", i, symbol.name, qualified_info, symbol.line),
					vim.log.levels.INFO
				)

				if i >= 5 then -- Limit output
					utils.notify(string.format("    ... and %d more", #type_symbols - 5), vim.log.levels.INFO)
					break
				end
			end
		end

		utils.notify("✅ Analysis completed successfully!", vim.log.levels.INFO)
	end, {
		desc = "Test the corrected TCL symbol analysis",
	})

	-- Test the specific file from your error
	vim.api.nvim_create_user_command("TclTestFile", function(opts)
		local file_path = opts.args
		if not file_path or file_path == "" then
			file_path =
				"/Users/rob.yang/Documents/Repos/FlightAware/22fa_web/packages/flightaware-main/ftrehose/trials.tcl"
		end

		if not vim.fn.filereadable(file_path) then
			utils.notify("File not readable: " .. file_path, vim.log.levels.ERROR)
			return
		end

		local utils = require("tcl-lsp.utils")
		local tcl = require("tcl-lsp.tcl")
		local config = require("tcl-lsp.config")

		utils.notify("Testing analysis on specific file: " .. vim.fn.fnamemodify(file_path, ":t"), vim.log.levels.INFO)

		local tclsh_cmd = config.get_tclsh_cmd()

		-- Test the TCL script directly
		local escaped_path = file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
		local test_script = string.format(
			[[
# Test script to verify file can be read and parsed
set file_path "%s"

puts "Testing file: $file_path"

if {[catch {
    set fp [open $file_path r]
    set content [read $fp]
    close $fp
} err]} {
    puts "ERROR: Cannot read file: $err"
    exit 1
}

set lines [split $content "\n"]
puts "File has [llength $lines] lines"

# Test parsing first 10 lines
set line_num 0
foreach line [lrange $lines 0 9] {
    incr line_num
    puts "Line $line_num: [string length $line] chars: [string range $line 0 50]..."
}

puts "SUCCESS: File parsed without errors"
]],
			escaped_path
		)

		local result, success = utils.execute_tcl_script(test_script, tclsh_cmd)

		if result and success then
			utils.notify("✅ File test passed:", vim.log.levels.INFO)
			for line in result:gmatch("[^\n]+") do
				utils.notify("  " .. line, vim.log.levels.INFO)
			end
		else
			utils.notify("❌ File test failed:", vim.log.levels.ERROR)
			utils.notify("Result: " .. (result or "nil"), vim.log.levels.ERROR)
		end
	end, {
		desc = "Test analysis on specific file",
		nargs = "?",
	})

	-- Test semantic analysis vs regex patterns
	vim.api.nvim_create_user_command("TclTestSemantic", function()
		local utils = require("tcl-lsp.utils")
		local tcl = require("tcl-lsp.tcl")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file to analyze: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()

		utils.notify("🧠 Testing TRUE semantic analysis (not regex patterns)...", vim.log.levels.INFO)

		-- Clear cache to force fresh analysis
		tcl.invalidate_cache(file_path)

		-- Run semantic analysis
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

		if not symbols then
			utils.notify("❌ Semantic analysis failed", vim.log.levels.ERROR)
			return
		end

		if #symbols == 0 then
			utils.notify("⚠️  No symbols found with semantic analysis", vim.log.levels.WARN)
			return
		end

		utils.notify("✅ Semantic analysis found " .. #symbols .. " symbols:", vim.log.levels.INFO)

		-- Group by method to show semantic vs other approaches
		local by_method = {}
		for _, symbol in ipairs(symbols) do
			local method = symbol.method or "unknown"
			if not by_method[method] then
				by_method[method] = {}
			end
			table.insert(by_method[method], symbol)
		end

		for method, method_symbols in pairs(by_method) do
			utils.notify(string.format("  %s method: %d symbols", method, #method_symbols), vim.log.levels.INFO)

			-- Show a few examples
			for i = 1, math.min(3, #method_symbols) do
				local symbol = method_symbols[i]
				local qualified_info = symbol.qualified_name and (" → " .. symbol.qualified_name) or ""
				utils.notify(
					string.format("    %s '%s'%s [%s]", symbol.type, symbol.name, qualified_info, symbol.scope),
					vim.log.levels.INFO
				)
			end

			if #method_symbols > 3 then
				utils.notify(string.format("    ... and %d more", #method_symbols - 3), vim.log.levels.INFO)
			end
		end
	end, {
		desc = "Test true semantic analysis (not regex)",
	})

	-- Test semantic vs regex on tricky TCL constructs
	vim.api.nvim_create_user_command("TclCreateSemanticTest", function()
		local tricky_tcl = [[
# This file tests tricky TCL constructs that regex patterns typically miss

# Dynamic procedure creation
set proc_name "dynamic_proc"
set proc_args {arg1 arg2}
set proc_body {
    puts "arg1: $arg1, arg2: $arg2"
    return [expr {$arg1 + $arg2}]
}
eval "proc $proc_name [list $proc_args] [list $proc_body]"

# Namespace with variable interpolation
set ns_name "test_namespace"
namespace eval $ns_name {
    variable count 0
    
    proc increment {{step 1}} {
        variable count
        incr count $step
        return $count
    }
    
    # Procedure with complex parameter patterns
    proc complex_proc {required {optional "default"} args} {
        variable count
        puts "Required: $required"
        puts "Optional: $optional" 
        puts "Args: $args"
        puts "Count: $count"
        
        # Variable assignment inside control structure
        if {$count > 5} {
            set status "high"
        } else {
            set status "low"
        }
        
        # Array operations
        array set local_array {key1 value1 key2 value2}
        
        # Dynamic variable names
        set var_name "dynamic_var"
        set $var_name "dynamic_value"
        
        return $status
    }
}

# Uplevel and upvar (advanced TCL constructs)
proc wrapper_proc {script} {
    set local_var "wrapper_value"
    uplevel 1 $script
}

proc upvar_test {var_name} {
    upvar $var_name local_ref
    set local_ref "modified_by_upvar"
}

# Complex namespace operations
namespace eval another_ns {
    namespace import ::${ns_name}::*
    
    proc call_imported {} {
        return [increment 2]
    }
}

# Runtime procedure modification
proc original_proc {arg} {
    return "original: $arg"
}

# This would be missed by regex but caught by semantic analysis
rename original_proc old_original_proc
proc original_proc {arg} {
    set result [old_original_proc $arg]
    return "modified: $result"
}

# Package with variable name
set package_name "json"
package require $package_name

# Source with computed filename
set config_dir "/etc/myapp"
set config_file "config.tcl"
source [file join $config_dir $config_file]
]]

		-- Create new buffer with tricky TCL
		vim.cmd("new")
		vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(tricky_tcl, "\n"))
		vim.bo.filetype = "tcl"

		local utils = require("tcl-lsp.utils")
		utils.notify("Created test file with tricky TCL constructs that regex typically misses:", vim.log.levels.INFO)
		utils.notify("- Dynamic procedure creation (line 5)", vim.log.levels.INFO)
		utils.notify("- Variable interpolation in namespaces (line 12)", vim.log.levels.INFO)
		utils.notify("- Complex parameter patterns (line 22)", vim.log.levels.INFO)
		utils.notify("- Variables in control structures (line 30)", vim.log.levels.INFO)
		utils.notify("- Dynamic variable names (line 38)", vim.log.levels.INFO)
		utils.notify("- Uplevel/upvar constructs (line 45)", vim.log.levels.INFO)
		utils.notify("- Runtime procedure modification (line 65)", vim.log.levels.INFO)
		utils.notify("", vim.log.levels.INFO)
		utils.notify("Try: :TclTestSemantic to see if semantic analysis catches these!", vim.log.levels.INFO)
	end, {
		desc = "Create test file with tricky TCL constructs",
	})

	-- Compare semantic vs regex analysis
	vim.api.nvim_create_user_command("TclCompareAnalysis", function()
		local utils = require("tcl-lsp.utils")
		local tcl = require("tcl-lsp.tcl")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file to analyze: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()

		utils.notify("🔬 Comparing semantic analysis vs regex patterns...", vim.log.levels.INFO)

		-- Clear cache
		tcl.invalidate_cache(file_path)

		-- Run semantic analysis
		local semantic_symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

		if not semantic_symbols then
			utils.notify("❌ Semantic analysis failed", vim.log.levels.ERROR)
			return
		end

		-- Count symbols by type and method
		local semantic_count = {}
		local regex_count = {}

		for _, symbol in ipairs(semantic_symbols) do
			local method = symbol.method or "unknown"
			if not semantic_count[symbol.type] then
				semantic_count[symbol.type] = 0
			end
			semantic_count[symbol.type] = semantic_count[symbol.type] + 1
		end

		utils.notify("📊 Analysis Results:", vim.log.levels.INFO)
		utils.notify("Semantic Analysis Results:", vim.log.levels.INFO)

		local total_semantic = 0
		for sym_type, count in pairs(semantic_count) do
			utils.notify(string.format("  %s: %d", sym_type, count), vim.log.levels.INFO)
			total_semantic = total_semantic + count
		end

		utils.notify(string.format("Total symbols found: %d", total_semantic), vim.log.levels.INFO)

		-- Show some advanced symbols that regex would miss
		utils.notify("", vim.log.levels.INFO)
		utils.notify("🎯 Advanced constructs detected (regex would miss these):", vim.log.levels.INFO)

		local advanced_found = false
		for _, symbol in ipairs(semantic_symbols) do
			-- Look for signs of advanced analysis
			if symbol.type == "parameter" and symbol.proc_context then
				utils.notify(
					string.format("  Parameter '%s' of procedure '%s'", symbol.name, symbol.proc_context),
					vim.log.levels.INFO
				)
				advanced_found = true
			elseif symbol.qualified_name and symbol.qualified_name ~= symbol.name then
				utils.notify(
					string.format("  Qualified symbol '%s' → '%s'", symbol.name, symbol.qualified_name),
					vim.log.levels.INFO
				)
				advanced_found = true
			elseif symbol.scope and symbol.scope ~= "global" then
				utils.notify(
					string.format("  Scoped %s '%s' [%s]", symbol.type, symbol.name, symbol.scope),
					vim.log.levels.INFO
				)
				advanced_found = true
			end
		end

		if not advanced_found then
			utils.notify("  No advanced constructs found (file may be simple)", vim.log.levels.INFO)
		end
	end, {
		desc = "Compare semantic analysis vs regex patterns",
	})

	-- Test semantic resolution specifically
	vim.api.nvim_create_user_command("TclTestSemanticResolution", function()
		local utils = require("tcl-lsp.utils")
		local tcl = require("tcl-lsp.tcl")
		local config = require("tcl-lsp.config")

		local word, err = utils.get_word_under_cursor()
		if not word then
			utils.notify("No symbol under cursor: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		local file_path, file_err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file: " .. (file_err or "unknown"), vim.log.levels.ERROR)
			return
		end

		local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
		local tclsh_cmd = config.get_tclsh_cmd()

		utils.notify("🧠 Testing SEMANTIC resolution for '" .. word .. "' (not regex)", vim.log.levels.INFO)

		-- Run semantic resolution
		local resolution = tcl.resolve_symbol(word, file_path, cursor_line, tclsh_cmd)

		if not resolution then
			utils.notify("❌ Semantic resolution failed", vim.log.levels.ERROR)
			return
		end

		-- Show semantic context
		local context = resolution.context
		utils.notify("📍 Semantic Context at cursor:", vim.log.levels.INFO)
		utils.notify("  Namespace: " .. (context.namespace or "::"), vim.log.levels.INFO)
		utils.notify("  Procedure: " .. (context.proc or "none"), vim.log.levels.INFO)

		if context.proc_params and #context.proc_params > 0 then
			utils.notify("  Parameters: " .. table.concat(context.proc_params, ", "), vim.log.levels.INFO)

			-- Check if current symbol is a parameter
			for _, param in ipairs(context.proc_params) do
				if param == word then
					utils.notify("  ✅ '" .. word .. "' IS a parameter!", vim.log.levels.INFO)
					break
				end
			end
		end

		-- Show semantic resolution results
		utils.notify("", vim.log.levels.INFO)
		utils.notify("🎯 Semantic Resolution Results:", vim.log.levels.INFO)

		for i, res in ipairs(resolution.resolutions) do
			local res_info = string.format("  %d. %s '%s' (priority: %d)", i, res.type, res.name, res.priority)

			if res.proc then
				res_info = res_info .. " [proc: " .. res.proc .. "]"
			end
			if res.namespace then
				res_info = res_info .. " [ns: " .. res.namespace .. "]"
			end

			utils.notify(res_info, vim.log.levels.INFO)
		end

		local method = resolution.method or "unknown"
		utils.notify("", vim.log.levels.INFO)
		utils.notify("Method used: " .. method, vim.log.levels.INFO)

		if method == "true_semantic" then
			utils.notify("✅ TRUE semantic resolution (not regex)!", vim.log.levels.INFO)
		else
			utils.notify("⚠️  May still be using regex patterns", vim.log.levels.WARN)
		end
	end, {
		desc = "Test semantic resolution for symbol under cursor",
	})

	-- Comprehensive semantic test
	vim.api.nvim_create_user_command("TclTestSemanticAll", function()
		local utils = require("tcl-lsp.utils")

		utils.notify("🧪 Running comprehensive semantic engine tests...", vim.log.levels.INFO)

		-- Test 1: Semantic analysis
		utils.notify("1️⃣ Testing semantic analysis...", vim.log.levels.INFO)
		vim.cmd("TclTestSemantic")

		-- Test 2: Semantic resolution
		utils.notify("2️⃣ Testing semantic resolution...", vim.log.levels.INFO)
		vim.cmd("TclTestSemanticResolution")

		-- Test 3: Comparison analysis
		utils.notify("3️⃣ Comparing with regex patterns...", vim.log.levels.INFO)
		vim.cmd("TclCompareAnalysis")

		utils.notify("✅ Semantic engine tests complete!", vim.log.levels.INFO)
		utils.notify("If you see 'true_semantic' methods, the semantic engine is working!", vim.log.levels.INFO)
	end, {
		desc = "Run all semantic engine tests",
	})

	-- Step-by-step goto definition debug
	vim.api.nvim_create_user_command("TclDebugGotoDef", function()
		local utils = require("tcl-lsp.utils")
		local tcl = require("tcl-lsp.tcl")
		local config = require("tcl-lsp.config")
		local navigation = require("tcl-lsp.navigation")

		utils.notify("🔍 Step-by-step goto definition debug", vim.log.levels.INFO)

		-- Step 1: Get symbol under cursor
		local word, err = utils.get_qualified_word_under_cursor()
		if not word then
			word, err = utils.get_word_under_cursor()
			if not word then
				utils.notify("❌ Step 1 FAILED: " .. (err or "No word under cursor"), vim.log.levels.ERROR)
				return
			end
		end
		utils.notify("✅ Step 1: Found symbol '" .. word .. "'", vim.log.levels.INFO)

		-- Step 2: Get current file
		local file_path, file_err = utils.get_current_file_path()
		if not file_path then
			utils.notify("❌ Step 2 FAILED: " .. (file_err or "No current file"), vim.log.levels.ERROR)
			return
		end
		utils.notify("✅ Step 2: Current file " .. vim.fn.fnamemodify(file_path, ":t"), vim.log.levels.INFO)

		-- Step 3: Analyze current file symbols
		local tclsh_cmd = config.get_tclsh_cmd()
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
		if not symbols then
			utils.notify("❌ Step 3 FAILED: Symbol analysis returned nil", vim.log.levels.ERROR)
			return
		end
		utils.notify("✅ Step 3: Found " .. #symbols .. " symbols in current file", vim.log.levels.INFO)

		if #symbols == 0 then
			utils.notify("⚠️  Step 3 WARNING: Zero symbols found - this is the problem!", vim.log.levels.WARN)
			utils.notify("Try :TclTestSemantic to debug symbol analysis", vim.log.levels.INFO)
			return
		end

		-- Step 4: Show symbols for debugging
		utils.notify("📋 Step 4: Symbols found:", vim.log.levels.INFO)
		for i = 1, math.min(10, #symbols) do
			local symbol = symbols[i]
			utils.notify(
				string.format(
					"  %d. %s '%s' at line %d [%s]",
					i,
					symbol.type,
					symbol.name,
					symbol.line,
					symbol.scope or "unknown"
				),
				vim.log.levels.INFO
			)
		end
		if #symbols > 10 then
			utils.notify(string.format("  ... and %d more symbols", #symbols - 10), vim.log.levels.INFO)
		end

		-- Step 5: Check if our target symbol exists in symbols
		local target_found = false
		local target_matches = {}
		for _, symbol in ipairs(symbols) do
			if symbol.name == word then
				target_found = true
				table.insert(target_matches, symbol)
			elseif utils.symbols_match and utils.symbols_match(symbol.name, word) then
				table.insert(target_matches, symbol)
			end
		end

		if target_found then
			utils.notify("✅ Step 5: Target symbol '" .. word .. "' found in symbols!", vim.log.levels.INFO)
			utils.notify("Exact matches:", vim.log.levels.INFO)
			for _, match in ipairs(target_matches) do
				utils.notify(
					string.format("  %s '%s' at line %d", match.type, match.name, match.line),
					vim.log.levels.INFO
				)
			end
		else
			utils.notify("❌ Step 5 FAILED: Target symbol '" .. word .. "' NOT found in symbols", vim.log.levels.ERROR)
			utils.notify("This is why goto definition fails!", vim.log.levels.ERROR)

			-- Show similar symbols for debugging
			local similar = {}
			for _, symbol in ipairs(symbols) do
				if symbol.name:lower():find(word:lower(), 1, true) then
					table.insert(similar, symbol)
				end
			end

			if #similar > 0 then
				utils.notify("Similar symbols found:", vim.log.levels.INFO)
				for _, sim in ipairs(similar) do
					utils.notify(
						string.format("  %s '%s' at line %d", sim.type, sim.name, sim.line),
						vim.log.levels.INFO
					)
				end
			end
			return
		end

		-- Step 6: Test symbol resolution
		local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
		local resolution = tcl.resolve_symbol(word, file_path, cursor_line, tclsh_cmd)

		if not resolution then
			utils.notify("❌ Step 6 FAILED: Symbol resolution returned nil", vim.log.levels.ERROR)
			return
		end
		utils.notify("✅ Step 6: Symbol resolution succeeded", vim.log.levels.INFO)

		if not resolution.resolutions or #resolution.resolutions == 0 then
			utils.notify("⚠️  Step 6 WARNING: No resolutions found", vim.log.levels.WARN)
		else
			utils.notify("Resolutions found:", vim.log.levels.INFO)
			for i, res in ipairs(resolution.resolutions) do
				utils.notify(
					string.format("  %d. %s '%s' priority %d", i, res.type, res.name, res.priority),
					vim.log.levels.INFO
				)
			end
		end

		-- Step 7: Test find_matching_symbols
		if navigation.find_matching_symbols then
			local matches = navigation.find_matching_symbols(symbols, resolution.resolutions or {}, word)

			if #matches == 0 then
				utils.notify("❌ Step 7 FAILED: find_matching_symbols returned no matches", vim.log.levels.ERROR)
				utils.notify("This is likely where goto definition fails!", vim.log.levels.ERROR)

				-- Debug the matching logic
				utils.notify("Debugging symbol matching:", vim.log.levels.INFO)
				for _, symbol in ipairs(symbols) do
					if symbol.name == word then
						utils.notify(
							string.format("  Symbol '%s' SHOULD match query '%s'", symbol.name, word),
							vim.log.levels.INFO
						)
					end
				end
			else
				utils.notify("✅ Step 7: find_matching_symbols found " .. #matches .. " matches", vim.log.levels.INFO)
				for _, match in ipairs(matches) do
					utils.notify(
						string.format(
							"  Match: %s '%s' at line %d",
							match.symbol.type,
							match.symbol.name,
							match.symbol.line
						),
						vim.log.levels.INFO
					)
				end
			end
		else
			utils.notify("❌ Step 7 FAILED: find_matching_symbols function not found", vim.log.levels.ERROR)
		end

		utils.notify("🎯 Debug complete! Check the failed steps above.", vim.log.levels.INFO)
	end, {
		desc = "Debug goto definition step by step",
	})

	-- Test symbol matching logic specifically
	vim.api.nvim_create_user_command("TclDebugMatching", function()
		local utils = require("tcl-lsp.utils")
		local tcl = require("tcl-lsp.tcl")
		local config = require("tcl-lsp.config")

		local word, err = utils.get_word_under_cursor()
		if not word then
			utils.notify("No symbol under cursor: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		local file_path, file_err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file: " .. (file_err or "unknown"), vim.log.levels.ERROR)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

		if not symbols or #symbols == 0 then
			utils.notify("No symbols to test matching against", vim.log.levels.ERROR)
			return
		end

		utils.notify("🔍 Testing symbol matching for '" .. word .. "'", vim.log.levels.INFO)

		-- Test different matching approaches
		local exact_matches = {}
		local fuzzy_matches = {}
		local utils_matches = {}

		for _, symbol in ipairs(symbols) do
			-- Exact match
			if symbol.name == word then
				table.insert(exact_matches, symbol)
			end

			-- Fuzzy match (contains)
			if symbol.name:lower():find(word:lower(), 1, true) then
				table.insert(fuzzy_matches, symbol)
			end

			-- Utils.symbols_match (if available)
			if utils.symbols_match and utils.symbols_match(symbol.name, word) then
				table.insert(utils_matches, symbol)
			end
		end

		utils.notify("Exact matches (" .. #exact_matches .. "):", vim.log.levels.INFO)
		for _, match in ipairs(exact_matches) do
			utils.notify(string.format("  %s '%s' at line %d", match.type, match.name, match.line), vim.log.levels.INFO)
		end

		utils.notify("Fuzzy matches (" .. #fuzzy_matches .. "):", vim.log.levels.INFO)
		for i = 1, math.min(5, #fuzzy_matches) do
			local match = fuzzy_matches[i]
			utils.notify(string.format("  %s '%s' at line %d", match.type, match.name, match.line), vim.log.levels.INFO)
		end

		if utils.symbols_match then
			utils.notify("Utils.symbols_match (" .. #utils_matches .. "):", vim.log.levels.INFO)
			for _, match in ipairs(utils_matches) do
				utils.notify(
					string.format("  %s '%s' at line %d", match.type, match.name, match.line),
					vim.log.levels.INFO
				)
			end
		else
			utils.notify("⚠️  utils.symbols_match function not available", vim.log.levels.WARN)
		end

		if #exact_matches == 0 and #fuzzy_matches == 0 and #utils_matches == 0 then
			utils.notify("❌ NO MATCHES FOUND - this explains goto definition failure!", vim.log.levels.ERROR)

			-- Show all symbols for reference
			utils.notify("All available symbols:", vim.log.levels.INFO)
			for i = 1, math.min(20, #symbols) do
				local symbol = symbols[i]
				utils.notify(string.format("  %s '%s'", symbol.type, symbol.name), vim.log.levels.INFO)
			end
		end
	end, {
		desc = "Debug symbol matching logic",
	})

	-- Test the complete goto definition flow with detailed logging
	vim.api.nvim_create_user_command("TclDebugGotoFlow", function()
		local utils = require("tcl-lsp.utils")
		local tcl = require("tcl-lsp.tcl")
		local config = require("tcl-lsp.config")
		local navigation = require("tcl-lsp.navigation")

		-- Override the goto_definition function temporarily with debug version
		local original_goto_definition = navigation.goto_definition

		navigation.goto_definition = function()
			utils.notify("🎯 DEBUG GOTO DEFINITION START", vim.log.levels.INFO)

			-- Step 1: Get word
			local word, err = utils.get_qualified_word_under_cursor()
			if not word then
				word, err = utils.get_word_under_cursor()
				if not word then
					utils.notify("DEBUG: No word found - " .. (err or "unknown"), vim.log.levels.ERROR)
					return
				end
			end
			utils.notify("DEBUG: Target word = '" .. word .. "'", vim.log.levels.INFO)

			-- Step 2: Get file
			local file_path, file_err = utils.get_current_file_path()
			if not file_path then
				utils.notify("DEBUG: No file - " .. (file_err or "unknown"), vim.log.levels.ERROR)
				return
			end
			utils.notify("DEBUG: File = " .. vim.fn.fnamemodify(file_path, ":t"), vim.log.levels.INFO)

			-- Step 3: Analyze symbols
			local tclsh_cmd = config.get_tclsh_cmd()
			local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
			if not symbols then
				utils.notify("DEBUG: Symbol analysis FAILED", vim.log.levels.ERROR)
				return
			end
			utils.notify("DEBUG: Found " .. #symbols .. " symbols", vim.log.levels.INFO)

			if #symbols == 0 then
				utils.notify("DEBUG: ZERO SYMBOLS - goto definition will fail here", vim.log.levels.ERROR)
				return
			end

			-- Step 4: Get cursor and resolve
			local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
			local resolution = tcl.resolve_symbol(word, file_path, cursor_line, tclsh_cmd)
			local matches = {}

			if resolution and resolution.resolutions then
				utils.notify(
					"DEBUG: Using smart resolution with " .. #resolution.resolutions .. " candidates",
					vim.log.levels.INFO
				)
				matches = navigation.find_matching_symbols(symbols, resolution.resolutions, word)
				utils.notify("DEBUG: Smart resolution found " .. #matches .. " matches", vim.log.levels.INFO)
			else
				utils.notify("DEBUG: Smart resolution failed or returned nil", vim.log.levels.WARN)
			end

			-- Step 5: Fallback matching
			if #matches == 0 then
				utils.notify("DEBUG: Trying fallback simple matching", vim.log.levels.INFO)
				for _, symbol in ipairs(symbols) do
					if symbol.name == word or (utils.symbols_match and utils.symbols_match(symbol.name, word)) then
						table.insert(matches, {
							symbol = symbol,
							priority = (symbol.name == word) and 10 or 5,
							resolution = { type = "fallback", name = word },
						})
					end
				end
				utils.notify("DEBUG: Fallback found " .. #matches .. " matches", vim.log.levels.INFO)
			end

			-- Step 6: Results
			if #matches == 0 then
				utils.notify("DEBUG: FINAL RESULT - NO MATCHES FOUND", vim.log.levels.ERROR)
				utils.notify("This is why goto definition says 'not found'", vim.log.levels.ERROR)
			else
				utils.notify("DEBUG: FINAL RESULT - " .. #matches .. " matches found", vim.log.levels.INFO)
				for _, match in ipairs(matches) do
					utils.notify(
						"DEBUG: Match - "
							.. match.symbol.type
							.. " '"
							.. match.symbol.name
							.. "' at line "
							.. match.symbol.line,
						vim.log.levels.INFO
					)
				end
			end

			utils.notify("🎯 DEBUG GOTO DEFINITION END", vim.log.levels.INFO)

			-- Now call the original function
			return original_goto_definition()
		end

		utils.notify("🔧 Goto definition override installed. Try 'gd' now.", vim.log.levels.INFO)
		utils.notify("The debug version will show exactly what's happening.", vim.log.levels.INFO)
	end, {
		desc = "Install debug version of goto definition",
	})

	-- Create a minimal working goto definition
	vim.api.nvim_create_user_command("TclSimpleGoto", function()
		local utils = require("tcl-lsp.utils")
		local tcl = require("tcl-lsp.tcl")
		local config = require("tcl-lsp.config")

		-- Get basics
		local word, err = utils.get_word_under_cursor()
		if not word then
			utils.notify("No word under cursor", vim.log.levels.ERROR)
			return
		end

		local file_path, file_err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No current file", vim.log.levels.ERROR)
			return
		end

		utils.notify("🎯 Simple goto for '" .. word .. "'", vim.log.levels.INFO)

		-- Get symbols
		local tclsh_cmd = config.get_tclsh_cmd()
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

		if not symbols then
			utils.notify("❌ No symbols returned from analysis", vim.log.levels.ERROR)
			return
		end

		if #symbols == 0 then
			utils.notify("❌ Zero symbols found in file", vim.log.levels.ERROR)
			return
		end

		utils.notify("Found " .. #symbols .. " symbols, searching for '" .. word .. "'", vim.log.levels.INFO)

		-- Simple exact match search
		local matches = {}
		for _, symbol in ipairs(symbols) do
			if symbol.name == word then
				table.insert(matches, symbol)
			end
		end

		if #matches == 0 then
			utils.notify("❌ No exact matches for '" .. word .. "'", vim.log.levels.ERROR)

			-- Show available symbols
			utils.notify("Available symbols:", vim.log.levels.INFO)
			for i = 1, math.min(10, #symbols) do
				utils.notify("  " .. symbols[i].type .. ": " .. symbols[i].name, vim.log.levels.INFO)
			end
			return
		end

		-- Found matches!
		if #matches == 1 then
			local match = matches[1]
			utils.notify(
				"✅ Found " .. match.type .. " '" .. match.name .. "' at line " .. match.line,
				vim.log.levels.INFO
			)
			vim.api.nvim_win_set_cursor(0, { match.line, 0 })
		else
			utils.notify("Found " .. #matches .. " matches:", vim.log.levels.INFO)
			for i, match in ipairs(matches) do
				utils.notify(
					"  " .. i .. ". " .. match.type .. " '" .. match.name .. "' at line " .. match.line,
					vim.log.levels.INFO
				)
			end

			-- Jump to first match
			vim.api.nvim_win_set_cursor(0, { matches[1].line, 0 })
		end
	end, {
		desc = "Simple goto definition test",
	})

	-- Test if symbols_match function is working
	vim.api.nvim_create_user_command("TclTestSymbolsMatch", function()
		local utils = require("tcl-lsp.utils")

		if not utils.symbols_match then
			utils.notify("❌ utils.symbols_match function not found!", vim.log.levels.ERROR)
			utils.notify("This could be why goto definition fails", vim.log.levels.ERROR)
			return
		end

		local word, err = utils.get_word_under_cursor()
		if not word then
			utils.notify("No word under cursor", vim.log.levels.ERROR)
			return
		end

		utils.notify("Testing symbols_match function with '" .. word .. "'", vim.log.levels.INFO)

		-- Test various symbol patterns
		local test_symbols = {
			word, -- exact
			"test::" .. word, -- namespace qualified
			word .. "_var", -- similar
			"my_" .. word, -- similar
			string.upper(word), -- case different
			"::" .. word, -- global qualified
		}

		for _, test_symbol in ipairs(test_symbols) do
			local matches = utils.symbols_match(test_symbol, word)
			local status = matches and "✅ MATCHES" or "❌ no match"
			utils.notify(string.format("  '%s' vs '%s': %s", test_symbol, word, status), vim.log.levels.INFO)
		end
	end, {
		desc = "Test symbols_match function",
	})

	-- Create a minimal test file for goto definition
	vim.api.nvim_create_user_command("TclCreateGotoTest", function()
		local test_content = [[
# Simple test file for goto definition
proc test_proc {arg1 arg2} {
    set local_var "hello"
    puts $local_var
    puts $arg1
    return $arg2
}

set global_var "world"
set another_var $global_var

test_proc "first" "second"
]]

		vim.cmd("new")
		vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(test_content, "\n"))
		vim.bo.filetype = "tcl"

		local utils = require("tcl-lsp.utils")
		utils.notify("Created simple test file for goto definition", vim.log.levels.INFO)
		utils.notify("Try these tests:", vim.log.levels.INFO)
		utils.notify("1. Put cursor on 'test_proc' in line 11 and run :TclSimpleGoto", vim.log.levels.INFO)
		utils.notify("2. Put cursor on 'local_var' in line 4 and run :TclSimpleGoto", vim.log.levels.INFO)
		utils.notify("3. Put cursor on 'global_var' in line 9 and run :TclSimpleGoto", vim.log.levels.INFO)
		utils.notify("4. Put cursor on 'arg1' in line 5 and run :TclSimpleGoto", vim.log.levels.INFO)
	end, {
		desc = "Create simple test file for goto definition",
	})

	-- Quick analysis of current file
	vim.api.nvim_create_user_command("TclQuickAnalysis", function()
		local utils = require("tcl-lsp.utils")
		local tcl = require("tcl-lsp.tcl")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No current file: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		utils.notify("📊 Quick analysis of " .. vim.fn.fnamemodify(file_path, ":t"), vim.log.levels.INFO)

		local tclsh_cmd = config.get_tclsh_cmd()
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

		if not symbols then
			utils.notify("❌ Analysis returned nil", vim.log.levels.ERROR)
			return
		end

		if #symbols == 0 then
			utils.notify("❌ Zero symbols found", vim.log.levels.ERROR)
			utils.notify("This is why goto definition fails!", vim.log.levels.ERROR)

			-- Show first few lines of file for debugging
			local lines = vim.api.nvim_buf_get_lines(0, 0, 5, false)
			utils.notify("First lines of file:", vim.log.levels.INFO)
			for i, line in ipairs(lines) do
				if line:gsub("%s", "") ~= "" then
					utils.notify("  " .. i .. ": " .. line, vim.log.levels.INFO)
				end
			end
			return
		end

		-- Group by type
		local by_type = {}
		for _, symbol in ipairs(symbols) do
			if not by_type[symbol.type] then
				by_type[symbol.type] = {}
			end
			table.insert(by_type[symbol.type], symbol)
		end

		utils.notify("✅ Found " .. #symbols .. " symbols:", vim.log.levels.INFO)
		for type_name, type_symbols in pairs(by_type) do
			utils.notify("  " .. type_name .. ": " .. #type_symbols, vim.log.levels.INFO)

			-- Show first few examples
			for i = 1, math.min(3, #type_symbols) do
				local sym = type_symbols[i]
				utils.notify("    '" .. sym.name .. "' at line " .. sym.line, vim.log.levels.INFO)
			end
		end
	end, {
		desc = "Quick analysis of current file",
	})

	vim.api.nvim_create_user_command("TclTestRobust", function()
		local utils = require("tcl-lsp.utils")
		local tcl = require("tcl-lsp.tcl")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file to analyze: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		utils.notify("🔧 Testing ROBUST analysis on " .. vim.fn.fnamemodify(file_path, ":t"), vim.log.levels.INFO)

		local tclsh_cmd = config.get_tclsh_cmd()

		-- Clear cache to force fresh analysis
		tcl.invalidate_cache(file_path)

		-- Run the robust analysis
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

		if not symbols then
			utils.notify("❌ Robust analysis STILL failed", vim.log.levels.ERROR)
			utils.notify("Check :messages for debug output", vim.log.levels.INFO)
			return
		end

		if #symbols == 0 then
			utils.notify("❌ Robust analysis found ZERO symbols", vim.log.levels.ERROR)
			utils.notify("This suggests the TCL script itself is failing", vim.log.levels.ERROR)

			-- Show file info for debugging
			local file_size = vim.fn.getfsize(file_path)
			local line_count = vim.api.nvim_buf_line_count(0)
			utils.notify("File size: " .. file_size .. " bytes, " .. line_count .. " lines", vim.log.levels.INFO)

			return
		end

		utils.notify("✅ Robust analysis found " .. #symbols .. " symbols!", vim.log.levels.INFO)

		-- Group by type and show results
		local by_type = {}
		for _, symbol in ipairs(symbols) do
			if not by_type[symbol.type] then
				by_type[symbol.type] = {}
			end
			table.insert(by_type[symbol.type], symbol)
		end

		for type_name, type_symbols in pairs(by_type) do
			utils.notify(string.format("  %s (%d):", type_name, #type_symbols), vim.log.levels.INFO)

			for i = 1, math.min(5, #type_symbols) do
				local symbol = type_symbols[i]
				local qualified_info = symbol.qualified_name and (" → " .. symbol.qualified_name) or ""
				utils.notify(
					string.format(
						"    %d. '%s'%s [%s] line %d",
						i,
						symbol.name,
						qualified_info,
						symbol.scope,
						symbol.line
					),
					vim.log.levels.INFO
				)
			end

			if #type_symbols > 5 then
				utils.notify(string.format("    ... and %d more", #type_symbols - 5), vim.log.levels.INFO)
			end
		end

		utils.notify("🎯 Now try goto definition - it should work!", vim.log.levels.INFO)
	end, {
		desc = "Test robust analysis on current file",
	})

	-- Test if the TCL script execution is working at all
	vim.api.nvim_create_user_command("TclTestExecution", function()
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")

		local tclsh_cmd = config.get_tclsh_cmd()
		utils.notify("Testing basic TCL script execution with: " .. tclsh_cmd, vim.log.levels.INFO)

		-- Simple test script
		local test_script = [[
puts "TCL_TEST_START"
puts "TCL version: [info patchlevel]"
puts "Working directory: [pwd]"

# Test basic functionality
set test_var "hello world"
puts "Test variable: $test_var"

# Test file operations
set temp_file "/tmp/tcl_test_[clock seconds].txt"
if {[catch {
    set fp [open $temp_file w]
    puts $fp "test content"
    close $fp
    puts "File write: SUCCESS"
    file delete $temp_file
} err]} {
    puts "File operations: FAILED - $err"
} else {
    puts "File operations: SUCCESS"
}

puts "TCL_TEST_COMPLETE"
]]

		local result, success = utils.execute_tcl_script(test_script, tclsh_cmd)

		if not result then
			utils.notify("❌ TCL script execution completely failed", vim.log.levels.ERROR)
			utils.notify("Check if tclsh is installed: " .. tclsh_cmd, vim.log.levels.ERROR)
			return
		end

		if not success then
			utils.notify("❌ TCL script had errors:", vim.log.levels.ERROR)
			utils.notify(result, vim.log.levels.ERROR)
			return
		end

		utils.notify("✅ TCL script execution works!", vim.log.levels.INFO)
		utils.notify("Output:", vim.log.levels.INFO)
		for line in result:gmatch("[^\n]+") do
			utils.notify("  " .. line, vim.log.levels.INFO)
		end
	end, {
		desc = "Test basic TCL script execution",
	})

	-- Test the analysis script step by step
	vim.api.nvim_create_user_command("TclTestAnalysisSteps", function()
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file to analyze: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()

		utils.notify("🔍 Testing analysis script step by step", vim.log.levels.INFO)

		-- Step 1: Test file reading
		local escaped_path = file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
		local file_read_test = string.format(
			[[
set file_path "%s"
puts "Testing file: $file_path"

if {[catch {
    set fp [open $file_path r]
    set content [read $fp]
    close $fp
} err]} {
    puts "ERROR: Cannot read file: $err"
    exit 1
}

puts "SUCCESS: File read, length: [string length $content] characters"
set lines [split $content "\n"]
puts "Lines: [llength $lines]"

# Show first few lines
set count 0
foreach line $lines {
    if {[incr count] > 5} break
    set trimmed [string trim $line]
    if {$trimmed ne ""} {
        puts "Line $count: $trimmed"
    }
}
]],
			escaped_path
		)

		local result, success = utils.execute_tcl_script(file_read_test, tclsh_cmd)

		if not (result and success) then
			utils.notify("❌ Step 1 FAILED: Cannot read file", vim.log.levels.ERROR)
			utils.notify("Result: " .. (result or "nil"), vim.log.levels.ERROR)
			return
		end

		utils.notify("✅ Step 1: File reading works", vim.log.levels.INFO)
		for line in result:gmatch("[^\n]+") do
			utils.notify("  " .. line, vim.log.levels.INFO)
		end

		-- Step 2: Test pattern matching
		local pattern_test = string.format(
			[[
set file_path "%s"
set fp [open $file_path r]
set content [read $fp]
close $fp

set lines [split $content "\n"]
set line_num 0
set found_symbols 0

foreach line $lines {
    incr line_num
    set trimmed [string trim $line]
    
    if {$trimmed eq "" || [string match "#*" $trimmed]} {
        continue
    }
    
    # Test namespace pattern
    if {[regexp {^\s*namespace\s+eval\s+([a-zA-Z_:][a-zA-Z0-9_:]*)} $trimmed match ns_name]} {
        puts "FOUND: namespace '$ns_name' at line $line_num"
        incr found_symbols
    }
    
    # Test proc pattern  
    if {[regexp {^\s*proc\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $trimmed match proc_name]} {
        puts "FOUND: procedure '$proc_name' at line $line_num"
        incr found_symbols
    }
    
    # Test package pattern
    if {[regexp {^\s*package\s+(require|provide)\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $trimmed match cmd pkg_name]} {
        puts "FOUND: package '$pkg_name' ($cmd) at line $line_num"
        incr found_symbols
    }
    
    # Test variable pattern
    if {[regexp {^\s*set\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $trimmed match var_name]} {
        puts "FOUND: variable '$var_name' at line $line_num"
        incr found_symbols
    }
}

puts "TOTAL SYMBOLS FOUND: $found_symbols"
]],
			escaped_path
		)

		result, success = utils.execute_tcl_script(pattern_test, tclsh_cmd)

		if not (result and success) then
			utils.notify("❌ Step 2 FAILED: Pattern matching failed", vim.log.levels.ERROR)
			return
		end

		utils.notify("✅ Step 2: Pattern matching results", vim.log.levels.INFO)
		for line in result:gmatch("[^\n]+") do
			utils.notify("  " .. line, vim.log.levels.INFO)
		end
	end, {
		desc = "Test analysis script step by step",
	})

	vim.api.nvim_create_user_command("TclTestTrueSemantic", function()
		local utils = require("tcl-lsp.utils")
		local tcl = require("tcl-lsp.tcl")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file to analyze: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		utils.notify("🧠 Testing TRUE semantic analysis (NO REGEX PATTERNS)", vim.log.levels.INFO)

		local tclsh_cmd = config.get_tclsh_cmd()

		-- Clear cache to force fresh analysis
		tcl.invalidate_cache(file_path)

		-- Run the true semantic analysis
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

		if not symbols then
			utils.notify("❌ True semantic analysis failed", vim.log.levels.ERROR)
			utils.notify("Check :messages for debug output", vim.log.levels.INFO)
			return
		end

		if #symbols == 0 then
			utils.notify("❌ True semantic analysis found ZERO symbols", vim.log.levels.ERROR)
			utils.notify("This suggests the TCL parser evaluation is failing", vim.log.levels.ERROR)
			return
		end

		utils.notify("✅ TRUE semantic analysis found " .. #symbols .. " symbols!", vim.log.levels.INFO)

		-- Show method to verify it's truly semantic
		local by_method = {}
		for _, symbol in ipairs(symbols) do
			local method = symbol.method or "unknown"
			if not by_method[method] then
				by_method[method] = 0
			end
			by_method[method] = by_method[method] + 1
		end

		utils.notify("Analysis methods used:", vim.log.levels.INFO)
		for method, count in pairs(by_method) do
			local status = (method == "true_semantic_no_regex") and "✅ TRUE SEMANTIC" or "⚠️ " .. method
			utils.notify("  " .. status .. ": " .. count .. " symbols", vim.log.levels.INFO)
		end

		-- Group by type and show results
		local by_type = {}
		for _, symbol in ipairs(symbols) do
			if not by_type[symbol.type] then
				by_type[symbol.type] = {}
			end
			table.insert(by_type[symbol.type], symbol)
		end

		utils.notify("", vim.log.levels.INFO)
		utils.notify("Symbols found by type:", vim.log.levels.INFO)
		for type_name, type_symbols in pairs(by_type) do
			utils.notify(string.format("  %s (%d):", type_name, #type_symbols), vim.log.levels.INFO)

			for i = 1, math.min(3, #type_symbols) do
				local symbol = type_symbols[i]
				local qualified_info = symbol.qualified_name and (" → " .. symbol.qualified_name) or ""
				utils.notify(
					string.format(
						"    %d. '%s'%s [%s] line %d",
						i,
						symbol.name,
						qualified_info,
						symbol.scope,
						symbol.line
					),
					vim.log.levels.INFO
				)
			end

			if #type_symbols > 3 then
				utils.notify(string.format("    ... and %d more", #type_symbols - 3), vim.log.levels.INFO)
			end
		end

		utils.notify("", vim.log.levels.INFO)
		utils.notify("🎯 Now try goto definition - it should work with TRUE semantic analysis!", vim.log.levels.INFO)
	end, {
		desc = "Test true semantic analysis (no regex patterns)",
	})

	-- Compare regex vs true semantic
	vim.api.nvim_create_user_command("TclCompareRegexVsSemantic", function()
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()
		local escaped_path = file_path:gsub("\\", "\\\\"):gsub('"', '\\"')

		utils.notify("🔬 Comparing REGEX vs TRUE SEMANTIC analysis", vim.log.levels.INFO)

		-- Test 1: Regex approach (what we were doing)
		local regex_script = string.format(
			[[
set file_path "%s"
set fp [open $file_path r]
set content [read $fp]
close $fp

set lines [split $content "\n"]
set regex_count 0

foreach line $lines {
    set trimmed [string trim $line]
    if {$trimmed eq "" || [string match "#*" $trimmed]} continue
    
    # REGEX pattern matching
    if {[regexp {^\s*namespace\s+eval\s+([a-zA-Z_:][a-zA-Z0-9_:]*)} $trimmed]} {
        incr regex_count
    }
    if {[regexp {^\s*proc\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $trimmed]} {
        incr regex_count  
    }
    if {[regexp {^\s*package\s+(require|provide)\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $trimmed]} {
        incr regex_count
    }
    if {[regexp {^\s*set\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $trimmed]} {
        incr regex_count
    }
}

puts "REGEX_FOUND: $regex_count"
]],
			escaped_path
		)

		-- Test 2: Semantic approach using TCL's parser
		local semantic_script = string.format(
			[[
set file_path "%s"
set fp [open $file_path r]
set content [read $fp]
close $fp

set semantic_count 0
set semantic_interp [interp create -safe]

$semantic_interp alias count_symbol count_symbol
proc count_symbol {} {
    global semantic_count
    incr semantic_count
}

$semantic_interp eval {
    rename namespace orig_ns
    proc namespace {args} { count_symbol; return "" }
    
    rename proc orig_proc  
    proc proc {args} { count_symbol; return "" }
    
    rename package orig_pkg
    proc package {args} { count_symbol; return "" }
    
    rename set orig_set
    proc set {args} { count_symbol; return "" }
    
    # Disable side effects
    proc puts {args} { return "" }
    proc exec {args} { return "" }
}

# Use TCL's actual parser
if {[catch {$semantic_interp eval $content} err]} {
    # If full eval fails, try command by command
    set pos 0
    while {$pos < [string length $content]} {
        set end $pos
        while {$end < [string length $content]} {
            set cmd [string range $content $pos $end]
            if {[catch {info complete $cmd} complete]} {
                incr end
                continue
            }
            if {$complete && [string trim $cmd] ne ""} {
                catch {$semantic_interp eval $cmd}
                set pos [expr {$end + 1}]
                break
            }
            incr end
        }
        if {$end >= [string length $content]} break
    }
}

interp delete $semantic_interp
puts "SEMANTIC_FOUND: $semantic_count"
]],
			escaped_path
		)

		-- Run both tests
		local regex_result, regex_success = utils.execute_tcl_script(regex_script, tclsh_cmd)
		local semantic_result, semantic_success = utils.execute_tcl_script(semantic_script, tclsh_cmd)

		local regex_count = 0
		local semantic_count = 0

		if regex_result and regex_success then
			regex_count = tonumber(regex_result:match("REGEX_FOUND: (%d+)")) or 0
		end

		if semantic_result and semantic_success then
			semantic_count = tonumber(semantic_result:match("SEMANTIC_FOUND: (%d+)")) or 0
		end

		utils.notify("📊 Analysis Comparison Results:", vim.log.levels.INFO)
		utils.notify("  REGEX pattern matching: " .. regex_count .. " symbols", vim.log.levels.INFO)
		utils.notify("  TRUE SEMANTIC parsing: " .. semantic_count .. " symbols", vim.log.levels.INFO)

		if semantic_count > regex_count then
			utils.notify("✅ Semantic found MORE symbols (catches complex cases)", vim.log.levels.INFO)
		elseif semantic_count == regex_count then
			utils.notify("= Both found same count (file may be simple)", vim.log.levels.INFO)
		else
			utils.notify("⚠️ Regex found more (semantic may have eval issues)", vim.log.levels.WARN)
		end

		utils.notify("", vim.log.levels.INFO)
		utils.notify("The TRUE semantic approach uses TCL's actual parser", vim.log.levels.INFO)
		utils.notify("instead of fragile regex patterns!", vim.log.levels.INFO)
	end, {
		desc = "Compare regex vs true semantic analysis",
	})

	-- Test the hybrid semantic analysis

	vim.api.nvim_create_user_command("TclTestHybrid", function()
		local utils = require("tcl-lsp.utils")
		local tcl = require("tcl-lsp.tcl")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file to analyze: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		utils.notify("🔬 Testing HYBRID semantic analysis (Parser + Patterns)", vim.log.levels.INFO)

		local tclsh_cmd = config.get_tclsh_cmd()

		-- Clear cache to force fresh analysis
		tcl.invalidate_cache(file_path)

		-- Run the hybrid analysis
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

		if not symbols then
			utils.notify("❌ Hybrid analysis failed", vim.log.levels.ERROR)
			utils.notify("Check :messages for debug output", vim.log.levels.INFO)
			return
		end

		if #symbols == 0 then
			utils.notify("❌ Hybrid analysis found ZERO symbols", vim.log.levels.ERROR)
			utils.notify("Both parser and patterns failed", vim.log.levels.ERROR)
			return
		end

		utils.notify("✅ HYBRID analysis found " .. #symbols .. " symbols!", vim.log.levels.INFO)

		-- Show method to verify it's hybrid
		local by_method = {}
		for _, symbol in ipairs(symbols) do
			local method = symbol.method or "unknown"
			if not by_method[method] then
				by_method[method] = 0
			end
			by_method[method] = by_method[method] + 1
		end

		utils.notify("Analysis methods used:", vim.log.levels.INFO)
		for method, count in pairs(by_method) do
			utils.notify("  " .. method .. ": " .. count .. " symbols", vim.log.levels.INFO)
		end

		-- Group by type and show results
		local by_type = {}
		for _, symbol in ipairs(symbols) do
			if not by_type[symbol.type] then
				by_type[symbol.type] = {}
			end
			table.insert(by_type[symbol.type], symbol)
		end

		utils.notify("", vim.log.levels.INFO)
		utils.notify("Symbols found by type:", vim.log.levels.INFO)
		for type_name, type_symbols in pairs(by_type) do
			utils.notify(string.format("  %s (%d):", type_name, #type_symbols), vim.log.levels.INFO)

			for i = 1, math.min(3, #type_symbols) do
				local symbol = type_symbols[i]
				local qualified_info = symbol.qualified_name and (" → " .. symbol.qualified_name) or ""
				utils.notify(
					string.format(
						"    %d. '%s'%s [%s] line %d",
						i,
						symbol.name,
						qualified_info,
						symbol.scope,
						symbol.line
					),
					vim.log.levels.INFO
				)
			end

			if #type_symbols > 3 then
				utils.notify(string.format("    ... and %d more", #type_symbols - 3), vm.log.levels.INFO)
			end
		end

		utils.notify("", vim.log.levels.INFO)
		utils.notify("🎯 Now try goto definition - it should work!", vim.log.levels.INFO)
	end, {
		desc = "Test hybrid semantic analysis (parser + patterns)",
	})

	-- Final comparison of all approaches
	vim.api.nvim_create_user_command("TclCompareAll", function()
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			utils.notify("No file: " .. (err or "unknown"), vim.log.levels.ERROR)
			return
		end

		utils.notify("📊 Comparing ALL analysis approaches", vim.log.levels.INFO)

		-- Test each approach
		utils.notify("1. Testing regex patterns...", vim.log.levels.INFO)
		vim.cmd("TclTestAnalysisSteps")

		utils.notify("2. Testing pure semantic...", vim.log.levels.INFO)
		vim.cmd("TclTestTrueSemantic")

		utils.notify("3. Testing hybrid approach...", vim.log.levels.INFO)
		vim.cmd("TclTestHybrid")

		utils.notify("", vim.log.levels.INFO)
		utils.notify("📈 Summary:", vim.log.levels.INFO)
		utils.notify("- Regex: Works but fragile", vim.log.levels.INFO)
		utils.notify("- Pure semantic: More accurate but eval issues", vim.log.levels.INFO)
		utils.notify("- Hybrid: Best of both worlds!", vim.log.levels.INFO)
	end, {
		desc = "Compare all analysis approaches",
	})

	vim.api.nvim_create_user_command("TclLspDebugDetailed", function()
		local file_path, err = require("tcl-lsp.utils").get_current_file_path()
		if not file_path then
			print("ERROR: No file to debug:", err)
			return
		end

		local config = require("tcl-lsp.config")
		local tcl = require("tcl-lsp.tcl")
		local semantic = require("tcl-lsp.semantic")
		local utils = require("tcl-lsp.utils")

		print("=== TCL LSP Detailed Debug ===")
		print("File:", file_path)
		print("File exists:", tcl.file_exists(file_path))

		local tclsh_cmd = config.get_tclsh_cmd()
		print("TCL command:", tclsh_cmd)

		-- Test basic TCL functionality
		print("\n=== Testing Basic TCL ===")
		local test_result, test_success = utils.execute_tcl_script('puts "BASIC_TEST_OK"', tclsh_cmd)
		print("Basic test result:", test_result)
		print("Basic test success:", test_success)

		-- Test file reading
		print("\n=== Testing File Reading ===")
		local read_test = string.format(
			[[
if {[catch {
    set fp [open "%s" r]
    set content [read $fp]
    close $fp
    puts "FILE_READ_OK:[string length $content] characters"
} err]} {
    puts "FILE_READ_ERROR:$err"
}
]],
			file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
		)

		local read_result, read_success = utils.execute_tcl_script(read_test, tclsh_cmd)
		print("File read result:", read_result)
		print("File read success:", read_success)

		-- Test symbol analysis
		print("\n=== Testing Symbol Analysis ===")
		local symbols = tcl.debug_symbols(file_path, tclsh_cmd)
		print("Symbols found:", #symbols)

		-- Test semantic analysis
		print("\n=== Testing Semantic Analysis ===")
		local semantic_symbols = semantic.analyze_single_file_symbols(file_path, tclsh_cmd)
		if semantic_symbols then
			print("Semantic symbols found:", #semantic_symbols)
		else
			print("Semantic analysis failed")
		end

		-- Test current word detection
		print("\n=== Testing Word Detection ===")
		local word, word_err = utils.get_word_under_cursor()
		local qualified_word, qual_err = utils.get_qualified_word_under_cursor()
		print("Current word:", word or ("ERROR: " .. (word_err or "unknown")))
		print("Qualified word:", qualified_word or ("ERROR: " .. (qual_err or "unknown")))

		-- Cache statistics
		print("\n=== Cache Statistics ===")
		local cache_stats = tcl.get_cache_stats()
		for k, v in pairs(cache_stats) do
			print(k .. ":", v)
		end

		print("\n=== Debug Complete ===")
	end, {
		desc = "Run detailed TCL LSP debug analysis",
	})

	-- Command to test go-to-definition step by step
	vim.api.nvim_create_user_command("TclTestGotoDefinition", function()
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")
		local tcl = require("tcl-lsp.tcl")

		print("=== Testing Go-to-Definition Step by Step ===")

		-- Step 1: Get word under cursor
		local word, err = utils.get_qualified_word_under_cursor()
		if not word then
			word, err = utils.get_word_under_cursor()
		end

		if not word then
			print("FAIL: Cannot get word under cursor:", err)
			return
		end
		print("Step 1 OK: Found word:", word)

		-- Step 2: Get file path
		local file_path, file_err = utils.get_current_file_path()
		if not file_path then
			print("FAIL: Cannot get file path:", file_err)
			return
		end
		print("Step 2 OK: File path:", file_path)

		-- Step 3: Get TCL command
		local tclsh_cmd = config.get_tclsh_cmd()
		print("Step 3 OK: TCL command:", tclsh_cmd)

		-- Step 4: Analyze file
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
		if not symbols then
			print("FAIL: Symbol analysis returned nil")
			return
		end
		print("Step 4 OK: Found", #symbols, "symbols")

		-- Step 5: Look for matching symbols
		local matches = {}
		for _, symbol in ipairs(symbols) do
			if symbol.name == word or utils.symbols_match(symbol.name, word) then
				table.insert(matches, symbol)
			end
		end
		print("Step 5 OK: Found", #matches, "matching symbols")

		-- Step 6: Display results
		if #matches == 0 then
			print("RESULT: No matches found for '" .. word .. "'")
			print("Available symbols:")
			for i, symbol in ipairs(symbols) do
				print(string.format("  %d. %s '%s' at line %d", i, symbol.type, symbol.name, symbol.line))
			end
		else
			print("RESULT: Found matches:")
			for i, symbol in ipairs(matches) do
				print(string.format("  %d. %s '%s' at line %d", i, symbol.type, symbol.name, symbol.line))
			end
		end

		print("=== Test Complete ===")
	end, {
		desc = "Test go-to-definition functionality step by step",
	})

	-- Command to show all symbols in current file
	vim.api.nvim_create_user_command("TclShowAllSymbols", function()
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")
		local tcl = require("tcl-lsp.tcl")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			print("ERROR:", err)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

		if not symbols then
			print("ERROR: Failed to analyze file")
			return
		end

		print("=== All Symbols in", vim.fn.fnamemodify(file_path, ":t"), "===")
		print("Total symbols:", #symbols)

		-- Group by type
		local by_type = {}
		for _, symbol in ipairs(symbols) do
			if not by_type[symbol.type] then
				by_type[symbol.type] = {}
			end
			table.insert(by_type[symbol.type], symbol)
		end

		-- Display grouped
		for type_name, type_symbols in pairs(by_type) do
			print("\n" .. type_name:upper() .. " (" .. #type_symbols .. "):")
			table.sort(type_symbols, function(a, b)
				return a.line < b.line
			end)
			for _, symbol in ipairs(type_symbols) do
				print(
					string.format(
						"  Line %d: %s (scope: %s, context: %s)",
						symbol.line,
						symbol.name,
						symbol.scope or "none",
						symbol.context or "none"
					)
				)
			end
		end
	end, {
		desc = "Show all symbols found in current file",
	})

	-- Command to clear all caches
	vim.api.nvim_create_user_command("TclClearCaches", function()
		local tcl = require("tcl-lsp.tcl")
		local semantic = require("tcl-lsp.semantic")

		tcl.clear_all_caches()
		semantic.invalidate_workspace_cache()

		print("All TCL LSP caches cleared")
	end, {
		desc = "Clear all TCL LSP caches",
	})

	-- Command to test a specific symbol resolution
	vim.api.nvim_create_user_command("TclTestSymbol", function(opts)
		if not opts.args or opts.args == "" then
			print("Usage: :TclTestSymbol <symbol_name>")
			return
		end

		local symbol_name = opts.args
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")
		local tcl = require("tcl-lsp.tcl")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			print("ERROR:", err)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()
		local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

		print("=== Testing Symbol:", symbol_name, "===")
		print("File:", file_path)
		print("Cursor line:", cursor_line)

		-- Test resolution
		local resolution = tcl.resolve_symbol(symbol_name, file_path, cursor_line, tclsh_cmd)
		if resolution then
			print("Resolution context:", vim.inspect(resolution.context))
			print("Resolution candidates:", #resolution.resolutions)
			for i, res in ipairs(resolution.resolutions) do
				print(string.format("  %d. %s: %s (priority: %d)", i, res.type, res.name, res.priority))
			end
		else
			print("No resolution found")
		end

		-- Test symbol search
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
		if symbols then
			local matches = {}
			for _, symbol in ipairs(symbols) do
				if symbol.name == symbol_name or utils.symbols_match(symbol.name, symbol_name) then
					table.insert(matches, symbol)
				end
			end
			print("Direct matches:", #matches)
			for i, symbol in ipairs(matches) do
				print(string.format("  %d. %s '%s' at line %d", i, symbol.type, symbol.name, symbol.line))
			end
		end
	end, {
		desc = "Test symbol resolution for a specific symbol",
		nargs = 1,
	})

	vim.api.nvim_create_user_command("TclTestSimple", function()
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")
		local tcl = require("tcl-lsp.tcl")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			print("ERROR: No file:", err)
			return
		end

		print("=== Simple TCL Test ===")
		print("File:", file_path)

		local tclsh_cmd = config.get_tclsh_cmd()
		print("TCL command:", tclsh_cmd)

		-- Clear cache
		tcl.clear_all_caches()

		-- Test symbol analysis directly
		print("Testing symbol analysis...")
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

		if symbols then
			print("SUCCESS: Found", #symbols, "symbols")
			for i, symbol in ipairs(symbols) do
				if i <= 5 then -- Show first 5 symbols
					print(string.format("  %d. %s '%s' at line %d", i, symbol.type, symbol.name, symbol.line))
				end
			end
			if #symbols > 5 then
				print("  ... and", #symbols - 5, "more symbols")
			end
		else
			print("FAILED: No symbols found")
		end
	end, {
		desc = "Simple TCL symbol test",
	})

	-- Add these debug commands to your init.lua for troubleshooting

	-- Enhanced debug command for the init.lua file
	vim.api.nvim_create_user_command("TclLspDebugDetailed", function()
		local file_path, err = require("tcl-lsp.utils").get_current_file_path()
		if not file_path then
			print("ERROR: No file to debug:", err)
			return
		end

		local config = require("tcl-lsp.config")
		local tcl = require("tcl-lsp.tcl")
		local semantic = require("tcl-lsp.semantic")
		local utils = require("tcl-lsp.utils")

		print("=== TCL LSP Detailed Debug ===")
		print("File:", file_path)
		print("File exists:", tcl.file_exists(file_path))

		local tclsh_cmd = config.get_tclsh_cmd()
		print("TCL command:", tclsh_cmd)

		-- Test basic TCL functionality
		print("\n=== Testing Basic TCL ===")
		local test_result, test_success = utils.execute_tcl_script('puts "BASIC_TEST_OK"', tclsh_cmd)
		print("Basic test result:", test_result)
		print("Basic test success:", test_success)

		-- Test file reading
		print("\n=== Testing File Reading ===")
		local read_test = string.format(
			[[
if {[catch {
    set fp [open "%s" r]
    set content [read $fp]
    close $fp
    puts "FILE_READ_OK:[string length $content] characters"
} err]} {
    puts "FILE_READ_ERROR:$err"
}
]],
			file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
		)

		local read_result, read_success = utils.execute_tcl_script(read_test, tclsh_cmd)
		print("File read result:", read_result)
		print("File read success:", read_success)

		-- Test symbol analysis
		print("\n=== Testing Symbol Analysis ===")
		local symbols = tcl.debug_symbols(file_path, tclsh_cmd)
		print("Symbols found:", #symbols)

		-- Test semantic analysis
		print("\n=== Testing Semantic Analysis ===")
		local semantic_symbols = semantic.analyze_single_file_symbols(file_path, tclsh_cmd)
		if semantic_symbols then
			print("Semantic symbols found:", #semantic_symbols)
		else
			print("Semantic analysis failed")
		end

		-- Test current word detection
		print("\n=== Testing Word Detection ===")
		local word, word_err = utils.get_word_under_cursor()
		local qualified_word, qual_err = utils.get_qualified_word_under_cursor()
		print("Current word:", word or ("ERROR: " .. (word_err or "unknown")))
		print("Qualified word:", qualified_word or ("ERROR: " .. (qual_err or "unknown")))

		-- Cache statistics
		print("\n=== Cache Statistics ===")
		local cache_stats = tcl.get_cache_stats()
		for k, v in pairs(cache_stats) do
			print(k .. ":", v)
		end

		print("\n=== Debug Complete ===")
	end, {
		desc = "Run detailed TCL LSP debug analysis",
	})

	-- Command to test go-to-definition step by step
	vim.api.nvim_create_user_command("TclTestGotoDefinition", function()
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")
		local tcl = require("tcl-lsp.tcl")

		print("=== Testing Go-to-Definition Step by Step ===")

		-- Step 1: Get word under cursor
		local word, err = utils.get_qualified_word_under_cursor()
		if not word then
			word, err = utils.get_word_under_cursor()
		end

		if not word then
			print("FAIL: Cannot get word under cursor:", err)
			return
		end
		print("Step 1 OK: Found word:", word)

		-- Step 2: Get file path
		local file_path, file_err = utils.get_current_file_path()
		if not file_path then
			print("FAIL: Cannot get file path:", file_err)
			return
		end
		print("Step 2 OK: File path:", file_path)

		-- Step 3: Get TCL command
		local tclsh_cmd = config.get_tclsh_cmd()
		print("Step 3 OK: TCL command:", tclsh_cmd)

		-- Step 4: Analyze file
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
		if not symbols then
			print("FAIL: Symbol analysis returned nil")
			return
		end
		print("Step 4 OK: Found", #symbols, "symbols")

		-- Step 5: Look for matching symbols
		local matches = {}
		for _, symbol in ipairs(symbols) do
			if symbol.name == word or utils.symbols_match(symbol.name, word) then
				table.insert(matches, symbol)
			end
		end
		print("Step 5 OK: Found", #matches, "matching symbols")

		-- Step 6: Display results
		if #matches == 0 then
			print("RESULT: No matches found for '" .. word .. "'")
			print("Available symbols:")
			for i, symbol in ipairs(symbols) do
				print(string.format("  %d. %s '%s' at line %d", i, symbol.type, symbol.name, symbol.line))
			end
		else
			print("RESULT: Found matches:")
			for i, symbol in ipairs(matches) do
				print(string.format("  %d. %s '%s' at line %d", i, symbol.type, symbol.name, symbol.line))
			end
		end

		print("=== Test Complete ===")
	end, {
		desc = "Test go-to-definition functionality step by step",
	})

	-- Command to show all symbols in current file
	vim.api.nvim_create_user_command("TclShowAllSymbols", function()
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")
		local tcl = require("tcl-lsp.tcl")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			print("ERROR:", err)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

		if not symbols then
			print("ERROR: Failed to analyze file")
			return
		end

		print("=== All Symbols in", vim.fn.fnamemodify(file_path, ":t"), "===")
		print("Total symbols:", #symbols)

		-- Group by type
		local by_type = {}
		for _, symbol in ipairs(symbols) do
			if not by_type[symbol.type] then
				by_type[symbol.type] = {}
			end
			table.insert(by_type[symbol.type], symbol)
		end

		-- Display grouped
		for type_name, type_symbols in pairs(by_type) do
			print("\n" .. type_name:upper() .. " (" .. #type_symbols .. "):")
			table.sort(type_symbols, function(a, b)
				return a.line < b.line
			end)
			for _, symbol in ipairs(type_symbols) do
				print(
					string.format(
						"  Line %d: %s (scope: %s, context: %s)",
						symbol.line,
						symbol.name,
						symbol.scope or "none",
						symbol.context or "none"
					)
				)
			end
		end
	end, {
		desc = "Show all symbols found in current file",
	})

	-- Command to clear all caches
	vim.api.nvim_create_user_command("TclClearCaches", function()
		local tcl = require("tcl-lsp.tcl")
		local semantic = require("tcl-lsp.semantic")

		tcl.clear_all_caches()
		semantic.invalidate_workspace_cache()

		print("All TCL LSP caches cleared")
	end, {
		desc = "Clear all TCL LSP caches",
	})

	-- Command to test a specific symbol resolution
	vim.api.nvim_create_user_command("TclTestSymbol", function(opts)
		if not opts.args or opts.args == "" then
			print("Usage: :TclTestSymbol <symbol_name>")
			return
		end

		local symbol_name = opts.args
		local utils = require("tcl-lsp.utils")
		local config = require("tcl-lsp.config")
		local tcl = require("tcl-lsp.tcl")

		local file_path, err = utils.get_current_file_path()
		if not file_path then
			print("ERROR:", err)
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()
		local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

		print("=== Testing Symbol:", symbol_name, "===")
		print("File:", file_path)
		print("Cursor line:", cursor_line)

		-- Test resolution
		local resolution = tcl.resolve_symbol(symbol_name, file_path, cursor_line, tclsh_cmd)
		if resolution then
			print("Resolution context:", vim.inspect(resolution.context))
			print("Resolution candidates:", #resolution.resolutions)
			for i, res in ipairs(resolution.resolutions) do
				print(string.format("  %d. %s: %s (priority: %d)", i, res.type, res.name, res.priority))
			end
		else
			print("No resolution found")
		end

		-- Test symbol search
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)
		if symbols then
			local matches = {}
			for _, symbol in ipairs(symbols) do
				if symbol.name == symbol_name or utils.symbols_match(symbol.name, symbol_name) then
					table.insert(matches, symbol)
				end
			end
			print("Direct matches:", #matches)
			for i, symbol in ipairs(matches) do
				print(string.format("  %d. %s '%s' at line %d", i, symbol.type, symbol.name, symbol.line))
			end
		end
	end, {
		desc = "Test symbol resolution for a specific symbol",
		nargs = 1,
	})

	-- Debug workspace search functionality
	vim.api.nvim_create_user_command("TclDebugWorkspace", function(opts)
		local symbol_name = opts.args
		if not symbol_name or symbol_name == "" then
			-- Try to get from cursor
			local utils = require("tcl-lsp.utils")
			local word, err = utils.get_qualified_word_under_cursor()
			if not word then
				word, err = utils.get_word_under_cursor()
			end
			if word then
				symbol_name = word
			else
				print("Usage: :TclDebugWorkspace <symbol_name> or place cursor on symbol")
				return
			end
		end

		local config = require("tcl-lsp.config")
		local tcl = require("tcl-lsp.tcl")
		local utils = require("tcl-lsp.utils")

		print("=== Workspace Search Debug ===")
		print("Searching for:", "'" .. symbol_name .. "'")

		-- Get current file to exclude it
		local current_file, _ = utils.get_current_file_path()
		print("Current file:", current_file or "none")

		-- Find all TCL files
		local files = vim.fn.glob("**/*.tcl", false, true)
		print("Found", #files, "TCL files in workspace")

		if #files > 20 then
			print("WARNING: Large workspace, showing first 20 files:")
			for i = 1, 20 do
				print("  " .. i .. ". " .. files[i])
			end
			print("  ... and", #files - 20, "more files")
		else
			print("TCL files:")
			for i, file in ipairs(files) do
				print("  " .. i .. ". " .. file)
			end
		end

		local tclsh_cmd = config.get_tclsh_cmd()
		local total_symbols = 0
		local matches = {}
		local file_count = 0
		local error_count = 0

		print("\n--- Searching Files ---")

		for _, file in ipairs(files) do
			if file ~= current_file then
				file_count = file_count + 1

				-- Analyze each file
				local file_symbols = tcl.analyze_tcl_file(file, tclsh_cmd)

				if file_symbols then
					total_symbols = total_symbols + #file_symbols
					print(string.format("✓ %s: %d symbols", vim.fn.fnamemodify(file, ":t"), #file_symbols))

					-- Check for matches
					for _, symbol in ipairs(file_symbols) do
						local match_found = false
						local match_type = ""

						if symbol.name == symbol_name then
							match_found = true
							match_type = "exact"
						elseif symbol.qualified_name == symbol_name then
							match_found = true
							match_type = "qualified"
						elseif utils.symbols_match(symbol.name, symbol_name) then
							match_found = true
							match_type = "fuzzy"
						end

						if match_found then
							table.insert(matches, {
								symbol = symbol,
								file = file,
								match_type = match_type,
							})
							print(
								string.format(
									"  🎯 MATCH: %s '%s' at line %d (%s)",
									symbol.type,
									symbol.name,
									symbol.line,
									match_type
								)
							)
						end
					end
				else
					error_count = error_count + 1
					print(string.format("❌ %s: analysis failed", vim.fn.fnamemodify(file, ":t")))
				end

				-- Limit output for large workspaces
				if file_count >= 10 and #matches == 0 then
					print(string.format("... analyzed %d files so far, continuing search ...", file_count))
				end
			end
		end

		print("\n--- Summary ---")
		print("Files analyzed:", file_count)
		print("Files with errors:", error_count)
		print("Total symbols found:", total_symbols)
		print("Matches for '" .. symbol_name .. "':", #matches)

		if #matches == 0 then
			print("❌ NO MATCHES FOUND")
			print("\nTroubleshooting:")
			print("1. Check symbol name spelling")
			print("2. Make sure the file containing the symbol has .tcl extension")
			print("3. Check if the symbol is in a namespace (try namespace::symbol)")
			print("4. Run :TclTestSimple on the file you think contains the symbol")
		else
			print("✅ MATCHES FOUND:")
			for i, match in ipairs(matches) do
				local file_short = vim.fn.fnamemodify(match.file, ":t")
				print(
					string.format(
						"%d. %s '%s' in %s at line %d (%s match)",
						i,
						match.symbol.type,
						match.symbol.name,
						file_short,
						match.symbol.line,
						match.match_type
					)
				)
			end

			if #matches == 1 then
				print("\n🚀 Would jump to:", matches[1].file, "line", matches[1].symbol.line)
			else
				print("\n📋 Would show selection menu with", #matches, "options")
			end
		end

		print("=== Debug Complete ===")
	end, {
		desc = "Debug workspace symbol search",
		nargs = "?",
	})

	-- Command to test a specific file for symbols
	vim.api.nvim_create_user_command("TclTestFile", function(opts)
		if not opts.args or opts.args == "" then
			print("Usage: :TclTestFile <filepath>")
			print("Example: :TclTestFile src/utils.tcl")
			return
		end

		local file_path = opts.args
		local config = require("tcl-lsp.config")
		local tcl = require("tcl-lsp.tcl")

		print("=== Testing File Analysis ===")
		print("File:", file_path)

		-- Check if file exists
		if not tcl.file_exists(file_path) then
			print("❌ File does not exist or is not readable")
			return
		end

		local tclsh_cmd = config.get_tclsh_cmd()

		-- Clear cache for this file
		tcl.invalidate_cache(file_path)

		-- Analyze the file
		local symbols = tcl.analyze_tcl_file(file_path, tclsh_cmd)

		if not symbols then
			print("❌ Analysis failed")
			return
		end

		print("✅ Found", #symbols, "symbols:")

		-- Group by type
		local by_type = {}
		for _, symbol in ipairs(symbols) do
			if not by_type[symbol.type] then
				by_type[symbol.type] = {}
			end
			table.insert(by_type[symbol.type], symbol)
		end

		-- Show grouped results
		for type_name, type_symbols in pairs(by_type) do
			print("\n" .. type_name:upper() .. " (" .. #type_symbols .. "):")
			for _, symbol in ipairs(type_symbols) do
				print(string.format("  Line %d: %s", symbol.line, symbol.name))
			end
		end
	end, {
		desc = "Test symbol analysis on a specific file",
		nargs = 1,
	})

	-- Command to find all instances of a symbol across workspace
	vim.api.nvim_create_user_command("TclFindSymbol", function(opts)
		if not opts.args or opts.args == "" then
			print("Usage: :TclFindSymbol <symbol_name>")
			return
		end

		local symbol_name = opts.args
		local config = require("tcl-lsp.config")
		local tcl = require("tcl-lsp.tcl")
		local utils = require("tcl-lsp.utils")

		local files = vim.fn.glob("**/*.tcl", false, true)
		local tclsh_cmd = config.get_tclsh_cmd()
		local all_matches = {}

		print("=== Finding Symbol Across Workspace ===")
		print("Symbol:", symbol_name)
		print("Searching", #files, "files...")

		for _, file in ipairs(files) do
			local symbols = tcl.analyze_tcl_file(file, tclsh_cmd)
			if symbols then
				for _, symbol in ipairs(symbols) do
					if
						symbol.name:find(symbol_name, 1, true)
						or (symbol.qualified_name and symbol.qualified_name:find(symbol_name, 1, true))
					then
						table.insert(all_matches, {
							symbol = symbol,
							file = file,
						})
					end
				end
			end
		end

		if #all_matches == 0 then
			print("❌ No symbols found containing '" .. symbol_name .. "'")
		else
			print("✅ Found", #all_matches, "symbols:")
			for i, match in ipairs(all_matches) do
				local file_short = vim.fn.fnamemodify(match.file, ":t")
				print(
					string.format(
						"%d. %s '%s' in %s:%d",
						i,
						match.symbol.type,
						match.symbol.name,
						file_short,
						match.symbol.line
					)
				)
			end
		end
	end, {
		desc = "Find all instances of a symbol across workspace",
		nargs = 1,
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
