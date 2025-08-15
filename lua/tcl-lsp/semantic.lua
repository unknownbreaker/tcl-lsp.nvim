local utils = require("tcl-lsp.utils")
local M = {}

-- Create a semantic analysis script that uses TCL's runtime capabilities
function M.create_semantic_analysis_script(file_path)
	local escaped_path = file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
	return string.format(
		[[
# Semantic TCL Analysis Engine - Uses TCL's introspection
set file_path "%s"

# Track symbols with full context
proc track_symbol {type name line ns_context proc_context args body scope} {
    # Create qualified name
    set qualified_name $name
    if {$ns_context ne "" && ![string match "::*" $name]} {
        set qualified_name "${ns_context}::$name"
    }
    
    puts "SEMANTIC_SYMBOL:$type:$name:$qualified_name:$line:$scope:$ns_context:$proc_context:$args"
}

# Initialize analysis variables
set current_namespace ""
set current_proc ""
set current_line 0

# Read the file
if {[catch {
    set fp [open $file_path r]
    set content [read $fp]
    close $fp
} err]} {
    puts "ERROR: Cannot read file: $err"
    exit 1
}

# Process content line by line
set lines [split $content "\n"]
set line_num 0

foreach line $lines {
    incr line_num
    set current_line $line_num
    set trimmed [string trim $line]
    
    # Skip comments and empty lines
    if {$trimmed eq "" || [string index $trimmed 0] eq "#"} {
        continue
    }
    
    # Track namespace context
    if {[regexp {^\s*namespace\s+eval\s+([a-zA-Z_][a-zA-Z0-9_:]*)\s*\{} $line match ns_name]} {
        set old_namespace $current_namespace
        set current_namespace $ns_name
        track_symbol "namespace" $ns_name $line_num $old_namespace "" "" "" "namespace"
    }
    
    # Track procedure definitions
    if {[regexp {^\s*proc\s+([a-zA-Z_][a-zA-Z0-9_:]*)\s*\{([^}]*)\}\s*\{} $line match proc_name proc_args]} {
        set scope "global"
        if {$current_namespace ne ""} {
            set scope "namespace"
        }
        track_symbol "procedure" $proc_name $line_num $current_namespace $current_proc $proc_args "" $scope
        set current_proc $proc_name
    }
    
    # Track variable assignments
    if {[regexp {^\s*set\s+([a-zA-Z_][a-zA-Z0-9_:]*)\s+(.*)$} $line match var_name var_value]} {
        set scope "global"
        if {$current_proc ne ""} {
            set scope "local"
        } elseif {$current_namespace ne ""} {
            set scope "namespace"
        }
        track_symbol "variable" $var_name $line_num $current_namespace $current_proc "" $var_value $scope
    }
    
    # Track global variable declarations
    if {[regexp {^\s*global\s+(.+)$} $line match globals]} {
        foreach global_var [split $globals] {
            set clean_var [string trim $global_var]
            if {$clean_var ne ""} {
                track_symbol "global" $clean_var $line_num $current_namespace $current_proc "" "" "global"
            }
        }
    }
    
    # Track package operations
    if {[regexp {^\s*package\s+(require|provide)\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match cmd pkg_name]} {
        track_symbol "package" $pkg_name $line_num $current_namespace $current_proc $cmd "" "package"
    }
    
    # Track source operations
    if {[regexp {^\s*source\s+(.+)$} $line match source_file]} {
        set clean_file [string trim $source_file "\"'{}"]
        track_symbol "source" $clean_file $line_num $current_namespace $current_proc "" "" "source"
    }
    
    # Track variable references
    set var_refs [regexp -all -inline {\$([a-zA-Z_][a-zA-Z0-9_:]*)} $line]
    foreach {match var_name} $var_refs {
        puts "SEMANTIC_REFERENCE:variable:$var_name:$line_num:usage"
    }
    
    # Track procedure calls (command at start of line)
    if {[regexp {^\s*([a-zA-Z_][a-zA-Z0-9_:]*)\s} $line match cmd_name]} {
        # Skip known control structures and commands we already track
        if {![regexp {^(if|while|for|foreach|proc|set|namespace|global|package|source)$} $cmd_name]} {
            puts "SEMANTIC_REFERENCE:procedure:$cmd_name:$line_num:call"
        }
    }
    
    # Reset procedure context when we exit a procedure
    if {[regexp {^\s*\}\s*$} $line] && $current_proc ne ""} {
        set current_proc ""
    }
    
    # Reset namespace context when we exit a namespace
    if {[regexp {^\s*\}\s*$} $line] && $current_namespace ne ""} {
        # This is simplified - in real code you'd need to track brace nesting
        # For now, we'll just keep the namespace context
    }
}

puts "SEMANTIC_ANALYSIS_COMPLETE"
]],
		escaped_path
	)
