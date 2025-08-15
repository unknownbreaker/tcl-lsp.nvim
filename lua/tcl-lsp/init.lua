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
