local utils = require("tcl-lsp.utils")
local M = {}

-- Cache for file analysis results
local file_cache = {}
local resolution_cache = {}

-- Cache management functions (keep existing)
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

-- Enhanced TCL analysis script with better symbol detection
function M.analyze_tcl_file(file_path, tclsh_cmd)
	-- Check cache first
	local cached_symbols = get_cached_analysis(file_path)
	if cached_symbols then
		print("DEBUG: Using cached symbols for", file_path)
		return cached_symbols
	end

	print("DEBUG: Analyzing file", file_path, "with", tclsh_cmd)

	-- Enhanced analysis script with comprehensive symbol detection
	local analysis_script = string.format(
		[[
# Enhanced TCL Symbol Analysis Script with Debug Output
set file_path "%s"
puts "DEBUG: Starting analysis of $file_path"

# Track context during parsing
set current_namespace ""
set current_proc ""
set namespace_stack [list]
set brace_level 0

# Helper procedure to output symbols
proc emit_symbol {type name line {context ""} {scope "global"} {extra ""}} {
    # Clean up the name - remove leading/trailing whitespace and quotes
    set clean_name [string trim $name "\"'{}"]
    if {$clean_name eq ""} return
    
    puts "SYMBOL:$type:$clean_name:$line:$scope:$context:$extra"
    puts "DEBUG: Found $type '$clean_name' at line $line (scope: $scope, context: $context)"
}

# Read the file with better error handling
if {[catch {
    if {![file exists $file_path]} {
        puts "ERROR: File does not exist: $file_path"
        exit 1
    }
    
    if {![file readable $file_path]} {
        puts "ERROR: File is not readable: $file_path"
        exit 1
    }
    
    set fp [open $file_path r]
    set content [read $fp]
    close $fp
    puts "DEBUG: Successfully read [string length $content] characters"
} err]} {
    puts "ERROR: Cannot read file: $err"
    exit 1
}

# Split into lines for line number tracking
set lines [split $content "\n"]
set line_num 0
set total_lines [llength $lines]
puts "DEBUG: Processing $total_lines lines"

# Enhanced parsing with better context tracking
foreach line $lines {
    incr line_num
    set original_line $line
    set trimmed [string trim $line]
    
    # Skip comments and empty lines
    if {$trimmed eq "" || [string index $trimmed 0] eq "#"} {
        continue
    }
    
    # Track brace levels for better context awareness
    set open_braces [regexp -all {\{} $line]
    set close_braces [regexp -all {\}} $line]
    set brace_level [expr {$brace_level + $open_braces - $close_braces}]
    
    # Enhanced namespace handling with stack
    if {[regexp {^\s*namespace\s+eval\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match ns_name]} {
        # Push current namespace to stack
        if {$current_namespace ne ""} {
            lappend namespace_stack $current_namespace
        }
        set current_namespace $ns_name
        emit_symbol "namespace" $ns_name $line_num $current_namespace "namespace" ""
        puts "DEBUG: Entered namespace '$ns_name' at line $line_num"
    }
    
    # Enhanced procedure detection with argument parsing
    if {[regexp {^\s*proc\s+([a-zA-Z_][a-zA-Z0-9_:]*)\s*\{([^}]*)\}\s*\{} $line match proc_name proc_args]} {
        set scope "global"
        set context $current_namespace
        
        # Determine scope and create qualified name
        if {$current_namespace ne ""} {
            set scope "namespace"
            if {![string match "*::*" $proc_name]} {
                set qualified_name "$current_namespace\::$proc_name"
            } else {
                set qualified_name $proc_name
            }
        } else {
            set qualified_name $proc_name
        }
        
        if {$current_proc ne ""} {
            set scope "local"
        }
        
        # Clean up arguments
        set clean_args [string trim $proc_args]
        emit_symbol "procedure" $qualified_name $line_num $context $scope $clean_args
        
        # Also emit the local name if different
        if {$qualified_name ne $proc_name} {
            emit_symbol "procedure_local" $proc_name $line_num $context "local" $clean_args
        }
        
        set current_proc $proc_name
        puts "DEBUG: Entered procedure '$proc_name' (qualified: $qualified_name) at line $line_num"
    }
    
    # Enhanced variable detection with type inference
    if {[regexp {^\s*set\s+([a-zA-Z_][a-zA-Z0-9_:]*)\s+(.*)$} $line match var_name var_value]} {
        set scope "global"
        set context $current_namespace
        
        # Determine scope
        if {$current_proc ne ""} {
            set scope "local"
        } elseif {$current_namespace ne ""} {
            set scope "namespace"
        }
        
        # Create qualified name for namespace variables
        if {$current_namespace ne "" && $scope eq "namespace" && ![string match "*::*" $var_name]} {
            set qualified_name "$current_namespace\::$var_name"
        } else {
            set qualified_name $var_name
        }
        
        # Clean up value and detect type
        set clean_value [string trim $var_value]
        set var_type "variable"
        
        # Type detection based on value
        if {[regexp {^\[.*\]$} $clean_value]} {
            set var_type "command_result"
        } elseif {[regexp {^\{.*\}$} $clean_value]} {
            set var_type "list_or_dict"
        } elseif {[regexp {^".*"$} $clean_value]} {
            set var_type "string"
        } elseif {[regexp {^[0-9]+(\.[0-9]+)?$} $clean_value]} {
            set var_type "number"
        }
        
        emit_symbol $var_type $qualified_name $line_num $context $scope $clean_value
        
        # Also emit local name if different
        if {$qualified_name ne $var_name} {
            emit_symbol "${var_type}_local" $var_name $line_num $context "local" $clean_value
        }
    }
    
    # Global variable declarations
    if {[regexp {^\s*global\s+(.+)$} $line match globals]} {
        foreach global_var [split $globals] {
            set clean_var [string trim $global_var]
            if {$clean_var ne ""} {
                emit_symbol "global" $clean_var $line_num $current_namespace "global" ""
            }
        }
    }
    
    # Variable command (namespace variables)
    if {[regexp {^\s*variable\s+([a-zA-Z_][a-zA-Z0-9_:]*)\s*(.*)$} $line match var_name var_value]} {
        set scope "namespace"
        set context $current_namespace
        
        if {$current_namespace ne "" && ![string match "*::*" $var_name]} {
            set qualified_name "$current_namespace\::$var_name"
        } else {
            set qualified_name $var_name
        }
        
        set clean_value [string trim $var_value]
        emit_symbol "namespace_variable" $qualified_name $line_num $context $scope $clean_value
    }
    
    # Array declarations
    if {[regexp {^\s*array\s+set\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match array_name]} {
        set scope "global"
        set context $current_namespace
        
        if {$current_proc ne ""} {
            set scope "local"
        } elseif {$current_namespace ne ""} {
            set scope "namespace"
        }
        
        if {$current_namespace ne "" && $scope eq "namespace" && ![string match "*::*" $array_name]} {
            set qualified_name "$current_namespace\::$array_name"
        } else {
            set qualified_name $array_name
        }
        
        emit_symbol "array" $qualified_name $line_num $context $scope ""
    }
    
    # Package operations
    if {[regexp {^\s*package\s+(require|provide)\s+([a-zA-Z_][a-zA-Z0-9_:]*)\s*(.*)$} $line match cmd pkg_name version]} {
        set clean_version [string trim $version]
        emit_symbol "package_$cmd" $pkg_name $line_num "" "package" $clean_version
    }
    
    # Source commands
    if {[regexp {^\s*source\s+(.+)$} $line match source_file]} {
        set clean_file [string trim $source_file "\"'{}"]
        emit_symbol "source" $clean_file $line_num $current_namespace "source" ""
    }
    
    # Class definitions (for Tcl object systems)
    if {[regexp {^\s*(class|oo::class)\s+create\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match oo_type class_name]} {
        emit_symbol "class" $class_name $line_num $current_namespace "class" $oo_type
    }
    
    # Method definitions
    if {[regexp {^\s*method\s+([a-zA-Z_][a-zA-Z0-9_:]*)\s*\{([^}]*)\}} $line match method_name method_args]} {
        set clean_args [string trim $method_args]
        emit_symbol "method" $method_name $line_num $current_namespace "method" $clean_args
    }
    
    # Reset contexts when exiting scopes (improved brace tracking)
    if {$close_braces > 0 && $brace_level <= 0} {
        if {$current_proc ne ""} {
            puts "DEBUG: Exiting procedure '$current_proc' at line $line_num"
            set current_proc ""
        }
        
        if {$current_namespace ne "" && [llength $namespace_stack] > 0} {
            puts "DEBUG: Exiting namespace '$current_namespace' at line $line_num"
            set current_namespace [lindex $namespace_stack end]
            set namespace_stack [lrange $namespace_stack 0 end-1]
            puts "DEBUG: Returned to namespace '$current_namespace'"
        } elseif {$current_namespace ne "" && $brace_level < 0} {
            puts "DEBUG: Exiting namespace '$current_namespace' (root level) at line $line_num"
            set current_namespace ""
        }
    }
}

puts "DEBUG: Completed analysis of $total_lines lines"
puts "ANALYSIS_COMPLETE"
]],
		file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
	)

	local result, success = utils.execute_tcl_script(analysis_script, tclsh_cmd)

	if not (result and success) then
		print("DEBUG: TCL script execution failed")
		print("DEBUG: Command:", tclsh_cmd)
		print("DEBUG: Result:", result or "nil")
		print("DEBUG: Success:", success)

		-- Try a simpler fallback analysis
		print("DEBUG: Attempting fallback analysis")
		return M.fallback_analysis(file_path)
	end

	print("DEBUG: TCL script executed successfully")
	print("DEBUG: Output length:", string.len(result))

	local symbols = {}
	local debug_lines = {}

	for line in result:gmatch("[^\n]+") do
		if line:match("^DEBUG:") then
			table.insert(debug_lines, line)
		elseif line:match("^SYMBOL:") then
			-- Enhanced parsing: SYMBOL:type:name:line:scope:context:extra
			local parts = {}
			for part in line:gmatch("([^:]+)") do
				table.insert(parts, part)
			end

			if #parts >= 4 then
				local symbol = {
					type = parts[2] or "unknown",
					name = parts[3] or "unknown",
					line = tonumber(parts[4]) or 1,
					scope = parts[5] or "",
					context = parts[6] or "",
					extra = parts[7] or "",
					text = "", -- Will be filled if needed
					qualified_name = parts[3] or "unknown",
					method = "enhanced",
				}

				-- Set qualified name properly
				if symbol.context ~= "" and not symbol.name:match("::") then
					symbol.qualified_name = symbol.context .. "::" .. symbol.name
				end

				table.insert(symbols, symbol)
			end
		end
	end

	-- Print debug information
	print("DEBUG: Found", #symbols, "symbols")
	for _, debug_line in ipairs(debug_lines) do
		print(debug_line)
	end

	for i, symbol in ipairs(symbols) do
		print(
			string.format(
				"DEBUG: Symbol %d: %s '%s' at line %d (scope: %s, context: %s)",
				i,
				symbol.type,
				symbol.name,
				symbol.line,
				symbol.scope,
				symbol.context
			)
		)
	end

	-- Cache the results
	cache_file_analysis(file_path, symbols)

	return symbols
end

-- Fallback analysis for when the enhanced script fails
function M.fallback_analysis(file_path)
	print("DEBUG: Running fallback analysis")

	local file = io.open(file_path, "r")
	if not file then
		print("DEBUG: Cannot open file for fallback analysis")
		return {}
	end

	local symbols = {}
	local line_num = 0

	for line in file:lines() do
		line_num = line_num + 1
		local trimmed = line:match("^%s*(.-)%s*$")

		-- Skip empty lines and comments
		if trimmed == "" or trimmed:match("^#") then
			goto continue
		end

		-- Simple procedure detection
		local proc_name = trimmed:match("^proc%s+([%w_:]+)")
		if proc_name then
			table.insert(symbols, {
				type = "procedure",
				name = proc_name,
				line = line_num,
				scope = "global",
				context = "",
				text = trimmed,
				qualified_name = proc_name,
				method = "fallback",
			})
		end

		-- Simple variable detection
		local var_name = trimmed:match("^set%s+([%w_:]+)")
		if var_name then
			table.insert(symbols, {
				type = "variable",
				name = var_name,
				line = line_num,
				scope = "global",
				context = "",
				text = trimmed,
				qualified_name = var_name,
				method = "fallback",
			})
		end

		-- Simple namespace detection
		local ns_name = trimmed:match("^namespace%s+eval%s+([%w_:]+)")
		if ns_name then
			table.insert(symbols, {
				type = "namespace",
				name = ns_name,
				line = line_num,
				scope = "namespace",
				context = "",
				text = trimmed,
				qualified_name = ns_name,
				method = "fallback",
			})
		end

		::continue::
	end

	file:close()

	print("DEBUG: Fallback analysis found", #symbols, "symbols")
	return symbols
end

-- Keep all existing functions but enhance the main analysis
-- [Include all your existing functions: get_tcl_info, test_json_functionality,
--  find_symbol_references, check_builtin_command, get_command_documentation,
--  resolve_symbol, etc.]

-- Get Tcl system information (keep existing)
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

-- Test JSON functionality (keep existing)
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

-- Enhanced find symbol references with better detection
function M.find_symbol_references(file_path, symbol_name, tclsh_cmd)
	local reference_script = string.format(
		[[
# Enhanced reference finding
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

# Check if target_word contains namespace qualifier
set is_qualified [string match "*::*" $target_word]
if {$is_qualified} {
    set parts [split $target_word "::"]
    set unqualified [lindex $parts end]
} else {
    set unqualified $target_word
}

foreach line $lines {
    incr line_num
    
    # Check for exact matches with word boundaries
    if {[regexp "\\y$target_word\\y" $line]} {
        set context "usage"
        if {[regexp "^\\s*proc\\s+$target_word\\s" $line]} {
            set context "definition:procedure"
        } elseif {[regexp "^\\s*set\\s+$target_word\\s" $line]} {
            set context "definition:variable"
        } elseif {[regexp "^\\s*namespace\\s+eval\\s+$target_word\\s" $line]} {
            set context "definition:namespace"
        } elseif {[regexp "\\$target_word\\y" $line]} {
            set context "variable_usage"
        } elseif {[regexp "$target_word\\s*\\(" $line] || [regexp "\\s$target_word\\s" $line]} {
            set context "procedure_call"
        }
        
        puts "REFERENCE:$context:$line_num:$line"
    } elseif {$is_qualified && [regexp "\\y$unqualified\\y" $line]} {
        # Unqualified matches for qualified symbols
        set context "usage_unqualified"
        if {[regexp "^\\s*proc\\s+$unqualified\\s" $line]} {
            set context "definition:procedure_local"
        } elseif {[regexp "^\\s*set\\s+$unqualified\\s" $line]} {
            set context "definition:variable_local"
        } elseif {[regexp "\\$unqualified\\y" $line]} {
            set context "variable_usage_local"
        } elseif {[regexp "$unqualified\\s*\\(" $line]} {
            set context "procedure_call_local"
        }
        
        puts "REFERENCE:$context:$line_num:$line"
    }
}

puts "REFERENCES_COMPLETE"
]],
		symbol_name:gsub("\\", "\\\\"):gsub('"', '\\"'),
		file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
	)

	local result, success = utils.execute_tcl_script(reference_script, tclsh_cmd)

	if not (result and success) then
		return nil
	end

	local references = {}
	for line in result:gmatch("[^\n]+") do
		local context, line_num, text = line:match("REFERENCE:([^:]+):([^:]+):(.+)")
		if context and line_num and text then
			table.insert(references, {
				context = context,
				line = tonumber(line_num),
				text = utils.trim(text),
				method = "enhanced",
			})
		end
	end

	return references
end

-- Keep all other existing functions...
-- [Include check_builtin_command, get_command_documentation, resolve_symbol, etc.]

-- Check if a symbol is a built-in TCL command using introspection
function M.check_builtin_command(symbol_name, tclsh_cmd)
	local builtin_check_script = string.format(
		[[
set word "%s"

if {[catch {info args $word} args_result]} {
    if {[catch {info commands $word} cmd_result]} {
        puts "NOT_BUILTIN"
    } else {
        if {$cmd_result eq ""} {
            puts "NOT_BUILTIN" 
        } else {
            puts "BUILTIN_COMMAND:$word"
        }
    }
} else {
    puts "BUILTIN_PROC:$word:$args_result"
}

if {[catch {info vars $word} var_result]} {
    if {[catch {info globals $word} global_result]} {
        puts "NOT_BUILTIN_VAR"
    } else {
        if {$global_result ne ""} {
            puts "BUILTIN_VAR:$word"
        }
    }
} else {
    if {$var_result ne ""} {
        puts "BUILTIN_VAR:$word"
    }
}
]],
		symbol_name:gsub("\\", "\\\\"):gsub('"', '\\"')
	)

	local result, success = utils.execute_tcl_script(builtin_check_script, tclsh_cmd)

	if not (result and success) then
		return nil
	end

	if result:match("BUILTIN_PROC:([^:]+):(.+)") then
		local cmd, args = result:match("BUILTIN_PROC:([^:]+):(.+)")
		return {
			type = "builtin_proc",
			name = cmd,
			args = args,
			description = string.format("%s %s\nBuilt-in TCL procedure", cmd, args),
		}
	elseif result:match("BUILTIN_COMMAND:(.+)") then
		local cmd = result:match("BUILTIN_COMMAND:(.+)")
		return {
			type = "builtin_command",
			name = cmd,
			description = cmd .. "\nBuilt-in TCL command",
		}
	elseif result:match("BUILTIN_VAR:(.+)") then
		local var = result:match("BUILTIN_VAR:(.+)")
		return {
			type = "builtin_var",
			name = var,
			description = var .. "\nBuilt-in TCL variable",
		}
	end

	return nil
end

-- Get TCL command documentation (keep existing large documentation table)
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
		dict = "dict option arg ?arg ...?\nDictionary manipulation commands",
		array = "array option arrayName ?arg ...?\nArray manipulation commands",
		catch = "catch script ?resultVarName? ?optionsVarName?\nCatch script errors",
		error = "error message ?info? ?code?\nGenerate an error",
		source = "source fileName\nEvaluate script from file",
		package = "package option ?arg arg ...?\nPackage management commands",
		namespace = "namespace option ?arg ...?\nNamespace management",
		file = "file option name ?arg ...?\nFile system operations",
		glob = "glob ?switches? pattern ?pattern ...?\nReturn files matching patterns",
		regexp = "regexp ?switches? exp string ?matchVar? ?subMatchVar ...?\nMatch regular expression",
		regsub = "regsub ?switches? exp string subSpec ?varName?\nReplace using regular expression",
		switch = "switch ?options? string pattern body ?pattern body ...?\nMultiple conditional execution",
		eval = "eval arg ?arg ...?\nEvaluate arguments as script",
		uplevel = "uplevel ?level? arg ?arg ...?\nExecute script in different stack level",
		upvar = "upvar ?level? otherVar myVar ?otherVar myVar ...?\nLink to variable in different scope",
		global = "global varname ?varname ...?\nAccess global variables",
		variable = "variable ?name value ...? name ?value?\nDeclare namespace variables",
		info = "info option ?arg arg ...?\nIntrospection commands",
		clock = "clock option ?arg ...?\nDate and time functions",
		-- Add more as needed...
	}

	return tcl_docs[command]
end

-- Enhanced symbol resolution
function M.resolve_symbol(symbol_name, file_path, cursor_line, tclsh_cmd)
	-- Check cache first
	local cache_key = file_path .. ":" .. symbol_name .. ":" .. cursor_line
	local cached_resolution = resolution_cache[cache_key]
	if cached_resolution and is_cache_valid(file_path, cached_resolution) then
		return cached_resolution.resolution
	end

	print("DEBUG: Resolving symbol", symbol_name, "at line", cursor_line)

	local resolution_script = string.format(
		[[
set symbol_name "%s"
set file_path "%s" 
set cursor_line %d

if {[catch {
    set fp [open $file_path r]
    set content [read $fp]
    close $fp
} err]} {
    puts "ERROR: Cannot read file: $err"
    exit 1
}

set lines [split $content "\n"]
set current_namespace ""
set current_proc ""
set line_num 0

# Scan to cursor position to determine context
foreach line $lines {
    incr line_num
    if {$line_num > $cursor_line} break
    
    # Track namespace context
    if {[regexp {^\s*namespace\s+eval\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match ns_name]} {
        set current_namespace $ns_name
    }
    
    # Track procedure context
    if {[regexp {^\s*proc\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match proc_name]} {
        set current_proc $proc_name
    }
}

puts "CURSOR_CONTEXT:namespace:$current_namespace:proc:$current_proc"

# Generate resolution candidates with priorities
set candidates [list]

# 1. Built-in command check
if {[info commands $symbol_name] ne ""} {
    puts "RESOLUTION:builtin_command:$symbol_name:priority:10"
}

# 2. Qualified name as-is
if {[string match "*::*" $symbol_name]} {
    puts "RESOLUTION:qualified_name:$symbol_name:priority:9"
} else {
    # 3. Namespace qualified
    if {$current_namespace ne ""} {
        set ns_qualified "$current_namespace\::$symbol_name"
        puts "RESOLUTION:namespace_qualified:$ns_qualified:priority:8:context:$current_namespace"
    }
    
    # 4. Procedure local
    if {$current_proc ne ""} {
        puts "RESOLUTION:proc_local:$symbol_name:priority:7:context:$current_proc"
    }
    
    # 5. Global
    puts "RESOLUTION:global:$symbol_name:priority:6"
}

puts "RESOLUTION_COMPLETE"
]],
		symbol_name:gsub("\\", "\\\\"):gsub('"', '\\"'),
		file_path:gsub("\\", "\\\\"):gsub('"', '\\"'),
		cursor_line
	)

	local result, success = utils.execute_tcl_script(resolution_script, tclsh_cmd)

	if not (result and success) then
		return nil
	end

	local resolutions = {}
	local context = {}

	for line in result:gmatch("[^\n]+") do
		if line:match("CURSOR_CONTEXT:") then
			local ns, proc = line:match("CURSOR_CONTEXT:namespace:([^:]*):proc:([^:]*)")
			context.namespace = (ns ~= "") and ns or nil
			context.proc = (proc ~= "") and proc or nil
		elseif line:match("RESOLUTION:") then
			local parts = {}
			for part in line:gmatch("([^:]+)") do
				table.insert(parts, part)
			end

			if #parts >= 4 then
				local resolution = {
					type = parts[2],
					name = parts[3],
					priority = tonumber(parts[4]) or 0,
					context = "",
				}

				-- Parse additional metadata
				local i = 5
				while i <= #parts do
					if parts[i] == "priority" and i < #parts then
						resolution.priority = tonumber(parts[i + 1]) or 0
						i = i + 2
					elseif parts[i] == "context" and i < #parts then
						resolution.context = parts[i + 1]
						i = i + 2
					else
						i = i + 1
					end
				end

				table.insert(resolutions, resolution)
			end
		end
	end

	-- Sort by priority
	table.sort(resolutions, function(a, b)
		return a.priority > b.priority
	end)

	local final_resolution = {
		context = context,
		resolutions = resolutions,
	}

	-- Cache the result
	resolution_cache[cache_key] = {
		resolution = final_resolution,
		mtime = get_file_mtime(file_path),
		timestamp = os.time(),
	}

	return final_resolution
end

-- Clear cache for a specific file
function M.invalidate_cache(file_path)
	file_cache[file_path] = nil

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
end

-- Enhanced debug function
function M.debug_symbols(file_path, tclsh_cmd)
	print("DEBUG: Starting debug analysis of", file_path)

	-- Clear cache to force fresh analysis
	M.invalidate_cache(file_path)

	local symbols = M.analyze_tcl_file(file_path, tclsh_cmd)

	if not symbols then
		print("DEBUG: No symbols found - analysis failed")
		print("DEBUG: Checking if file exists:", M.file_exists(file_path))
		print("DEBUG: Checking tclsh command:", tclsh_cmd)

		-- Test basic TCL execution
		local test_result, test_success = utils.execute_tcl_script('puts "TCL_TEST_OK"', tclsh_cmd)
		print("DEBUG: Basic TCL test result:", test_result, test_success)

		return {}
	end

	print("DEBUG: Found " .. #symbols .. " symbols:")
	for i, symbol in ipairs(symbols) do
		print(
			string.format(
				"  %d. %s '%s' at line %d (scope: %s, context: %s, method: %s)",
				i,
				symbol.type,
				symbol.name,
				symbol.line,
				symbol.scope or "none",
				symbol.context or "none",
				symbol.method or "unknown"
			)
		)
	end

	return symbols
end

-- Helper function to check if file exists
function M.file_exists(file_path)
	local file = io.open(file_path, "r")
	if file then
		file:close()
		return true
	end
	return false
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

-- Execute TCL command directly
function M.execute_tcl_command(command, tclsh_cmd)
	local script = string.format(
		[[
if {[catch {%s} result]} {
    puts "ERROR:$result"
    exit 1
} else {
    puts "SUCCESS:$result"
}
]],
		command
	)

	local result, success = utils.execute_tcl_script(script, tclsh_cmd)

	if not (result and success) then
		return false, "Failed to execute command"
	end

	if result:match("SUCCESS:(.*)") then
		return true, result:match("SUCCESS:(.*)")
	elseif result:match("ERROR:(.*)") then
		return false, result:match("ERROR:(.*)")
	end

	return false, "Unknown result format"
end

-- Initialize the TCL environment and verify it's working
function M.initialize_tcl_environment(tclsh_cmd)
	local init_script = [[
# Test basic TCL functionality
puts "TCL_INIT_START"

# Check basic commands
if {[catch {set test_var "hello"} err]} {
    puts "ERROR: Basic set command failed: $err"
    exit 1
}

if {[catch {puts -nonewline ""} err]} {
    puts "ERROR: puts command failed: $err"
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

	local result, success = utils.execute_tcl_script(init_script, tclsh_cmd)

	if result and success and result:match("TCL_INIT_SUCCESS") then
		return true, "TCL environment initialized successfully"
	else
		return false, result or "Failed to initialize TCL environment"
	end
end

return M
