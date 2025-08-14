-- lua/tcl-lsp/tcl.lua
-- TCL execution and introspection functions

local utils = require("tcl-lsp.utils")
local M = {}

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

-- Use TCL to analyze a file and extract symbols with their locations
function M.analyze_tcl_file(file_path, tclsh_cmd)
	local analysis_script = string.format(
		[[
# TCL Symbol Analysis Script
set file_path "%s"
set symbols [list]

# Read the file
if {[catch {
    set fp [open $file_path r]
    set content [read $fp]
    close $fp
} err]} {
    puts "ERROR: Cannot read file: $err"
    exit 1
}

# Split into lines for line number tracking
set lines [split $content "\n"]
set line_num 0

# Parse each line to find symbols
foreach line $lines {
    incr line_num
    set trimmed [string trim $line]
    
    # Skip comments and empty lines
    if {$trimmed eq "" || [string index $trimmed 0] eq "#"} {
        continue
    }
    
    # Find procedure definitions
    if {[regexp {^\s*proc\s+([a-zA-Z_][a-zA-Z0-9_:]*)\s*\{(.*)$} $line match proc_name args]} {
        puts "SYMBOL:procedure:$proc_name:$line_num:$line"
    }
    
    # Find variable assignments (set commands)
    if {[regexp {^\s*set\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match var_name]} {
        puts "SYMBOL:variable:$var_name:$line_num:$line"
    }
    
    # Find namespace definitions
    if {[regexp {^\s*namespace\s+eval\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match ns_name]} {
        puts "SYMBOL:namespace:$ns_name:$line_num:$line"
    }
    
    # Find global variable declarations
    if {[regexp {^\s*global\s+([a-zA-Z_][a-zA-Z0-9_:\s]*)} $line match globals]} {
        foreach global_var [split $globals] {
            if {$global_var ne ""} {
                puts "SYMBOL:global:$global_var:$line_num:$line"
            }
        }
    }
    
    # Find package requirements
    if {[regexp {^\s*package\s+require\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match pkg_name]} {
        puts "SYMBOL:package:$pkg_name:$line_num:$line"
    }
    
    # Find source commands
    if {[regexp {^\s*source\s+(.+)$} $line match source_file]} {
        # Clean up the filename (remove quotes, etc.)
        set clean_file [string trim $source_file "\"'\{\}"]
        puts "SYMBOL:source:$clean_file:$line_num:$line"
    }
}

puts "ANALYSIS_COMPLETE"
]],
		file_path
	)

	local result, success = utils.execute_tcl_script(analysis_script, tclsh_cmd)

	if not (result and success) then
		return nil
	end

	local symbols = {}
	for line in result:gmatch("[^\n]+") do
		local symbol_type, name, line_num, text = line:match("SYMBOL:([^:]+):([^:]+):([^:]+):(.+)")
		if symbol_type and name and line_num and text then
			table.insert(symbols, {
				type = symbol_type,
				name = name,
				line = tonumber(line_num),
				text = text,
			})
		end
	end

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

foreach line $lines {
    incr line_num
    
    # Check if line contains the target word
    # Use word boundaries to avoid partial matches
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
		["continue"] = "continue\nSkip to next iteration of loop",
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

-- Execute a TCL command and capture its output
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
