local utils = require("tcl-lsp.utils")
local M = {}

-- Cache for cross-file analysis
local workspace_cache = {}
local source_dependency_cache = {}

-- Build a dependency graph of source files
function M.build_source_dependencies(file_path, tclsh_cmd, visited)
	visited = visited or {}

	-- Avoid circular dependencies
	if visited[file_path] then
		return {}
	end
	visited[file_path] = true

	-- Check cache
	if source_dependency_cache[file_path] then
		return source_dependency_cache[file_path]
	end

	local dependencies = { file_path } -- Include self

	-- Analyze the file to find source commands
	local source_script = string.format(
		[[
set file_path "%s"
set dependencies [list]

if {[catch {
    set fp [open $file_path r]
    set content [read $fp]
    close $fp
} err]} {
    puts "ERROR: Cannot read file: $err"
    exit 1
}

set lines [split $content "\n"]
foreach line $lines {
    set trimmed [string trim $line]
    
    # Skip comments and empty lines
    if {$trimmed eq "" || [string index $trimmed 0] eq "#"} {
        continue
    }
    
    # Find source commands
    if {[regexp {^\s*source\s+(.+)$} $line match source_file]} {
        set clean_file [string trim $source_file "\"'{}"]
        
        # Handle relative paths
        if {![string match "/*" $clean_file]} {
            set dir [file dirname $file_path]
            set clean_file [file join $dir $clean_file]
        }
        
        # Normalize the path
        set clean_file [file normalize $clean_file]
        
        puts "SOURCE_DEPENDENCY:$clean_file"
    }
    
    # Find package require commands (for tcllib, custom packages)
    if {[regexp {^\s*package\s+require\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match pkg_name]} {
        puts "PACKAGE_DEPENDENCY:$pkg_name"
    }
}

puts "DEPENDENCIES_COMPLETE"
]],
		file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
	)

	local result, success = utils.execute_tcl_script(source_script, tclsh_cmd)

	if result and success then
		for line in result:gmatch("[^\n]+") do
			local dep_file = line:match("SOURCE_DEPENDENCY:(.+)")
			if dep_file and utils.file_exists(dep_file) then
				table.insert(dependencies, dep_file)

				-- Recursively find dependencies of dependencies
				local sub_deps = M.build_source_dependencies(dep_file, tclsh_cmd, visited)
				for _, sub_dep in ipairs(sub_deps) do
					if not vim.tbl_contains(dependencies, sub_dep) then
						table.insert(dependencies, sub_dep)
					end
				end
			end
		end
	end

	-- Cache the result
	source_dependency_cache[file_path] = dependencies
	return dependencies
end

-- Analyze multiple files and build a comprehensive symbol database
function M.analyze_workspace_symbols(file_path, tclsh_cmd)
	-- Get all related files through source dependencies
	local related_files = M.build_source_dependencies(file_path, tclsh_cmd)

	-- Also include common TCL files in the same directory
	local current_dir = vim.fn.fnamemodify(file_path, ":h")
	local tcl_files = vim.fn.glob(current_dir .. "/*.tcl", false, true)

	for _, tcl_file in ipairs(tcl_files) do
		if not vim.tbl_contains(related_files, tcl_file) then
			table.insert(related_files, tcl_file)
		end
	end

	print("DEBUG: Analyzing", #related_files, "related files for workspace symbols")

	local all_symbols = {}

	for _, analyze_file in ipairs(related_files) do
		if utils.file_exists(analyze_file) then
			local file_symbols = M.analyze_single_file_symbols(analyze_file, tclsh_cmd)
			if file_symbols then
				for _, symbol in ipairs(file_symbols) do
					symbol.source_file = analyze_file
					symbol.is_imported = (analyze_file ~= file_path)
					table.insert(all_symbols, symbol)
				end
			end
		end
	end

	print("DEBUG: Found", #all_symbols, "total symbols across workspace")
	return all_symbols
end

-- Enhanced single file analysis
function M.analyze_single_file_symbols(file_path, tclsh_cmd)
	local escaped_path = file_path:gsub("\\", "\\\\"):gsub('"', '\\"')

	local analysis_script = string.format(
		[[
# Enhanced single file semantic analysis
set file_path "%s"

# Track symbols with enhanced context
proc track_symbol {type name line ns_context proc_context args body scope visibility} {
    set qualified_name $name
    if {$ns_context ne "" && ![string match "::*" $name]} {
        set qualified_name "${ns_context}::$name"
    }
    
    puts "SEMANTIC_SYMBOL:$type:$name:$qualified_name:$line:$scope:$ns_context:$proc_context:$args:$visibility"
}

# Initialize analysis variables
set current_namespace ""
set current_proc ""
set current_line 0
set namespace_stack [list]

if {[catch {
    set fp [open $file_path r]
    set content [read $fp]
    close $fp
} err]} {
    puts "ERROR: Cannot read file: $err"
    exit 1
}

# Enhanced parsing with better context tracking
set lines [split $content "\n"]
set line_num 0
set brace_level 0

foreach line $lines {
    incr line_num
    set current_line $line_num
    set trimmed [string trim $line]
    
    if {$trimmed eq "" || [string index $trimmed 0] eq "#"} {
        continue
    }
    
    # Track brace levels for context
    set open_braces [regexp -all {\{} $line]
    set close_braces [regexp -all {\}} $line]
    set brace_level [expr {$brace_level + $open_braces - $close_braces}]
    
    # Enhanced namespace tracking with stack
    if {[regexp {^\s*namespace\s+eval\s+([a-zA-Z_][a-zA-Z0-9_:]*)\s*\{} $line match ns_name]} {
        lappend namespace_stack $current_namespace
        set current_namespace $ns_name
        track_symbol "namespace" $ns_name $line_num "" "" "" "" "namespace" "public"
    }
    
    # Enhanced procedure definitions with argument parsing
    if {[regexp {^\s*proc\s+([a-zA-Z_][a-zA-Z0-9_:]*)\s*\{([^}]*)\}} $line match proc_name proc_args]} {
        set scope "global"
        set visibility "public"
        
        if {$current_namespace ne ""} {
            set scope "namespace"
        }
        if {$current_proc ne ""} {
            set scope "local"
            set visibility "private"
        }
        
        # Parse arguments
        set clean_args [string trim $proc_args]
        track_symbol "procedure" $proc_name $line_num $current_namespace $current_proc $clean_args "" $scope $visibility
        set current_proc $proc_name
    }
    
    # Enhanced variable tracking with type detection
    if {[regexp {^\s*set\s+([a-zA-Z_][a-zA-Z0-9_:]*)\s+(.*)$} $line match var_name var_value]} {
        set scope "global"
        set visibility "public"
        
        if {$current_proc ne ""} {
            set scope "local"
            set visibility "private"
        } elseif {$current_namespace ne ""} {
            set scope "namespace"
        }
        
        # Detect variable type from value
        set var_type "variable"
        if {[regexp {^\[.*\]$} $var_value]} {
            set var_type "command_result"
        } elseif {[regexp {^\{.*\}$} $var_value]} {
            set var_type "list_or_dict"
        } elseif {[regexp {^".*"$} $var_value]} {
            set var_type "string"
        } elseif {[regexp {^[0-9]+$} $var_value]} {
            set var_type "number"
        }
        
        track_symbol $var_type $var_name $line_num $current_namespace $current_proc "" $var_value $scope $visibility
    }
    
    # Enhanced global variable tracking
    if {[regexp {^\s*global\s+(.+)$} $line match globals]} {
        foreach global_var [split $globals] {
            set clean_var [string trim $global_var]
            if {$clean_var ne ""} {
                track_symbol "global" $clean_var $line_num $current_namespace $current_proc "" "" "global" "public"
            }
        }
    }
    
    # Enhanced package tracking
    if {[regexp {^\s*package\s+(require|provide)\s+([a-zA-Z_][a-zA-Z0-9_:]*)\s*(.*)$} $line match cmd pkg_name version]} {
        track_symbol "package" $pkg_name $line_num $current_namespace $current_proc $cmd $version "package" "public"
    }
    
    # Array variable tracking
    if {[regexp {^\s*array\s+set\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match array_name]} {
        set scope "global"
        if {$current_proc ne ""} {
            set scope "local"
        } elseif {$current_namespace ne ""} {
            set scope "namespace"
        }
        track_symbol "array" $array_name $line_num $current_namespace $current_proc "" "" $scope "public"
    }
    
    # Source file tracking
    if {[regexp {^\s*source\s+(.+)$} $line match source_file]} {
        set clean_file [string trim $source_file "\"'{}"]
        track_symbol "source" $clean_file $line_num $current_namespace $current_proc "" "" "source" "public"
    }
    
    # Reset contexts when exiting scopes
    if {$close_braces > 0} {
        if {$current_proc ne "" && $brace_level <= 0} {
            set current_proc ""
        }
        if {$current_namespace ne "" && $brace_level <= 0 && [llength $namespace_stack] > 0} {
            set current_namespace [lindex $namespace_stack end]
            set namespace_stack [lrange $namespace_stack 0 end-1]
        }
    }
}

puts "SEMANTIC_ANALYSIS_COMPLETE"
]],
		escaped_path
	)

	local result, success = utils.execute_tcl_script(analysis_script, tclsh_cmd)

	if not (result and success) then
		return nil
	end

	local symbols = {}
	for line in result:gmatch("[^\n]+") do
		local type, name, qualified_name, line_num, scope, ns_context, proc_context, args, visibility =
			line:match("SEMANTIC_SYMBOL:([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]*):([^:]*):([^:]*):([^:]*)")

		if type and name and line_num then
			table.insert(symbols, {
				type = type,
				name = name,
				qualified_name = qualified_name,
				line = tonumber(line_num),
				scope = scope,
				namespace_context = ns_context ~= "" and ns_context or nil,
				proc_context = proc_context ~= "" and proc_context or nil,
				args = args ~= "" and args or nil,
				visibility = visibility,
				method = "semantic",
				text = line, -- We'll need to get this separately if needed
			})
		end
	end

	return symbols
end

-- Smart symbol resolution across files
function M.resolve_symbol_across_workspace(symbol_name, file_path, cursor_line, tclsh_cmd)
	print("DEBUG: Resolving symbol", symbol_name, "across workspace")

	-- Get all workspace symbols
	local all_symbols = M.analyze_workspace_symbols(file_path, tclsh_cmd)

	if not all_symbols or #all_symbols == 0 then
		print("DEBUG: No workspace symbols found")
		return nil
	end

	local candidates = {}

	-- Find matching symbols with priority scoring
	for _, symbol in ipairs(all_symbols) do
		local score = 0
		local match_type = "none"

		-- Exact name match
		if symbol.name == symbol_name then
			score = score + 100
			match_type = "exact"
		elseif symbol.qualified_name == symbol_name then
			score = score + 95
			match_type = "qualified_exact"
		end

		-- Partial matches (unqualified name matches qualified symbol)
		if match_type == "none" then
			if symbol.qualified_name and symbol.qualified_name:match("::" .. symbol_name .. "$") then
				score = score + 80
				match_type = "unqualified_match"
			end

			if symbol.name:match("^" .. symbol_name) then
				score = score + 60
				match_type = "prefix_match"
			end
		end

		-- Skip if no match
		if score == 0 then
			goto continue
		end

		-- Boost score based on file proximity
		if symbol.source_file == file_path then
			score = score + 50 -- Same file
		elseif not symbol.is_imported then
			score = score + 20 -- Local workspace
		end

		-- Boost score based on visibility and scope
		if symbol.visibility == "public" then
			score = score + 10
		end

		if symbol.scope == "global" then
			score = score + 5
		end

		table.insert(candidates, {
			symbol = symbol,
			score = score,
			match_type = match_type,
		})

		::continue::
	end

	-- Sort by score (highest first)
	table.sort(candidates, function(a, b)
		return a.score > b.score
	end)

	-- Return top candidates
	local results = {}
	for i = 1, math.min(#candidates, 10) do
		table.insert(results, candidates[i].symbol)
	end

	print("DEBUG: Found", #results, "symbol candidates")
	return results
end

-- Cross-file reference finding
function M.find_references_across_workspace(symbol_name, file_path, tclsh_cmd)
	print("DEBUG: Finding references for", symbol_name, "across workspace")

	-- Get all related files
	local related_files = M.build_source_dependencies(file_path, tclsh_cmd)

	-- Also search common TCL files in workspace
	local workspace_files = vim.fn.glob("**/*.tcl", false, true)
	for _, tcl_file in ipairs(workspace_files) do
		if not vim.tbl_contains(related_files, tcl_file) then
			table.insert(related_files, tcl_file)
		end
	end

	local all_references = {}

	for _, search_file in ipairs(related_files) do
		if utils.file_exists(search_file) then
			local file_refs = M.find_references_in_single_file(symbol_name, search_file, tclsh_cmd)
			if file_refs then
				for _, ref in ipairs(file_refs) do
					ref.source_file = search_file
					ref.is_external = (search_file ~= file_path)
					table.insert(all_references, ref)
				end
			end
		end
	end

	print("DEBUG: Found", #all_references, "references across", #related_files, "files")
	return all_references
end

-- Find references in a single file
function M.find_references_in_single_file(symbol_name, file_path, tclsh_cmd)
	local escaped_path = file_path:gsub("\\", "\\\\"):gsub('"', '\\"')
	local escaped_symbol = symbol_name:gsub("\\", "\\\\"):gsub('"', '\\"')

	local reference_script = string.format(
		[[
set target_symbol "%s"
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
    
    # Variable usage: $symbol_name
    if {[regexp "\\$$target_symbol\\y" $line]} {
        puts "WORKSPACE_REF:variable:$target_symbol:$line_num:usage:$line"
    }
    
    # Procedure calls
    if {[regexp "(^|\\s)$target_symbol\\s*\\(" $line] || [regexp "(^|\\s)$target_symbol\\s+[^=]" $line]} {
        puts "WORKSPACE_REF:procedure:$target_symbol:$line_num:call:$line"
    }
    
    # Definitions
    if {[regexp "^\\s*proc\\s+$target_symbol\\s" $line]} {
        puts "WORKSPACE_REF:procedure:$target_symbol:$line_num:definition:$line"
    }
    
    if {[regexp "^\\s*set\\s+$target_symbol\\s" $line]} {
        puts "WORKSPACE_REF:variable:$target_symbol:$line_num:definition:$line"
    }
    
    # Namespace qualified references
    if {[regexp "::$target_symbol\\y" $line]} {
        puts "WORKSPACE_REF:qualified:$target_symbol:$line_num:qualified_usage:$line"
    }
}

puts "WORKSPACE_REFERENCES_COMPLETE"
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
		local type, name, line_num, context, text = line:match("WORKSPACE_REF:([^:]+):([^:]+):([^:]+):([^:]+):(.+)")

		if type and name and line_num and context then
			table.insert(references, {
				type = type,
				name = name,
				line = tonumber(line_num),
				context = context,
				text = utils.trim(text),
				method = "workspace_semantic",
			})
		end
	end

	return references
end

-- Clear workspace cache when files change
function M.invalidate_workspace_cache()
	workspace_cache = {}
	source_dependency_cache = {}
end

return M
