local utils = require("tcl-lsp.utils")
local M = {}

-- Cache for file analysis results
local file_cache = {}
local resolution_cache = {}

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

-- Simplified semantic TCL analysis that avoids complex nested strings
function M.semantic_tcl_analysis(file_path, tclsh_cmd)
	print("DEBUG: Running simplified semantic TCL analysis")

	local escaped_path = file_path:gsub("\\", "\\\\"):gsub('"', '\\"')

	-- Much simpler approach: just use TCL's introspection on the sourced file
	local semantic_script = string.format(
		[[
# Simple Semantic Analysis - just source and introspect
set file_path "%s"

# Source the file (in current interpreter, but catch errors)
if {[catch {source $file_path} err]} {
    puts "WARNING: Could not source file: $err"
    puts "PARTIAL_ANALYSIS"
} else {
    puts "FULL_ANALYSIS"
}

# Get all procedures that were defined
foreach proc_name [info procs] {
    # Skip built-in procs that we don't care about
    if {$proc_name ni {unknown auto_execok auto_import auto_qualify}} {
        set proc_args ""
        if {![catch {info args $proc_name} args]} {
            set proc_args [join $args " "]
        }
        puts "SEMANTIC_PROC|$proc_name|$proc_args|[namespace current]"
    }
}

# Get all global variables
foreach var_name [info globals] {
    if {[info exists ::$var_name]} {
        puts "SEMANTIC_VAR|$var_name|global|::"
    }
}

# Get all namespaces
foreach ns [namespace children ::] {
    if {$ns ne "::tcl"} {
        puts "SEMANTIC_NS|$ns"
        
        # Get procs in this namespace
        foreach ns_proc [info procs ${ns}::*] {
            set proc_args ""
            if {![catch {info args $ns_proc} args]} {
                set proc_args [join $args " "]
            }
            puts "SEMANTIC_PROC|$ns_proc|$proc_args|$ns"
        }
        
        # Get vars in this namespace  
        foreach ns_var [info vars ${ns}::*] {
            puts "SEMANTIC_VAR|$ns_var|namespace|$ns"
        }
    }
}

puts "SEMANTIC_COMPLETE"
]],
		escaped_path
	)

	local result, success = utils.execute_tcl_script(semantic_script, tclsh_cmd)

	if not (result and success) then
		print("DEBUG: Simplified semantic analysis failed:", result or "nil")
		return nil
	end

	print("DEBUG: Simplified semantic analysis completed")

	local symbols = {}
	local symbol_count = 0

	-- Parse the simpler output format
	for line in result:gmatch("[^\n]+") do
		if line:match("^SEMANTIC_PROC|") then
			local parts = {}
			for part in line:gmatch("([^|]*)") do
				table.insert(parts, part)
			end

			if #parts >= 4 then
				local symbol = {
					type = "procedure",
					name = parts[2],
					line = 1, -- We don't have line numbers from introspection
					args = parts[3],
					context = parts[4],
					scope = "semantic",
					proc_context = "",
					text = "",
					qualified_name = parts[2],
					method = "semantic_simple",
				}

				table.insert(symbols, symbol)
				symbol_count = symbol_count + 1
			end
		elseif line:match("^SEMANTIC_VAR|") then
			local parts = {}
			for part in line:gmatch("([^|]*)") do
				table.insert(parts, part)
			end

			if #parts >= 4 then
				local symbol = {
					type = "variable",
					name = parts[2],
					line = 1,
					args = "",
					context = parts[4],
					scope = parts[3], -- "global" or "namespace"
					proc_context = "",
					text = "",
					qualified_name = parts[2],
					method = "semantic_simple",
				}

				table.insert(symbols, symbol)
				symbol_count = symbol_count + 1
			end
		elseif line:match("^SEMANTIC_NS|") then
			local parts = {}
			for part in line:gmatch("([^|]*)") do
				table.insert(parts, part)
			end

			if #parts >= 2 then
				local symbol = {
					type = "namespace",
					name = parts[2],
					line = 1,
					args = "",
					context = "",
					scope = "namespace",
					proc_context = "",
					text = "",
					qualified_name = parts[2],
					method = "semantic_simple",
				}

				table.insert(symbols, symbol)
				symbol_count = symbol_count + 1
			end
		end
	end

	print("DEBUG: Simplified semantic analysis found", symbol_count, "symbols")
	return symbols
