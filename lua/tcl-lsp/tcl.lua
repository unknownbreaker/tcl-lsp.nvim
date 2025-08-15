local semantic = require("tcl-lsp.semantic")
local utils = require("tcl-lsp.utils")
local M = {}

-- Cache for file analysis results
local file_cache = {}
local resolution_cache = {}

-- Cache management functions - DECLARE ALL LOCAL FUNCTIONS FIRST
local get_file_mtime
local is_cache_valid
local cache_file_analysis
local get_cached_analysis
local cache_resolution
local get_cached_resolution
local cleanup_cache

-- Now DEFINE the functions
get_file_mtime = function(file_path)
	return vim.fn.getftime(file_path)
end

is_cache_valid = function(file_path, cache_entry)
	if not cache_entry then
		return false
	end

	local current_mtime = get_file_mtime(file_path)
	return cache_entry.mtime == current_mtime
end

cache_file_analysis = function(file_path, symbols)
	file_cache[file_path] = {
		symbols = symbols,
		mtime = get_file_mtime(file_path),
		timestamp = os.time(),
	}
end

get_cached_analysis = function(file_path)
	local cache_entry = file_cache[file_path]
	if is_cache_valid(file_path, cache_entry) then
		return cache_entry.symbols
	end
	return nil
end

cache_resolution = function(file_path, symbol_name, cursor_line, resolution)
	local cache_key = file_path .. ":" .. symbol_name .. ":" .. cursor_line
	resolution_cache[cache_key] = {
		resolution = resolution,
		mtime = get_file_mtime(file_path),
		timestamp = os.time(),
	}
end

get_cached_resolution = function(file_path, symbol_name, cursor_line)
	local cache_key = file_path .. ":" .. symbol_name .. ":" .. cursor_line
	local cache_entry = resolution_cache[cache_key]
	if is_cache_valid(file_path, cache_entry) then
		return cache_entry.resolution
	end
	return nil
end

-- Clean old cache entries (call periodically)
cleanup_cache = function()
	local current_time = os.time()
	local max_age = 300 -- 5 minutes

	for key, entry in pairs(file_cache) do
		if current_time - entry.timestamp > max_age then
			file_cache[key] = nil
		end
	end

	for key, entry in pairs(resolution_cache) do
		if current_time - entry.timestamp > max_age then
			resolution_cache[key] = nil
		end
	end
end

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

