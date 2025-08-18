local utils = require("tcl-lsp.utils")
local M = {}

-- Cache for file analysis results
local file_cache = {}
local resolution_cache = {}
local pending_analyses = {} -- Track ongoing async operations

-- Cache management functions
local function get_file_mtime(file_path)
	return vim.fn.getftime(file_path)
end

local function is_cache_valid(file_path, cache_entry)
	if not cache_entry then
		return false
	end

	local current_mtime = get_file_mtime(file_path)
	return cache_entry.mtime == current_mtime
end

local function cache_file_analysis(file_path, symbols)
	file_cache[file_path] = {
		symbols = symbols,
		mtime = get_file_mtime(file_path),
		timestamp = os.time(),
	}
end

local function get_cached_analysis(file_path)
	local cache_entry = file_cache[file_path]
	if is_cache_valid(file_path, cache_entry) then
		return cache_entry.symbols
	end
	return nil
end

-- Clear cache for a specific file
function M.invalidate_cache(file_path)
	file_cache[file_path] = nil
	pending_analyses[file_path] = nil

	-- Clear resolution cache entries for this file
	for key, _ in pairs(resolution_cache) do
		if key:match("^" .. vim.pesc(file_path) .. ":") then
			resolution_cache[key] = nil
		end
	end
end

-- Clear all caches
function M.clear_all_caches()
	file_cache = {}
	resolution_cache = {}
	pending_analyses = {}
end

-- Async wrapper for executing TCL scripts
local function execute_tcl_script_async(script_content, tclsh_cmd, callback)
	tclsh_cmd = tclsh_cmd or "tclsh"

	-- Create temporary file
	local temp_file = os.tmpname() .. ".tcl"
	local file = io.open(temp_file, "w")
	if not file then
		callback(nil, false, "Failed to create temporary Tcl script file")
		return
	end

	-- Write script content
	file:write(script_content)
	file:close()

	-- Execute script asynchronously
	local cmd = { tclsh_cmd, temp_file }

	vim.system(cmd, {
		text = true,
		timeout = 10000, -- 10 second timeout
	}, function(result)
		-- Cleanup temp file
		vim.schedule(function()
			os.remove(temp_file)
		end)

		-- Process result in main thread
		vim.schedule(function()
			local success = result.code == 0
			local output = result.stdout or ""
			local error_output = result.stderr or ""

			-- Enhanced error detection
			if not success or error_output ~= "" then
				callback(error_output ~= "" and error_output or output, false, "TCL script execution failed")
				return
			end

			-- Check for common TCL error patterns in output
			if
				output
				and (
					output:match("ERROR:")
					or output:match("can't read")
					or output:match("invalid command")
					or output:match("syntax error")
				)
			then
				callback(output, false, "TCL script reported errors")
				return
			end

			callback(output, true, nil)
		end)
	end)
end