end

-- Semantic symbol resolution
function M.resolve_symbol_semantically(symbol_name, file_path, cursor_line, tclsh_cmd)
	local analysis_script = M.create_semantic_analysis_script(file_path)

	local result, success = utils.execute_tcl_script(analysis_script, tclsh_cmd)

	if not (result and success) then
		return nil
	end

	local symbols = {}
	for line in result:gmatch("[^\n]+") do
		local type, name, qualified_name, line_num, scope, ns_context, proc_context, args =
			line:match("SEMANTIC_SYMBOL:([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]*):([^:]*):([^:]*)")

		if type and name and line_num then
			table.insert(symbols, {
				type = type,
				name = name,
				qualified_name = qualified_name,
				line = tonumber(line_num),
				scope = scope,
				namespace_context = ns_context,
				proc_context = proc_context,
				args = args,
				method = "semantic",
			})
		end
	end

	return symbols
end

-- Semantic reference finding
function M.find_references_semantically(symbol_name, file_path, tclsh_cmd)
	local escaped_path = file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
	local escaped_symbol = symbol_name:gsub("\\", "\\\\"):gsub('"', '\\"')

	local reference_script = string.format(
		[[
# Semantic reference finding for: %s
set target_symbol "%s"
set file_path "%s"

# Read file and track all references to target symbol
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
    
    # Look for variable usage: $symbol_name
    if {[regexp "\\$target_symbol\\y" $line]} {
        puts "SEMANTIC_REF:variable:$target_symbol:$line_num:usage:$line"
    }
    
    # Look for procedure calls: symbol_name (at start or after space)
    if {[regexp "(^|\\s)$target_symbol\\s*\\(" $line]} {
        puts "SEMANTIC_REF:procedure:$target_symbol:$line_num:call:$line"
    }
    
    # Look for definitions
    if {[regexp "^\\s*proc\\s+$target_symbol\\s" $line]} {
        puts "SEMANTIC_REF:procedure:$target_symbol:$line_num:definition:$line"
    }
    
    if {[regexp "^\\s*set\\s+$target_symbol\\s" $line]} {
        puts "SEMANTIC_REF:variable:$target_symbol:$line_num:definition:$line"
    }
}

puts "SEMANTIC_REFERENCES_COMPLETE"
]],
		escaped_symbol,
		escaped_symbol,
		escaped_path
	)

	local result, success = utils.execute_tcl_script(reference_script, tclsh_cmd)

	if not (result and success) then
		return nil
	end

	local references = {}
	for line in result:gmatch("[^\n]+") do
		local type, name, line_num, context, text = line:match("SEMANTIC_REF:([^:]+):([^:]+):([^:]+):([^:]+):(.+)")

		if type and name and line_num and context then
			table.insert(references, {
				type = type,
				name = name,
				line = tonumber(line_num),
				context = context,
				text = utils.trim(text),
				method = "semantic",
			})
		end
	end

	return references
end

return M