-- Use TCL to analyze a file and extract symbols with their locations (cached)
function M.analyze_tcl_file(file_path, tclsh_cmd)
	-- Check cache first
	local cached_symbols = get_cached_analysis(file_path)
	if cached_symbols then
		return cached_symbols
	end

	-- Periodically clean up old cache entries
	if math.random(1, 20) == 1 then -- 5% chance
		cleanup_cache()
	end

	-- More robust analysis that works with real TCL files
	local escaped_path = file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
	local working_analysis_script = string.format(
		[[
# Robust TCL Analysis that actually works
set file_path "%s"

# Read the file
if {[catch {
    set fp [open $file_path r]
    set content [read $fp]
    close $fp
} err]} {
    puts "ERROR: Cannot read file: $err"
    exit 1
}

puts "DEBUG: File read successfully, length: [string length $content]"

# Split into lines and track context
set lines [split $content "\n"]
set line_num 0
set current_namespace ""
set current_proc ""
set namespace_stack [list]
set brace_level 0
set in_string 0

puts "DEBUG: Processing [llength $lines] lines"

# Function to output symbol information
proc emit_symbol {type name qualified_name line scope context extra} {
    puts "SYMBOL:$type:$name:$qualified_name:$line:$scope:$context:$extra"
}

# Parse each line more carefully
foreach line $lines {
    incr line_num
    set original_line $line
    set trimmed [string trim $line]
    
    # Skip empty lines and comments
    if {$trimmed eq "" || [string match "#*" $trimmed]} {
        continue
    }
    
    puts "DEBUG: Line $line_num: $trimmed"
    
    # Track brace levels more carefully
    set line_open_braces 0
    set line_close_braces 0
    set in_quotes 0
    
    # Count braces while respecting quotes
    for {set i 0} {$i < [string length $line]} {incr i} {
        set char [string index $line $i]
        if {$char eq "\""} {
            set in_quotes [expr {!$in_quotes}]
        } elseif {!$in_quotes} {
            if {$char eq "\{"} {
                incr line_open_braces
            } elseif {$char eq "\}"} {
                incr line_close_braces
            }
        }
    }
    
    set brace_level [expr {$brace_level + $line_open_braces - $line_close_braces}]
    puts "DEBUG: Brace level now: $brace_level"
    
    # Find package commands (more flexible pattern)
    if {[regexp {^\s*package\s+(require|provide)\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $trimmed match cmd pkg_name]} {
        puts "DEBUG: Found package: $cmd $pkg_name"
        emit_symbol "package" $pkg_name $pkg_name $line_num "package" "" "$cmd"
    }
    
    # Find namespace eval commands (handle various forms)
    if {[regexp {^\s*namespace\s+eval\s+([a-zA-Z_:][a-zA-Z0-9_:]*)} $trimmed match ns_name]} {
        puts "DEBUG: Found namespace: $ns_name"
        
        # Clean up namespace name
        set clean_ns [string trim $ns_name "{}\""]
        
        # Track namespace stack
        lappend namespace_stack $current_namespace
        set current_namespace $clean_ns
        
        emit_symbol "namespace" $clean_ns $clean_ns $line_num "namespace" "" ""
    }
    
    # Find procedure definitions (more robust)
    if {[regexp {^\s*proc\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $trimmed match proc_name]} {
        puts "DEBUG: Found proc: $proc_name"
        
        set qualified_name $proc_name
        
        # Create qualified name if in namespace
        if {$current_namespace ne "" && ![string match "*::*" $proc_name]} {
            set qualified_name "$current_namespace\::$proc_name"
        }
        
        # Try to extract arguments (simple approach)
        set proc_args ""
        if {[regexp {^\s*proc\s+[a-zA-Z_][a-zA-Z0-9_:]*\s*\{([^}]*)\}} $trimmed match args_part]} {
            set proc_args [string trim $args_part]
        }
        
        emit_symbol "procedure" $proc_name $qualified_name $line_num "procedure" $current_namespace $proc_args
        
        set current_proc $proc_name
        
        # Parse parameters if we found them
        if {$proc_args ne ""} {
            # Simple parameter parsing
            set param_list [split $proc_args]
            foreach param_item $param_list {
                set param_item [string trim $param_item]
                if {$param_item ne ""} {
                    # Handle simple parameters and defaults
                    if {[string match "*\{*\}*" $param_item]} {
                        # Parameter with default: {name default}
                        if {[regexp {\{([a-zA-Z_][a-zA-Z0-9_]*)} $param_item match param_name]} {
                            emit_symbol "parameter" $param_name "$current_proc\::$param_name" $line_num "parameter" $current_proc ""
                        }
                    } elseif {[regexp {^[a-zA-Z_][a-zA-Z0-9_]*$} $param_item]} {
                        # Simple parameter
                        emit_symbol "parameter" $param_item "$current_proc\::$param_item" $line_num "parameter" $current_proc ""
                    }
                }
            }
        }
    }
    
    # Find variable assignments
    if {[regexp {^\s*set\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $trimmed match var_name]} {
        puts "DEBUG: Found variable: $var_name"
        
        set qualified_name $var_name
        set scope "global"
        
        if {$current_proc ne ""} {
            set scope "local"
            set qualified_name "$current_proc\::$var_name"
        } elseif {$current_namespace ne "" && ![string match "*::*" $var_name]} {
            set scope "namespace"
            set qualified_name "$current_namespace\::$var_name"
        }
        
        emit_symbol "variable" $var_name $qualified_name $line_num $scope $current_proc ""
    }
    
    # Find global declarations
    if {[regexp {^\s*global\s+(.+)$} $trimmed match globals]} {
        puts "DEBUG: Found global: $globals"
        foreach global_var [split $globals] {
            set clean_var [string trim $global_var]
            if {$clean_var ne "" && [regexp {^[a-zA-Z_][a-zA-Z0-9_:]*$} $clean_var]} {
                emit_symbol "global" $clean_var $clean_var $line_num "global" $current_proc ""
            }
        }
    }
    
    # Find array operations
    if {[regexp {^\s*array\s+set\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $trimmed match array_name]} {
        puts "DEBUG: Found array: $array_name"
        
        set qualified_name $array_name
        set scope "global"
        
        if {$current_proc ne ""} {
            set scope "local"
            set qualified_name "$current_proc\::$array_name"
        } elseif {$current_namespace ne "" && ![string match "*::*" $array_name]} {
            set scope "namespace"
            set qualified_name "$current_namespace\::$array_name"
        }
        
        emit_symbol "array" $array_name $qualified_name $line_num $scope $current_proc ""
    }
    
    # Find source commands
    if {[regexp {^\s*source\s+(.+)$} $trimmed match source_file]} {
        puts "DEBUG: Found source: $source_file"
        set clean_file [string trim $source_file "\"'\{\}"]
        emit_symbol "source" $clean_file $clean_file $line_num "source" "" ""
    }
    
    # Handle scope exits when braces close
    if {$line_close_braces > 0} {
        puts "DEBUG: Closing braces, checking scope exits"
        
        # If we closed back to level 0 or below, exit current procedure
        if {$brace_level <= 0 && $current_proc ne ""} {
            puts "DEBUG: Exiting procedure: $current_proc"
            set current_proc ""
        }
        
        # If we have unmatched closes and we're in a namespace, exit it
        if {$brace_level <= 0 && [llength $namespace_stack] > 0} {
            puts "DEBUG: Exiting namespace: $current_namespace"
            set current_namespace [lindex $namespace_stack end]
            set namespace_stack [lrange $namespace_stack 0 end-1]
        }
    }
}

puts "ANALYSIS_COMPLETE"
puts "DEBUG: Analysis finished"
]],
		escaped_path
	)

	local result, success = utils.execute_tcl_script(working_analysis_script, tclsh_cmd)

	if not (result and success) then
		print("DEBUG: Robust analysis failed")
		print("DEBUG: Result:", result or "nil")
		print("DEBUG: Success:", success)
		return nil
	end

	print("DEBUG: Robust analysis output:")
	print(result)

	local symbols = {}
	for line in result:gmatch("[^\n]+") do
		if line:match("^SYMBOL:") then
			print("DEBUG: Processing symbol line:", line)

			-- Parse: SYMBOL:type:name:qualified_name:line:scope:context:extra
			local symbol_type, name, qualified_name, line_num, scope, context, extra =
				line:match("SYMBOL:([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]*):([^:]*)")

			if symbol_type and name and line_num then
				local symbol = {
					type = symbol_type,
					name = name,
					qualified_name = qualified_name ~= name and qualified_name or nil,
					line = tonumber(line_num),
					text = line, -- Could be improved by getting actual line text
					scope = scope or "global",
					context = context ~= "" and context or nil,
					proc_context = (symbol_type == "parameter" and context ~= "") and context or nil,
					args = extra ~= "" and extra or nil,
					method = "robust_working",
				}

				print(
					"DEBUG: Found robust symbol:",
					symbol.type,
					symbol.name,
					"at line",
					symbol.line,
					"scope:",
					symbol.scope,
					"qualified:",
					symbol.qualified_name or "none"
				)
				table.insert(symbols, symbol)
			else
				print("DEBUG: Failed to parse symbol line:", line)
			end
		end
	end

	print("DEBUG: Total robust symbols found:", #symbols)

	-- Cache the results
	cache_file_analysis(file_path, symbols)

	return symbols
end

-- Find references to a symbol using TCL analysis
function M.find_symbol_references(file_path, symbol_name, tclsh_cmd)
	local reference_script = string.format(
		[[
# Find references to a symbol
set target_word "%s"
set file_path "%s"

# Read the file
if {[catch {
    set fp [open $file_path r]
    set content [read $fp]
    close $fp
} err]} {
    puts "ERROR: Cannot read file: $err"
    exit 1
}

# Split into lines
set lines [split $content "\n"]
set line_num 0

# Check if target_word contains namespace qualifier
set is_qualified [string match "*::*" $target_word]
if {$is_qualified} {
    # Extract the unqualified part for additional matching
    set parts [split $target_word "::"]
    set unqualified [lindex $parts end]
} else {
    set unqualified $target_word
}

foreach line $lines {
    incr line_num
    
    # Check if line contains the target word (exact match)
    if {[regexp "\\y$target_word\\y" $line]} {
        # Determine the context/type of reference
        set context "usage"
        if {[regexp "^\\s*proc\\s+$target_word\\s" $line]} {
            set context "definition:procedure"
        } elseif {[regexp "^\\s*set\\s+$target_word\\s" $line]} {
            set context "definition:variable"
        } elseif {[regexp "^\\s*namespace\\s+eval\\s+$target_word\\s" $line]} {
            set context "definition:namespace"
        } elseif {[regexp "\\$target_word\\y" $line]} {
            set context "variable_usage"
        } elseif {[regexp "$target_word\\s*\\(" $line]} {
            set context "procedure_call"
        }
        
        puts "REFERENCE:$context:$line_num:$line"
    } elseif {$is_qualified && [regexp "\\y$unqualified\\y" $line]} {
        # If searching for qualified name, also look for unqualified references
        # But mark them as potential matches
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
		symbol_name,
		file_path
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
			})
		end
	end

	return references
end

-- Check if a symbol is a built-in TCL command using introspection
function M.check_builtin_command(symbol_name, tclsh_cmd)
	local builtin_check_script = string.format(
		[[
# Check if word is a built-in command
set word "%s"

# Try to get command info
if {[catch {info args $word} args_result]} {
    # Not a known command with args, check if it exists as a command
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
    # It's a command with arguments
    puts "BUILTIN_PROC:$word:$args_result"
}

# Also check if it's a built-in variable or namespace
if {[catch {info vars $word} var_result]} {
    # Check global vars
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
		symbol_name
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
		format = "format formatString ?arg arg ...?\nFormat string like sprintf",
		scan = "scan string format ?varName varName ...?\nParse string according to format",
		open = "open fileName ?access? ?permissions?\nOpen file for reading/writing",
		close = "close channelId\nClose open channel",
		read = "read ?-nonewline? channelId ?numChars?\nRead from channel",
		gets = "gets channelId ?varName?\nRead line from channel",
		seek = "seek channelId offset ?origin?\nSeek to position in channel",
		tell = "tell channelId\nGet current position in channel",
		eof = "eof channelId\nTest for end of file",
		flush = "flush ?channelId?\nFlush output to channel",
		fconfigure = "fconfigure channelId ?optionName? ?value? ?optionName value ...?\nConfigure channel options",
		-- JSON commands (from tcllib)
		json = "json subcommand ?arg ...?\nJSON parsing and generation",
		["json::json2dict"] = "json::json2dict jsonText\nConvert JSON string to Tcl dict",
		["json::dict2json"] = "json::dict2json dict\nConvert Tcl dict to JSON string",
		-- Control flow
		["break"] = "break\nExit from loop prematurely",
		continue = "continue\nSkip to next iteration of loop",
		["else"] = "else body\nExecute body if previous if/elseif was false",
		["elseif"] = "elseif expr ?then? body\nConditional execution alternative",
		["then"] = "then\nOptional keyword in if statements",
		-- Advanced commands
		interp = "interp option ?arg ...?\nManage Tcl interpreters",
		load = "load fileName ?packageName? ?interp?\nLoad binary extension",
		rename = "rename oldName newName\nRename or delete commands",
		unknown = "unknown cmdName ?arg ...?\nHandler for unknown commands",
		vwait = "vwait varName\nWait for variable to be set",
		after = "after ms ?script?\nSchedule script execution",
		update = "update ?idletasks?\nProcess pending events",
		exit = "exit ?returnCode?\nTerminate application",
		pwd = "pwd\nReturn current working directory",
		cd = "cd ?dirName?\nChange current directory",
		exec = "exec ?switches? arg ?arg ...?\nExecute system commands",
		pid = "pid ?file?\nReturn process ID",
		time = "time script ?count?\nTime script execution",
		history = "history ?option? ?arg ...?\nCommand history management",
		-- Tk commands (if available)
		winfo = "winfo option ?arg ...?\nWindow information commands",
		wm = "wm option window ?arg ...?\nWindow manager commands",
		bind = "bind tag ?sequence? ?+??script?\nBind events to scripts",
		pack = "pack option arg ?arg ...?\nPack geometry manager",
		grid = "grid option arg ?arg ...?\nGrid geometry manager",
		place = "place option arg ?arg ...?\nPlace geometry manager",
		-- Rivet-specific commands
		hputs = "hputs string\nOutput HTML without escaping",
		hesc = "hesc string\nEscape HTML characters",
		makeurl = "makeurl ?-absolute? ?-relative? url ?arg value ...?\nGenerate URL with parameters",
		var_qs = "var_qs varname ?default?\nGet query string variable",
		var_post = "var_post varname ?default?\nGet POST form variable",
		import_keyvalue_pairs = "import_keyvalue_pairs\nImport form data as variables",
	}

	return tcl_docs[command]
end

-- Resolve a symbol using TCL's semantic engine (cached)
function M.resolve_symbol(symbol_name, file_path, cursor_line, tclsh_cmd)
	-- Check cache first
	local cached_resolution = get_cached_resolution(file_path, symbol_name, cursor_line)
	if cached_resolution then
		return cached_resolution
	end

	-- True semantic resolution using TCL's namespace and variable resolution
	local escaped_path = file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
	local semantic_resolution_script = string.format(
		[[
# True Semantic Symbol Resolution using TCL's resolution engine
set symbol_name "%s"
set file_path "%s"
set cursor_line %d

# Read the file
if {[catch {
    set fp [open $file_path r]
    set content [read $fp]
    close $fp
} err]} {
    puts "ERROR: Cannot read file: $err"
    exit 1
}

# Create a safe interpreter for semantic analysis
set safe_interp [interp create -safe]

# Set up the interpreter to track context as we parse
set current_namespace ""
set current_proc ""
set current_proc_params [list]
set namespace_stack [list]
set proc_stack [list]

# Track what's defined in each scope
set global_symbols [dict create]
set namespace_symbols [dict create]
set proc_symbols [dict create]

# Override commands to track symbol definitions during parsing
$safe_interp alias track_context track_context
$safe_interp alias track_symbol_def track_symbol_def
$safe_interp alias get_current_context get_current_context

proc track_context {type name args} {
    global current_namespace current_proc current_proc_params namespace_stack proc_stack
    
    if {$type eq "namespace"} {
        lappend namespace_stack $current_namespace
        set current_namespace $name
        puts "DEBUG: Entering namespace: $name"
    } elseif {$type eq "proc"} {
        set current_proc $name
        set current_proc_params $args
        puts "DEBUG: Entering proc: $name with params: $args"
    } elseif {$type eq "end_namespace"} {
        if {[llength $namespace_stack] > 0} {
            set current_namespace [lindex $namespace_stack end]
            set namespace_stack [lrange $namespace_stack 0 end-1]
        } else {
            set current_namespace ""
        }
        puts "DEBUG: Exiting namespace, now in: $current_namespace"
    } elseif {$type eq "end_proc"} {
        set current_proc ""
        set current_proc_params [list]
        puts "DEBUG: Exiting procedure"
    }
}

proc track_symbol_def {symbol_type symbol_name line_num scope} {
    global global_symbols namespace_symbols proc_symbols current_namespace current_proc
    
    set qualified_name $symbol_name
    if {$current_namespace ne "" && ![string match "::*" $symbol_name]} {
        set qualified_name "${current_namespace}::$symbol_name"
    }
    
    # Store symbol definition for later resolution
    if {$scope eq "global"} {
        dict set global_symbols $symbol_name [list line $line_num qualified $qualified_name]
    } elseif {$scope eq "namespace"} {
        if {![dict exists $namespace_symbols $current_namespace]} {
            dict set namespace_symbols $current_namespace [dict create]
        }
        dict set namespace_symbols $current_namespace $symbol_name [list line $line_num qualified $qualified_name]
    } elseif {$scope eq "local" && $current_proc ne ""} {
        set proc_key "${current_namespace}::$current_proc"
        if {![dict exists $proc_symbols $proc_key]} {
            dict set proc_symbols $proc_key [dict create]
        }
        dict set proc_symbols $proc_key $symbol_name [list line $line_num qualified $qualified_name]
    }
}

proc get_current_context {} {
    global current_namespace current_proc current_proc_params
    puts "CONTEXT:namespace:$current_namespace:proc:$current_proc:params:[join $current_proc_params ,]"
}

# Set up command overrides in safe interpreter
$safe_interp eval {
    set namespace_depth 0
    set proc_depth 0
    set brace_level 0
    
    rename proc _orig_proc
    proc proc {name args body} {
        track_context "proc" $name $args
        
        # Parse parameters
        foreach param_spec $args {
            if {[llength $param_spec] == 1} {
                track_symbol_def "parameter" $param_spec [info frame line] "parameter"
            } elseif {[llength $param_spec] == 2} {
                track_symbol_def "parameter" [lindex $param_spec 0] [info frame line] "parameter"
            }
        }
        
        # Don't actually execute the body, just track that we're in a proc
        # In a full implementation, we'd parse the body for variable definitions
        track_context "end_proc" "" ""
        return
    }
    
    rename namespace _orig_namespace
    proc namespace {subcommand args} {
        if {$subcommand eq "eval"} {
            set ns_name [lindex $args 0]
            set body [lindex $args 1]
            
            track_context "namespace" $ns_name ""
            track_symbol_def "namespace" $ns_name [info frame line] "namespace"
            
            # Execute the namespace body to find definitions
            eval $body
            
            track_context "end_namespace" "" ""
        }
        return
    }
    
    rename set _orig_set
    proc set {varname args} {
        if {[info exists ::current_proc] && $::current_proc ne ""} {
            track_symbol_def "variable" $varname [info frame line] "local"
        } elseif {[info exists ::current_namespace] && $::current_namespace ne ""} {
            track_symbol_def "variable" $varname [info frame line] "namespace"
        } else {
            track_symbol_def "variable" $varname [info frame line] "global"
        }
        return
    }
    
    rename global _orig_global
    proc global {args} {
        foreach var $args {
            track_symbol_def "global" $var [info frame line] "global"
        }
        return
    }
    
    # Disable side effects
    proc puts {args} { return }
    proc exec {args} { return }
    proc file {args} { return }
}

# Parse the file up to the cursor line to understand context
set lines [split $content "\n"]
set partial_content ""
set line_num 0

foreach line $lines {
    incr line_num
    append partial_content $line "\n"
    
    if {$line_num >= $cursor_line} {
        break
    }
}

# Evaluate the partial content to establish context at cursor
if {[catch {
    $safe_interp eval $partial_content
} parse_err]} {
    puts "DEBUG: Partial parsing failed: $parse_err"
    # Try command by command
    set command_buffer ""
    set brace_count 0
    
    foreach line [split $partial_content "\n"] {
        append command_buffer $line "\n"
        incr brace_count [regexp -all {\{} $line]
        incr brace_count -[regexp -all {\}} $line]
        
        if {$brace_count == 0 && [string trim $command_buffer] ne ""} {
            if {[catch {
                if {[info complete $command_buffer]} {
                    $safe_interp eval $command_buffer
                }
            }]} {
                # Skip failed commands
            }
            set command_buffer ""
        }
    }
}

# Get the current context at cursor position
get_current_context

# Now use TCL's actual resolution rules to resolve the symbol
puts "RESOLUTION_START"

# 1. Check if it's a parameter in current procedure (highest priority)
if {$current_proc ne "" && [lsearch $current_proc_params $symbol_name] >= 0} {
    puts "RESOLUTION:procedure_parameter:$symbol_name:priority:20:proc:$current_proc"
}

# 2. Use TCL's info commands to check for built-ins
if {[info commands $symbol_name] ne ""} {
    puts "RESOLUTION:builtin_command:$symbol_name:priority:15"
}

# 3. Check for qualified names using TCL's namespace resolution
if {[string match "*::*" $symbol_name]} {
    # Fully qualified - use as-is
    puts "RESOLUTION:qualified_name:$symbol_name:priority:14"
} else {
    # Unqualified - use TCL's resolution order
    
    # 3a. Local variables in current procedure
    if {$current_proc ne ""} {
        puts "RESOLUTION:proc_local_var:$symbol_name:priority:13:proc:$current_proc"
    }
    
    # 3b. Current namespace
    if {$current_namespace ne ""} {
        set ns_qualified "${current_namespace}::$symbol_name"
        puts "RESOLUTION:namespace_qualified:$ns_qualified:priority:12:namespace:$current_namespace"
    }
    
    # 3c. Imported commands (would need to track namespace import)
    # For now, skip this advanced feature
    
    # 3d. Global namespace
    puts "RESOLUTION:global:$symbol_name:priority:10"
}

# 4. Check for namespace children if symbol contains ::
if {[string match "*::*" $symbol_name]} {
    set ns_part [string range $symbol_name 0 [string last "::" $symbol_name]-1]
    set name_part [string range $symbol_name [string last "::" $symbol_name]+2 end]
    puts "RESOLUTION:namespace_child:$symbol_name:priority:11:namespace:$ns_part:name:$name_part"
}

puts "RESOLUTION_COMPLETE"

# Clean up
interp delete $safe_interp
]],
		symbol_name,
		escaped_path,
		cursor_line
	)

	local result, success = utils.execute_tcl_script(semantic_resolution_script, tclsh_cmd)

	if not (result and success) then
		return nil
	end

	local resolutions = {}
	local context = {}

	for line in result:gmatch("[^\n]+") do
		if line:match("CONTEXT:") then
			local ns, proc, params = line:match("CONTEXT:namespace:([^:]*):proc:([^:]*):params:([^:]*)")
			context.namespace = (ns ~= "") and ns or nil
			context.proc = (proc ~= "") and proc or nil
			context.proc_params = {}

			if params and params ~= "" then
				for param in params:gmatch("[^,]+") do
					if param ~= "" then
						table.insert(context.proc_params, param)
					end
				end
			end
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
					proc = "",
					namespace = "",
				}

				-- Parse additional semantic metadata
				local i = 5
				while i <= #parts do
					if parts[i] == "priority" and i < #parts then
						resolution.priority = tonumber(parts[i + 1]) or 0
						i = i + 2
					elseif parts[i] == "proc" and i < #parts then
						resolution.proc = parts[i + 1]
						i = i + 2
					elseif parts[i] == "namespace" and i < #parts then
						resolution.namespace = parts[i + 1]
						i = i + 2
					elseif parts[i] == "name" and i < #parts then
						resolution.unqualified_name = parts[i + 1]
						i = i + 2
					else
						i = i + 1
					end
				end

				table.insert(resolutions, resolution)
			end
		end
	end

	-- Sort resolutions by priority (higher priority first)
	table.sort(resolutions, function(a, b)
		return a.priority > b.priority
	end)

	local final_resolution = {
		context = context,
		resolutions = resolutions,
		method = "true_semantic",
	}

	-- Cache the result
	cache_resolution(file_path, symbol_name, cursor_line, final_resolution)

	return final_resolution
end

-- Clear cache for a specific file (call when file is saved/modified)
function M.invalidate_cache(file_path)
	file_cache[file_path] = nil

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
end

-- Debug function to see what symbols are being found
function M.debug_symbols(file_path, tclsh_cmd)
	local symbols = M.analyze_tcl_file(file_path, tclsh_cmd)

	if not symbols then
		print("DEBUG: No symbols found - analysis failed")
		return
	end

	print("DEBUG: Found " .. #symbols .. " symbols:")
	for i, symbol in ipairs(symbols) do
		print(
			string.format(
				"  %d. %s '%s' at line %d (scope: %s, context: %s)",
				i,
				symbol.type,
				symbol.name,
				symbol.line,
				symbol.scope or "none",
				symbol.context or "none"
			)
		)
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
