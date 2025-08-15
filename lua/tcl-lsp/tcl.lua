local utils = require("tcl-lsp.utils")
local semantic = require("tcl-lsp.semantic") -- ADD this line at the top
local M = {}

-- EXISTING code stays the same until analyze_tcl_file function...

-- REPLACE the existing analyze_tcl_file function with this enhanced version:
function M.analyze_tcl_file(file_path, tclsh_cmd)
	-- Check cache first (existing cache logic)
	local cached_symbols = get_cached_analysis(file_path)
	if cached_symbols then
		return cached_symbols
	end

	-- Clean up old cache entries periodically
	if math.random(1, 20) == 1 then
		cleanup_cache()
	end

	-- TRY SEMANTIC ANALYSIS FIRST
	local semantic_symbols = semantic.resolve_symbol_semantically("", file_path, 0, tclsh_cmd)

	if semantic_symbols and #semantic_symbols > 0 then
		print("DEBUG: Using semantic analysis - found", #semantic_symbols, "symbols")
		-- Cache the semantic results
		cache_file_analysis(file_path, semantic_symbols)
		return semantic_symbols
	end

	-- FALLBACK TO EXISTING REGEX-BASED ANALYSIS
	print("DEBUG: Falling back to regex analysis")

	-- Your existing analysis_script code goes here unchanged...
	local analysis_script = string.format(
		[[
# Simple TCL Symbol Analysis Script (FALLBACK)
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

# Split into lines for line number tracking
set lines [split $content "\n"]
set line_num 0
set current_namespace ""

# Parse each line to find symbols (existing regex logic)
foreach line $lines {
    incr line_num
    set trimmed [string trim $line]
    
    # Skip comments and empty lines
    if {$trimmed eq "" || [string index $trimmed 0] eq "#"} {
        continue
    }
    
    # Find namespace definitions
    if {[regexp {^\s*namespace\s+eval\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match ns_name]} {
        set current_namespace $ns_name
        puts "SYMBOL:namespace:$ns_name:$line_num:$line"
    }
    
    # Find procedure definitions
    if {[regexp {^\s*proc\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match proc_name]} {
        if {$current_namespace ne "" && ![string match "*::*" $proc_name]} {
            set full_name "$current_namespace\::$proc_name"
        } else {
            set full_name $proc_name
        }
        puts "SYMBOL:procedure:$full_name:$line_num:$line"
        
        if {$full_name ne $proc_name} {
            puts "SYMBOL:procedure_local:$proc_name:$line_num:$line"
        }
    }
    
    # Find variable assignments
    if {[regexp {^\s*set\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match var_name]} {
        if {$current_namespace ne "" && ![string match "*::*" $var_name]} {
            set full_name "$current_namespace\::$var_name"
        } else {
            set full_name $var_name
        }
        puts "SYMBOL:variable:$full_name:$line_num:$line"
        
        if {$full_name ne $var_name} {
            puts "SYMBOL:variable_local:$var_name:$line_num:$line"
        }
    }
    
    # Find global variables
    if {[regexp {^\s*global\s+([a-zA-Z_][a-zA-Z0-9_:\s]*)} $line match globals]} {
        foreach global_var [split $globals] {
            if {$global_var ne ""} {
                puts "SYMBOL:global:$global_var:$line_num:$line"
            }
        }
    }
    
    # Find package commands
    if {[regexp {^\s*package\s+(require|provide)\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match cmd pkg_name]} {
        puts "SYMBOL:package:$pkg_name:$line_num:$line"
    }
    
    # Find source commands
    if {[regexp {^\s*source\s+(.+)$} $line match source_file]} {
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
		print("DEBUG: Both semantic and regex analysis failed")
		return nil
	end

	-- Parse regex results (existing logic)
	local symbols = {}
	for line in result:gmatch("[^\n]+") do
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
				qualified_name = "",
				method = "regex", -- Mark as regex-based
			}
			table.insert(symbols, symbol)
		end
	end

	-- Cache the results
	cache_file_analysis(file_path, symbols)
	return symbols
end

-- REPLACE the existing find_symbol_references function:
function M.find_symbol_references(file_path, symbol_name, tclsh_cmd)
	-- TRY SEMANTIC REFERENCE FINDING FIRST
	local semantic_refs = semantic.find_references_semantically(symbol_name, file_path, tclsh_cmd)

	if semantic_refs and #semantic_refs > 0 then
		print("DEBUG: Using semantic reference finding - found", #semantic_refs, "references")
		return semantic_refs
	end

	-- FALLBACK TO EXISTING REGEX-BASED REFERENCE FINDING
	print("DEBUG: Falling back to regex reference finding")

	-- Your existing reference_script code (unchanged)...
	local reference_script = string.format(
		[[
# Find references to a symbol (FALLBACK)
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
    set parts [split $target_word "::"]
    set unqualified [lindex $parts end]
} else {
    set unqualified $target_word
}

foreach line $lines {
    incr line_num
    
    # Check if line contains the target word (exact match)
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
        } elseif {[regexp "$target_word\\s*\\(" $line]} {
            set context "procedure_call"
        }
        
        puts "REFERENCE:$context:$line_num:$line"
    } elseif {$is_qualified && [regexp "\\y$unqualified\\y" $line]} {
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
				method = "regex", -- Mark as regex-based
			})
		end
	end

	return references
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