-- Enhanced async TCL file analysis
function M.analyze_tcl_file_async(file_path, tclsh_cmd, callback)
	-- Validate inputs
	if not file_path or not callback then
		if callback then
			callback(nil, "Invalid parameters")
		end
		return
	end

	-- Check cache first
	local cached_symbols = get_cached_analysis(file_path)
	if cached_symbols then
		-- Return cached result asynchronously
		vim.schedule(function()
			callback(cached_symbols, nil)
		end)
		return
	end

	-- Check if analysis is already pending for this file
	if pending_analyses[file_path] then
		-- Add callback to existing pending analysis
		local existing_callbacks = pending_analyses[file_path]
		table.insert(existing_callbacks, callback)
		return
	end

	-- Start new analysis
	pending_analyses[file_path] = { callback }

	-- Escape the file path properly for TCL
	local escaped_path = file_path:gsub("\\", "\\\\"):gsub('"', '\\"')

	-- Improved analysis script with better error handling and symbol detection
	local analysis_script = string.format(
		[[
# Enhanced TCL Symbol Analysis Script
set file_path "%s"

# Error handling wrapper
proc safe_analyze {} {
    global file_path
    
    # Read the file
    if {[catch {
        set fp [open $file_path r]
        set content [read $fp]
        close $fp
    } err]} {
        puts "ERROR:Cannot read file: $err"
        return
    }

    # Split into lines for analysis
    set lines [split $content "\n"]
    set line_num 0
    set current_namespace ""
    set namespace_stack [list]
    set in_proc_body 0
    set proc_brace_level 0
    set global_brace_level 0

    foreach line $lines {
        incr line_num
        set original_line $line
        set trimmed [string trim $line]
        
        # Skip empty lines and comments
        if {$trimmed eq "" || [string index $trimmed 0] eq "#"} {
            continue
        }
        
        # Count braces for scope tracking
        set open_braces [regexp -all {\{} $line]
        set close_braces [regexp -all {\}} $line]
        set global_brace_level [expr {$global_brace_level + $open_braces - $close_braces}]
        
        # Namespace handling with better brace tracking
        if {[regexp {^\s*namespace\s+eval\s+([a-zA-Z_:][a-zA-Z0-9_:]*)\s*\{?} $line match ns_name]} {
            lappend namespace_stack $current_namespace
            set current_namespace $ns_name
            puts "SYMBOL:namespace:$ns_name:$line_num:$original_line:$current_namespace"
        }
        
        # Enhanced procedure detection - handle various formats
        if {[regexp {^\s*proc\s+([a-zA-Z_:][a-zA-Z0-9_:]*)\s*\{([^}]*)\}\s*\{?} $line match proc_name proc_args] ||
            [regexp {^\s*proc\s+([a-zA-Z_:][a-zA-Z0-9_:]*)\s+\{([^}]*)\}\s*\{?} $line match proc_name proc_args]} {
            
            # Create qualified name
            set qualified_name $proc_name
            if {$current_namespace ne "" && ![string match "::*" $proc_name]} {
                set qualified_name "${current_namespace}::$proc_name"
            }
            
            # Clean up arguments
            set clean_args [string trim $proc_args]
            puts "SYMBOL:procedure:$proc_name:$line_num:$original_line:$qualified_name:$clean_args:$current_namespace"
            
            set in_proc_body 1
            set proc_brace_level $global_brace_level
        }
        
        # Variable definitions - enhanced patterns
        if {[regexp {^\s*set\s+([a-zA-Z_:][a-zA-Z0-9_:]*)\s+(.*)$} $line match var_name var_value]} {
            set qualified_name $var_name
            if {$current_namespace ne "" && ![string match "::*" $var_name]} {
                set qualified_name "${current_namespace}::$var_name"
            }
            
            set scope "global"
            if {$in_proc_body} {
                set scope "local"
            } elseif {$current_namespace ne ""} {
                set scope "namespace"
            }
            
            puts "SYMBOL:variable:$var_name:$line_num:$original_line:$qualified_name:$scope:$current_namespace"
        }
        
        # Enhanced global variable detection
        if {[regexp {^\s*global\s+(.+)$} $line match globals]} {
            # Split by whitespace and process each global
            set global_vars [regexp -all -inline {\S+} $globals]
            foreach global_var $global_vars {
                if {$global_var ne ""} {
                    puts "SYMBOL:global:$global_var:$line_num:$original_line:$global_var::global"
                }
            }
        }
        
        # Variable namespace declarations
        if {[regexp {^\s*variable\s+([a-zA-Z_:][a-zA-Z0-9_:]*)} $line match var_name]} {
            set qualified_name $var_name
            if {$current_namespace ne "" && ![string match "::*" $var_name]} {
                set qualified_name "${current_namespace}::$var_name"
            }
            puts "SYMBOL:namespace_variable:$var_name:$line_num:$original_line:$qualified_name:namespace:$current_namespace"
        }
        
        # Array declarations
        if {[regexp {^\s*array\s+set\s+([a-zA-Z_:][a-zA-Z0-9_:]*)} $line match array_name]} {
            set qualified_name $array_name
            if {$current_namespace ne "" && ![string match "::*" $array_name]} {
                set qualified_name "${current_namespace}::$array_name"
            }
            puts "SYMBOL:array:$array_name:$line_num:$original_line:$qualified_name:array:$current_namespace"
        }
        
        # Package commands
        if {[regexp {^\s*package\s+(require|provide)\s+([a-zA-Z_:][a-zA-Z0-9_:]*)\s*(.*)?$} $line match cmd pkg_name version]} {
            puts "SYMBOL:package:$pkg_name:$line_num:$original_line:$pkg_name:$cmd:package"
        }
        
        # Source commands
        if {[regexp {^\s*source\s+(.+)$} $line match source_file]} {
            set clean_file [string trim $source_file "\"'{}"]
            puts "SYMBOL:source:$clean_file:$line_num:$original_line:$clean_file:source:$current_namespace"
        }
        
        # Track end of procedure bodies
        if {$in_proc_body && $global_brace_level <= $proc_brace_level} {
            set in_proc_body 0
        }
        
        # Track end of namespace blocks
        if {$global_brace_level <= 0 && [llength $namespace_stack] > 0} {
            set current_namespace [lindex $namespace_stack end]
            set namespace_stack [lrange $namespace_stack 0 end-1]
        }
    }
    
    puts "ANALYSIS_COMPLETE:SUCCESS"
}

# Execute the analysis
safe_analyze
]],
		escaped_path
	)

	-- Execute analysis asynchronously
	execute_tcl_script_async(analysis_script, tclsh_cmd, function(result, success, error_msg)
		local callbacks = pending_analyses[file_path] or {}
		pending_analyses[file_path] = nil

		if not success then
			local err_msg = error_msg or "TCL analysis script failed"
			if result then
				err_msg = err_msg .. ": " .. tostring(result)
			end

			-- Notify all waiting callbacks of failure
			for _, cb in ipairs(callbacks) do
				cb(nil, err_msg)
			end
			return
		end

		-- Check if analysis completed successfully
		if not result:match("ANALYSIS_COMPLETE:SUCCESS") then
			local warn_msg = "TCL analysis did not complete successfully"
			-- Still try to parse what we got
		end

		local symbols = {}
		for line in result:gmatch("[^\n]+") do
			-- Enhanced parsing: SYMBOL:type:name:line:text:qualified_name:extra1:extra2
			local parts = {}
			local start = 1
			for i = 1, 8 do -- Extract up to 8 parts
				local colon_pos = string.find(line, ":", start)
				if colon_pos then
					table.insert(parts, string.sub(line, start, colon_pos - 1))
					start = colon_pos + 1
				else
					-- Last part (rest of the line)
					table.insert(parts, string.sub(line, start))
					break
				end
			end

			if parts[1] == "SYMBOL" and #parts >= 5 then
				local symbol = {
					type = parts[2],
					name = parts[3],
					line = tonumber(parts[4]),
					text = parts[5],
					qualified_name = parts[6] or parts[3],
					scope = parts[7] or "",
					context = parts[8] or "",
				}

				-- Add additional metadata based on type
				if symbol.type == "procedure" then
					symbol.args = parts[7] or ""
					symbol.namespace_context = parts[8] or ""
				elseif symbol.type == "variable" or symbol.type == "namespace_variable" then
					symbol.variable_scope = parts[7] or "global"
					symbol.namespace_context = parts[8] or ""
				end

				table.insert(symbols, symbol)
			end
		end

		-- Cache the results
		cache_file_analysis(file_path, symbols)

		-- Notify all waiting callbacks of success
		for _, cb in ipairs(callbacks) do
			cb(symbols, nil)
		end
	end)
end

-- Synchronous wrapper for backward compatibility
function M.analyze_tcl_file(file_path, tclsh_cmd)
	-- Check cache first for immediate return
	local cached_symbols = get_cached_analysis(file_path)
	if cached_symbols then
		return cached_symbols
	end

	-- For synchronous calls, we'll use a blocking approach with a timeout
	local result = nil
	local error_msg = nil
	local completed = false

	M.analyze_tcl_file_async(file_path, tclsh_cmd, function(symbols, err)
		result = symbols
		error_msg = err
		completed = true
	end)

	-- Wait for completion with timeout
	local timeout = 5000 -- 5 seconds
	local start_time = vim.loop.now()

	while not completed and (vim.loop.now() - start_time) < timeout do
		vim.wait(10) -- Wait 10ms between checks
	end

	if not completed then
		return nil -- Timeout occurred
	end

	if error_msg then
		vim.notify("TCL analysis failed: " .. error_msg, vim.log.levels.ERROR)
		return nil
	end

	return result
end

-- Async version of get TCL info
function M.get_tcl_info_async(tclsh_cmd, callback)
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

	execute_tcl_script_async(info_script, tclsh_cmd, function(result, success, error_msg)
		if not success then
			callback(nil, error_msg)
			return
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

		callback(info, nil)
	end)
end

-- Synchronous wrapper for backward compatibility
function M.get_tcl_info(tclsh_cmd)
	local result = nil
	local completed = false

	M.get_tcl_info_async(tclsh_cmd, function(info, err)
		result = info
		completed = true
	end)

	-- Wait for completion with timeout
	local timeout = 3000 -- 3 seconds
	local start_time = vim.loop.now()

	while not completed and (vim.loop.now() - start_time) < timeout do
		vim.wait(10)
	end

	return result
end

-- Async version of JSON functionality test
function M.test_json_functionality_async(tclsh_cmd, callback)
	local json_test_script = [[
if {[catch {package require json} err]} {
    puts "JSON_ERROR:$err"
    exit 1
} else {
    puts "JSON_SUCCESS"
    puts "RESULT:JSON package is available"
}
]]

	execute_tcl_script_async(json_test_script, tclsh_cmd, function(result, success, error_msg)
		if success and result and result:match("JSON_SUCCESS") then
			callback(true, "JSON package is working", nil)
		else
			local err_msg = "JSON test failed"
			if result and result:match("JSON_ERROR:(.+)") then
				err_msg = result:match("JSON_ERROR:(.+)")
			elseif error_msg then
				err_msg = error_msg
			end
			callback(false, err_msg, nil)
		end
	end)
end

-- Synchronous wrapper for backward compatibility
function M.test_json_functionality(tclsh_cmd)
	local success_result = nil
	local message_result = nil
	local completed = false

	M.test_json_functionality_async(tclsh_cmd, function(success, message, err)
		success_result = success
		message_result = message
		completed = true
	end)

	-- Wait for completion with timeout
	local timeout = 3000 -- 3 seconds
	local start_time = vim.loop.now()

	while not completed and (vim.loop.now() - start_time) < timeout do
		vim.wait(10)
	end

	if not completed then
		return false, "Timeout"
	end

	return success_result, message_result
end

-- Async debug function
function M.debug_symbols_async(file_path, tclsh_cmd, callback)
	-- Force cache invalidation for debugging
	M.invalidate_cache(file_path)

	M.analyze_tcl_file_async(file_path, tclsh_cmd, function(symbols, err)
		if err then
			callback(nil, err)
			return
		end

		if not symbols then
			callback(nil, "No symbols found - analysis failed")
			return
		end

		-- Format debug information
		local debug_info = {
			count = #symbols,
			symbols = symbols,
			message = "Found " .. #symbols .. " symbols",
		}

		callback(debug_info, nil)
	end)
end

-- Synchronous debug wrapper
function M.debug_symbols(file_path, tclsh_cmd)
	-- Force cache invalidation for debugging
	M.invalidate_cache(file_path)

	local symbols = M.analyze_tcl_file(file_path, tclsh_cmd)

	if not symbols then
		vim.notify("DEBUG: No symbols found - analysis failed", vim.log.levels.ERROR)
		return
	end

	vim.notify("DEBUG: Found " .. #symbols .. " symbols:", vim.log.levels.INFO)
	for i, symbol in ipairs(symbols) do
		local debug_msg = string.format(
			"  %d. %s '%s' at line %d (qualified: %s, scope: %s)",
			i,
			symbol.type,
			symbol.name,
			symbol.line,
			symbol.qualified_name or "none",
			symbol.scope or "none"
		)
		print(debug_msg)
	end

	return symbols
end

-- Initialize the TCL environment asynchronously
function M.initialize_tcl_environment_async(tclsh_cmd, callback)
	local init_script = [[
# Test basic TCL functionality
puts "TCL_INIT_START"

# Check basic commands
if {[catch {set test_var "hello"} err]} {
    puts "ERROR: Basic set command failed: $err"
    exit 1
}

# Check if we can create procedures
if {[catch {
    proc test_proc {} {
        return "test"
    }
    test_proc
} err]} {
    puts "ERROR: Procedure creation failed: $err"
    exit 1
}

puts "TCL_INIT_SUCCESS"
]]

	execute_tcl_script_async(init_script, tclsh_cmd, function(result, success, error_msg)
		if success and result and result:match("TCL_INIT_SUCCESS") then
			callback(true, "TCL environment initialized successfully")
		else
			callback(false, error_msg or result or "Failed to initialize TCL environment")
		end
	end)
end

-- Synchronous wrapper for backward compatibility
function M.initialize_tcl_environment(tclsh_cmd)
	local success_result = nil
	local message_result = nil
	local completed = false

	M.initialize_tcl_environment_async(tclsh_cmd, function(success, message)
		success_result = success
		message_result = message
		completed = true
	end)

	-- Wait for completion with timeout
	local timeout = 3000 -- 3 seconds
	local start_time = vim.loop.now()

	while not completed and (vim.loop.now() - start_time) < timeout do
		vim.wait(10)
	end

	if not completed then
		return false, "Timeout during TCL environment initialization"
	end

	return success_result, message_result
end

-- Get cache statistics
function M.get_cache_stats()
	return {
		file_cache_entries = vim.tbl_count(file_cache),
		resolution_cache_entries = vim.tbl_count(resolution_cache),
		pending_analyses = vim.tbl_count(pending_analyses),
		total_memory_usage = "~"
			.. math.floor((vim.tbl_count(file_cache) + vim.tbl_count(resolution_cache)) * 0.1)
			.. "KB",
	}
end

-- Batch analyze multiple files asynchronously
function M.batch_analyze_files_async(file_paths, tclsh_cmd, callback)
	local results = {}
	local completed = 0
	local total = #file_paths

	if total == 0 then
		callback({}, nil)
		return
	end

	for _, file_path in ipairs(file_paths) do
		M.analyze_tcl_file_async(file_path, tclsh_cmd, function(symbols, err)
			completed = completed + 1

			if symbols then
				results[file_path] = symbols
			else
				results[file_path] = nil
			end

			-- Check if all analyses are complete
			if completed == total then
				callback(results, nil)
			end
		end)
	end
end

return M