end

-- Enhanced analyze_tcl_file that combines semantic + text analysis
function M.analyze_tcl_file(file_path, tclsh_cmd)
	-- Check cache first
	local cached_symbols = get_cached_analysis(file_path)
	if cached_symbols then
		print("DEBUG: Using cached symbols for", file_path, "- found", #cached_symbols, "symbols")
		return cached_symbols
	end

	print("DEBUG: Analyzing file:", file_path)

	-- Periodically clean up old cache entries
	if math.random(1, 20) == 1 then -- 5% chance
		cleanup_cache()
	end

	-- Improved analysis script with better error handling and more flexible regex
	local escaped_path = file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
	local analysis_script = string.format(
		[[
# Enhanced TCL Symbol Analysis Script  
set file_path "%s"

puts "DEBUG: Starting analysis of $file_path"

# Read the file with error handling
if {[catch {
    set fp [open $file_path r]
    set content [read $fp]
    close $fp
    puts "DEBUG: Successfully read file, [string length $content] characters"
} err]} {
    puts "ERROR: Cannot read file: $err"
    exit 1
}

# Check if file is empty
if {[string length [string trim $content] ] == 0} {
    puts "DEBUG: File is empty"
    puts "ANALYSIS_COMPLETE"
    exit 0
}

# Split into lines for analysis
set lines [split $content "\n"]
set total_lines [llength $lines]
puts "DEBUG: Processing $total_lines lines"

set line_num 0
set current_namespace ""
set symbols_found 0
set in_proc 0
set brace_depth 0

# Parse each line to find symbols
foreach line $lines {
    incr line_num
    set original_line $line
    set trimmed [string trim $line]
    
    # Skip comments and empty lines
    if {$trimmed eq "" || [string index $trimmed 0] eq "#"} {
        continue
    }
    
    # Track brace depth for better context awareness
    set open_braces [regexp -all {\{} $line]
    set close_braces [regexp -all {\}} $line]
    set brace_depth [expr {$brace_depth + $open_braces - $close_braces}]
    
    # Debug every 50th line to show progress
    if {$line_num %% 50 == 0} {
        puts "DEBUG: Processing line $line_num: [string range $trimmed 0 50]..."
    }
    
    # Find namespace definitions (improved regex)
    if {[regexp {^\s*namespace\s+eval\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match ns_name]} {
        set current_namespace $ns_name
        puts "SYMBOL:namespace:$ns_name:$line_num:$original_line"
        incr symbols_found
        puts "DEBUG: Found namespace '$ns_name' at line $line_num"
    }
    
    # Find procedure definitions (improved to handle multi-line and various styles)
    if {[regexp {^\s*proc\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match proc_name]} {
        set in_proc 1
        # Create qualified name if in namespace
        if {$current_namespace ne "" && ![string match "*::*" $proc_name]} {
            set full_name "$current_namespace\::$proc_name"
        } else {
            set full_name $proc_name
        }
        puts "SYMBOL:procedure:$full_name:$line_num:$original_line"
        incr symbols_found
        puts "DEBUG: Found procedure '$full_name' at line $line_num"
        
        # Also add local name if different
        if {$full_name ne $proc_name} {
            puts "SYMBOL:procedure_local:$proc_name:$line_num:$original_line"
            incr symbols_found
        }
    }
    
    # End of procedure (when we hit closing brace at appropriate level)
    if {$in_proc && $brace_depth <= 0} {
        set in_proc 0
    }
    
    # Find variable assignments (improved regex to handle more cases)
    if {[regexp {^\s*set\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match var_name]} {
        # Create qualified name if in namespace
        if {$current_namespace ne "" && ![string match "*::*" $var_name]} {
            set full_name "$current_namespace\::$var_name"
        } else {
            set full_name $var_name
        }
        puts "SYMBOL:variable:$full_name:$line_num:$original_line"
        incr symbols_found
        
        # Also add local name if different
        if {$full_name ne $var_name} {
            puts "SYMBOL:variable_local:$var_name:$line_num:$original_line"
            incr symbols_found
        }
    }
    
    # Find global variables (improved to handle multiple globals on one line)
    if {[regexp {^\s*global\s+(.+)} $line match globals]} {
        # Split on whitespace and process each variable
        foreach global_var [regexp -all -inline {[a-zA-Z_][a-zA-Z0-9_:]*} $globals]} {
            if {$global_var ne ""} {
                puts "SYMBOL:global:$global_var:$line_num:$original_line"
                incr symbols_found
                puts "DEBUG: Found global variable '$global_var' at line $line_num"
            }
        }
    }
    
    # Find package commands (improved regex to handle more package names)
    if {[regexp {^\s*package\s+(require|provide)\s+([a-zA-Z_][a-zA-Z0-9_.-]*)} $line match cmd pkg_name]} {
        puts "SYMBOL:package:$pkg_name:$line_num:$original_line"
        incr symbols_found
        puts "DEBUG: Found package '$pkg_name' ($cmd) at line $line_num"
    }
    
    # Find source commands (improved to handle various quote styles)
    if {[regexp {^\s*source\s+(.+)$} $line match source_file]} {
        set clean_file [string trim $source_file "\"'\{\}"]
        puts "SYMBOL:source:$clean_file:$line_num:$original_line"
        incr symbols_found
        puts "DEBUG: Found source '$clean_file' at line $line_num"
    }
    
    # Find array definitions
    if {[regexp {^\s*array\s+set\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match array_name]} {
        puts "SYMBOL:array:$array_name:$line_num:$original_line"
        incr symbols_found
        puts "DEBUG: Found array '$array_name' at line $line_num"
    }
    
    # Find upvar commands (variable aliasing)
    if {[regexp {^\s*upvar\s+.*\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match var_name]} {
        puts "SYMBOL:upvar:$var_name:$line_num:$original_line"
        incr symbols_found
        puts "DEBUG: Found upvar '$var_name' at line $line_num"
    }
}

puts "DEBUG: Analysis complete. Found $symbols_found symbols total."
puts "ANALYSIS_COMPLETE"
]],
		escaped_path
	)

	local result, success = utils.execute_tcl_script(analysis_script, tclsh_cmd)

	print("DEBUG: TCL execution result:")
	print("  Success:", success)
	print("  Result length:", result and #result or "nil")
	if result then
		print("  First 500 chars:", result:sub(1, 500))
	end

	if not (result and success) then
		print("DEBUG: TCL script execution failed")
		print("DEBUG: Result:", result or "nil")
		print("DEBUG: Success:", success)
		return nil
	end

	local symbols = {}
	local debug_lines = {}

	-- More robust parsing
	for line in result:gmatch("[^\n]+") do
		if line:match("^DEBUG:") then
			table.insert(debug_lines, line)
		elseif line:match("^SYMBOL:") then
			-- Parse: SYMBOL:type:name:line:text
			local symbol_type, name, line_num, text = line:match("SYMBOL:([^:]+):([^:]+):([^:]+):(.+)")
			if symbol_type and name and line_num and text then
				local symbol = {
					type = symbol_type,
					name = name,
					line = tonumber(line_num),
					text = text,
					context = "",
					scope = "",
					args = "",
					qualified_name = name,
				}
				table.insert(symbols, symbol)
				print("DEBUG: Parsed symbol:", symbol.type, symbol.name, "at line", symbol.line)
			else
				print("DEBUG: Failed to parse symbol line:", line)
			end
		end
	end

	-- Print debug information
	print("DEBUG: TCL script debug output:")
	for _, debug_line in ipairs(debug_lines) do
		print("  " .. debug_line)
	end

	print("DEBUG: Final parsed symbols:", #symbols)
	for i, symbol in ipairs(symbols) do
		print("  " .. i .. ": " .. symbol.type .. " '" .. symbol.name .. "' at line " .. symbol.line)
	end

	-- Cache the results
	cache_file_analysis(file_path, symbols)

	return symbols
end

-- Enhanced text analysis that focuses on local variables and parameters
function M.enhanced_text_analysis(file_path)
	print("DEBUG: Running enhanced text analysis for local symbols")

	local file = io.open(file_path, "r")
	if not file then
		print("DEBUG: Cannot open file for text analysis")
		return {}
	end

	local symbols = {}
	local line_num = 0
	local current_namespace = ""
	local current_proc = ""
	local current_proc_line = 0
	local brace_level = 0
	local proc_brace_level = 0

	for line in file:lines() do
		line_num = line_num + 1
		local trimmed = line:match("^%s*(.-)%s*$")

		-- Skip empty lines and comments
		if trimmed == "" or trimmed:match("^#") then
			goto continue
		end

		-- Track brace levels
		local open_braces = 0
		local close_braces = 0
		for c in line:gmatch(".") do
			if c == "{" then
				open_braces = open_braces + 1
			elseif c == "}" then
				close_braces = close_braces + 1
			end
		end
		brace_level = brace_level + open_braces - close_braces

		-- Namespace detection
		local ns_name = trimmed:match("^namespace%s+eval%s+([%w_:]+)")
		if ns_name then
			current_namespace = ns_name
			table.insert(symbols, {
				type = "namespace",
				name = ns_name,
				line = line_num,
				scope = "namespace",
				context = "",
				proc_context = "",
				text = trimmed,
				qualified_name = ns_name,
				method = "text_analysis",
			})
		end

		-- Procedure detection with parameter extraction
		local proc_name, proc_args = trimmed:match("^proc%s+([%w_:]+)%s*{([^}]*)}")
		if proc_name then
			local qualified_name = proc_name
			if current_namespace ~= "" and not proc_name:match("::") then
				qualified_name = current_namespace .. "::" .. proc_name
			end

			table.insert(symbols, {
				type = "procedure",
				name = qualified_name,
				line = line_num,
				scope = "global",
				context = current_namespace,
				proc_context = "",
				text = trimmed,
				qualified_name = qualified_name,
				method = "text_analysis",
				args = proc_args,
			})

			-- Extract parameters from the procedure
			if proc_args and proc_args:match("%S") then
				-- Simple parameter extraction
				for param in proc_args:gmatch("[%w_]+") do
					table.insert(symbols, {
						type = "parameter",
						name = param,
						line = line_num,
						scope = "local",
						context = current_namespace,
						proc_context = qualified_name,
						text = trimmed,
						qualified_name = param,
						method = "text_analysis",
					})
					print("DEBUG: Found parameter:", param, "in proc:", qualified_name)
				end
			end

			current_proc = qualified_name
			current_proc_line = line_num
			proc_brace_level = brace_level
		end

		-- Variable assignments (local and global)
		local var_name = trimmed:match("^set%s+([%w_:]+)")
		if var_name then
			local scope = "global"
			local proc_context = ""

			if current_proc ~= "" and brace_level > 0 then
				scope = "local"
				proc_context = current_proc
			end

			local qualified_name = var_name
			if current_namespace ~= "" and scope ~= "local" and not var_name:match("::") then
				qualified_name = current_namespace .. "::" .. var_name
			end

			table.insert(symbols, {
				type = "variable",
				name = qualified_name,
				line = line_num,
				scope = scope,
				context = current_namespace,
				proc_context = proc_context,
				text = trimmed,
				qualified_name = qualified_name,
				method = "text_analysis",
			})

			if scope == "local" then
				print("DEBUG: Found local variable:", var_name, "in proc:", current_proc)
			end
		end

		-- Variable usage detection (for $varname)
		if current_proc ~= "" and brace_level > 0 then
			for var_name in line:gmatch("%$([%w_]+)") do
				table.insert(symbols, {
					type = "local_var_usage",
					name = var_name,
					line = line_num,
					scope = "local",
					context = current_namespace,
					proc_context = current_proc,
					text = trimmed,
					qualified_name = var_name,
					method = "text_analysis",
				})
				print("DEBUG: Found variable usage:", var_name, "in proc:", current_proc, "at line:", line_num)
			end
		end

		-- Global variables
		local globals = trimmed:match("^global%s+(.+)")
		if globals then
			for global_var in globals:gmatch("[%w_:]+") do
				table.insert(symbols, {
					type = "global",
					name = global_var,
					line = line_num,
					scope = "global",
					context = "",
					proc_context = current_proc,
					text = trimmed,
					qualified_name = global_var,
					method = "text_analysis",
				})
			end
		end

		-- Reset procedure context when exiting
		if close_braces > 0 and current_proc ~= "" then
			if brace_level <= proc_brace_level then
				print("DEBUG: Exiting procedure:", current_proc, "at line:", line_num)
				current_proc = ""
				current_proc_line = 0
			end
		end

		::continue::
	end

	file:close()

	print("DEBUG: Enhanced text analysis found", #symbols, "symbols")
	return symbols
end

-- Improved fallback analysis using pure Lua
function M.fallback_analysis(file_path)
	print("DEBUG: Running Lua-based fallback analysis")

	local file = io.open(file_path, "r")
	if not file then
		print("DEBUG: Cannot open file for fallback analysis")
		return {}
	end

	local symbols = {}
	local line_num = 0
	local current_namespace = ""

	for line in file:lines() do
		line_num = line_num + 1
		local trimmed = line:match("^%s*(.-)%s*$")

		-- Skip empty lines and comments
		if trimmed == "" or trimmed:match("^#") then
			goto continue
		end

		-- Namespace detection
		local ns_name = trimmed:match("^namespace%s+eval%s+([%w_:]+)")
		if ns_name then
			current_namespace = ns_name
			table.insert(symbols, {
				type = "namespace",
				name = ns_name,
				line = line_num,
				scope = "namespace",
				context = "",
				text = trimmed,
				qualified_name = ns_name,
				method = "lua_fallback",
			})
			print("DEBUG: Fallback found namespace:", ns_name)
		end

		-- Procedure detection
		local proc_name = trimmed:match("^proc%s+([%w_:]+)")
		if proc_name then
			local qualified_name = proc_name
			if current_namespace ~= "" and not proc_name:match("::") then
				qualified_name = current_namespace .. "::" .. proc_name
			end

			table.insert(symbols, {
				type = "procedure",
				name = qualified_name,
				line = line_num,
				scope = "global",
				context = current_namespace,
				text = trimmed,
				qualified_name = qualified_name,
				method = "lua_fallback",
			})
			print("DEBUG: Fallback found procedure:", qualified_name)
		end

		-- Variable detection
		local var_name = trimmed:match("^set%s+([%w_:]+)")
		if var_name then
			local qualified_name = var_name
			if current_namespace ~= "" and not var_name:match("::") then
				qualified_name = current_namespace .. "::" .. var_name
			end

			table.insert(symbols, {
				type = "variable",
				name = qualified_name,
				line = line_num,
				scope = "global",
				context = current_namespace,
				text = trimmed,
				qualified_name = qualified_name,
				method = "lua_fallback",
			})
			print("DEBUG: Fallback found variable:", qualified_name)
		end

		-- Global variable detection
		local globals = trimmed:match("^global%s+(.+)")
		if globals then
			for global_var in globals:gmatch("[%w_:]+") do
				table.insert(symbols, {
					type = "global",
					name = global_var,
					line = line_num,
					scope = "global",
					context = "",
					text = trimmed,
					qualified_name = global_var,
					method = "lua_fallback",
				})
				print("DEBUG: Fallback found global:", global_var)
			end
		end

		::continue::
	end

	file:close()

	print("DEBUG: Fallback analysis found", #symbols, "symbols")
	return symbols
end

-- Keep all your existing functions...

-- Get Tcl system information
function M.get_tcl_info(tclsh_cmd)
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

	local result, success = utils.execute_tcl_script(info_script, tclsh_cmd)
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
function M.test_json_functionality(tclsh_cmd)
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

	local result, success = utils.execute_tcl_script(json_test_script, tclsh_cmd)

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

-- Find symbol references
function M.find_symbol_references(file_path, symbol_name, tclsh_cmd)
	local escaped_path = file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
	local escaped_symbol = symbol_name:gsub("\\", "\\\\"):gsub('"', '\\"')

	local reference_script = string.format(
		[[
set target_word "%s"
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

foreach line $lines {
    incr line_num
    
    if {[regexp "\\y$target_word\\y" $line]} {
        set context "usage"
        if {[regexp "^\\s*proc\\s+$target_word\\s" $line]} {
            set context "definition:procedure"
        } elseif {[regexp "^\\s*set\\s+$target_word\\s" $line]} {
            set context "definition:variable"
        } elseif {[regexp "\\$$target_word\\y" $line]} {
            set context "variable_usage"
        }
        
        puts "REF|$context|$line_num|$line"
    }
}

puts "REFERENCES_COMPLETE"
]],
		escaped_symbol,
		escaped_path
	)

	local result, success = utils.execute_tcl_script(reference_script, tclsh_cmd)

	if not (result and success) then
		return nil
	end

	local references = {}
	for line in result:gmatch("[^\n]+") do
		if line:match("^REF|") then
			local parts = {}
			for part in line:gmatch("([^|]*)") do
				table.insert(parts, part)
			end

			if #parts >= 4 then
				table.insert(references, {
					context = parts[2] or "usage",
					line = tonumber(parts[3]) or 1,
					text = utils.trim(parts[4] or ""),
					method = "simplified",
				})
			end
		end
	end

	return references
end

-- Check builtin commands
function M.check_builtin_command(symbol_name, tclsh_cmd)
	local builtin_check_script = string.format(
		[[
set word "%s"

if {[info commands $word] ne ""} {
    if {[catch {info args $word} args_result]} {
        puts "BUILTIN_COMMAND|$word"
    } else {
        puts "BUILTIN_PROC|$word|$args_result"
    }
} else {
    puts "NOT_BUILTIN"
}
]],
		symbol_name:gsub("\\", "\\\\"):gsub('"', '\\"')
	)

	local result, success = utils.execute_tcl_script(builtin_check_script, tclsh_cmd)

	if not (result and success) then
		return nil
	end

	if result:match("BUILTIN_PROC|([^|]+)|(.+)") then
		local cmd, args = result:match("BUILTIN_PROC|([^|]+)|(.+)")
		return {
			type = "builtin_proc",
			name = cmd,
			args = args,
			description = string.format("%s %s\nBuilt-in TCL procedure", cmd, args),
		}
	elseif result:match("BUILTIN_COMMAND|(.+)") then
		local cmd = result:match("BUILTIN_COMMAND|(.+)")
		return {
			type = "builtin_command",
			name = cmd,
			description = cmd .. "\nBuilt-in TCL command",
		}
	end

	return nil
end

-- Get TCL command documentation
function M.get_command_documentation(command)
	local tcl_docs = {
		puts = "puts ?-nonewline? ?channelId? string\nWrite string to output channel",
		set = "set varName ?value?\nSet or get variable value",
		proc = "proc name args body\nDefine a new procedure",
		["if"] = "if expr1 ?then? body1 ?elseif expr2 ?then? body2? ... ?else? ?bodyN?\nConditional execution",
		["for"] = "for start test next body\nLoop with initialization, test, and increment",
		["while"] = "while test body\nLoop while test is true",
		foreach = "foreach varname list body\nIterate over list elements",
		["return"] = "return ?-code code? ?-errorinfo info? ?value?\nReturn from procedure",
		expr = "expr arg ?arg ...?\nEvaluate mathematical expression",
		string = "string option arg ?arg ...?\nString manipulation commands",
		list = "list ?value value ...?\nCreate a list",
		lappend = "lappend varName ?value value ...?\nAppend elements to list",
		split = "split string ?splitChars?\nSplit string into list",
		join = "join list ?joinString?\nJoin list elements into string",
	}

	return tcl_docs[command]
end

-- Simple symbol resolution
function M.resolve_symbol(symbol_name, file_path, cursor_line, tclsh_cmd)
	print("DEBUG: Resolving symbol", symbol_name, "at line", cursor_line)

	local context = {
		namespace = "",
		proc = "",
	}

	local resolutions = {}

	if M.check_builtin_command(symbol_name, tclsh_cmd) then
		table.insert(resolutions, {
			type = "builtin_command",
			name = symbol_name,
			priority = 10,
		})
	end

	if symbol_name:match("::") then
		table.insert(resolutions, {
			type = "qualified_name",
			name = symbol_name,
			priority = 9,
		})
	else
		table.insert(resolutions, {
			type = "global",
			name = symbol_name,
			priority = 6,
		})
	end

	return {
		context = context,
		resolutions = resolutions,
	}
end

-- Helper function to check if file exists
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

-- Clear cache functions
function M.invalidate_cache(file_path)
	file_cache[file_path] = nil

	for key, _ in pairs(resolution_cache) do
		if key:match("^" .. vim.pesc(file_path) .. ":") then
			resolution_cache[key] = nil
		end
	end
end

function M.clear_all_caches()
	file_cache = {}
	resolution_cache = {}
end

-- Enhanced debug function
function M.debug_symbols(file_path, tclsh_cmd)
	print("DEBUG: Starting debug_symbols for:", file_path)
	print("DEBUG: Using tclsh command:", tclsh_cmd)

	-- Check if file exists and is readable
	if not utils.file_exists(file_path) then
		print("DEBUG: File does not exist:", file_path)
		return nil
	end

	-- Clear cache for this file to ensure fresh analysis
	M.invalidate_cache(file_path)
	print("DEBUG: Cache cleared for file")

	-- Get file info
	local file_size = vim.fn.getfsize(file_path)
	print("DEBUG: File size:", file_size, "bytes")

	-- Test tclsh command first
	local test_result, test_success = utils.execute_tcl_script('puts "TCL_TEST_OK"', tclsh_cmd)
	print("DEBUG: TCL test result:", test_result, "success:", test_success)

	if not (test_result and test_success and test_result:match("TCL_TEST_OK")) then
		print("DEBUG: TCL command failed basic test")
		return nil
	end

	-- Now analyze the file
	local symbols = M.analyze_tcl_file(file_path, tclsh_cmd)

	if not symbols then
		print("DEBUG: analyze_tcl_file returned nil")
		return nil
	end

	print("DEBUG: Final result: Found " .. #symbols .. " symbols")

	if #symbols == 0 then
		print("DEBUG: No symbols found. Possible issues:")
		print("  1. File might be empty or contain only comments")
		print("  2. File might have syntax errors preventing parsing")
		print("  3. File might not contain standard TCL constructs")
		print("  4. TCL script regex patterns might not match the code style")

		-- Try a simple content check
		local content_check = string.format(
			[[
set fp [open "%s" r]
set content [read $fp]
close $fp
set lines [split $content "\n"]
puts "CONTENT_LINES:[llength $lines]"
set non_empty 0
foreach line $lines {
    if {[string trim $line] ne "" && [string index [string trim $line] 0] ne "#"} {
        incr non_empty
    }
}
puts "NON_EMPTY_LINES:$non_empty"
if {$non_empty > 0} {
    set first_non_empty ""
    foreach line $lines {
        set trimmed [string trim $line]
        if {$trimmed ne "" && [string index $trimmed 0] ne "#"} {
            set first_non_empty $trimmed
            break
        }
    }
    puts "FIRST_NON_EMPTY:$first_non_empty"
}
]],
			file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
		)

		local content_result, content_success = utils.execute_tcl_script(content_check, tclsh_cmd)
		if content_result then
			print("DEBUG: Content analysis:")
			for line in content_result:gmatch("[^\n]+") do
				print("  " .. line)
			end
		end
	else
		-- Show detailed symbol information
		for i, symbol in ipairs(symbols) do
			print(string.format("  %d. %s '%s' at line %d", i, symbol.type, symbol.name, symbol.line))
		end
	end

	return symbols
end

-- Get cache statistics
function M.get_cache_stats()
	return {
		file_cache_entries = vim.tbl_count(file_cache),
		resolution_cache_entries = vim.tbl_count(resolution_cache),
		total_memory_usage = "~"
			.. math.floor((vim.tbl_count(file_cache) + vim.tbl_count(resolution_cache)) * 0.1)
			.. "KB",
	}
end

-- Initialize the TCL environment
function M.initialize_tcl_environment(tclsh_cmd)
	local init_script = [[
puts "TCL_INIT_START"

if {[catch {set test_var "hello"} err]} {
    puts "ERROR: Basic set command failed: $err"
    exit 1
}

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

	local result, success = utils.execute_tcl_script(init_script, tclsh_cmd)

	if result and success and result:match("TCL_INIT_SUCCESS") then
		return true, "TCL environment initialized successfully"
	else
		return false, result or "Failed to initialize TCL environment"
	end
end

return M
