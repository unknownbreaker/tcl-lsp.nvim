-- Enhanced semantic.lua with better cross-file symbol resolution
local utils = require("tcl-lsp.utils")
local M = {}

-- Cache for cross-file analysis
local workspace_cache = {}
local source_dependency_cache = {}
local symbol_index_cache = {}

-- Enhanced dependency graph building with better path resolution
function M.build_source_dependencies(file_path, tclsh_cmd, visited)
	visited = visited or {}

	-- Avoid circular dependencies
	if visited[file_path] then
		return {}
	end
	visited[file_path] = true

	-- Check cache first
	local cache_key = file_path .. ":" .. (tclsh_cmd or "default")
	if source_dependency_cache[cache_key] then
		local cached = source_dependency_cache[cache_key]
		-- Check if cache is still valid (file not modified)
		if vim.fn.getftime(file_path) <= cached.timestamp then
			return cached.dependencies
		end
	end

	local dependencies = { file_path } -- Include self

	-- Enhanced source analysis with better path resolution
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
set current_dir [file dirname $file_path]

foreach line $lines {
    set trimmed [string trim $line]
    
    # Skip comments and empty lines
    if {$trimmed eq "" || [string index $trimmed 0] eq "#"} {
        continue
    }
    
    # Enhanced source command detection
    if {[regexp {^\s*source\s+(.+)$} $line match source_file]} {
        # Clean up the filename (remove quotes, braces, etc.)
        set clean_file [string trim $source_file "\"'{}"]
        
        # Handle variable substitution in filenames (basic)
        if {[string match "*$*" $clean_file]} {
            # Try common variable patterns
            set clean_file [string map [list {$::env(HOME)} $::env(HOME)] $clean_file]
            # Add more substitutions as needed
        }
        
        # Resolve relative paths
        if {![string match "/*" $clean_file]} {
            set clean_file [file join $current_dir $clean_file]
        }
        
        # Normalize and check if file exists
        set clean_file [file normalize $clean_file]
        if {[file exists $clean_file]} {
            puts "SOURCE_DEPENDENCY:$clean_file"
        } else {
            # Try common alternative locations
            set alternatives [list]
            lappend alternatives \[file join $current_dir "lib" [file tail $clean_file]\]
            lappend alternatives \[file join $current_dir "src" [file tail $clean_file]\]
            lappend alternatives \[file join $current_dir "tcl" [file tail $clean_file]\]
            lappend alternatives \[file join [file dirname $current_dir] [file tail $clean_file]\]
            
            foreach alt $alternatives {
                set alt [file normalize $alt]
                if {[file exists $alt]} {
                    puts "SOURCE_DEPENDENCY:$alt"
                    break
                }
            }
        }
    }
    
    # Package require commands (for finding package files)
    if {[regexp {^\s*package\s+require\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match pkg_name]} {
        puts "PACKAGE_DEPENDENCY:$pkg_name"
        
        # Try to find package files in common locations
        set pkg_paths [list]
        lappend pkg_paths [file join $current_dir "$pkg_name.tcl"]
        lappend pkg_paths [file join $current_dir "lib" "$pkg_name.tcl"]
        lappend pkg_paths [file join $current_dir "packages" "$pkg_name.tcl"]
        
        foreach pkg_path $pkg_paths {
            if {[file exists $pkg_path]} {
                puts "SOURCE_DEPENDENCY:$pkg_path"
                break
            }
        }
    }
    
    # namespace import commands (helps track cross-namespace dependencies)
    if {[regexp {^\s*namespace\s+import\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match import_pattern]} {
        puts "NAMESPACE_IMPORT:$import_pattern"
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
			if dep_file and utils.file_exists(dep_file) and dep_file ~= file_path then
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
	source_dependency_cache[cache_key] = {
		dependencies = dependencies,
		timestamp = vim.fn.getftime(file_path),
	}

	return dependencies
end

-- Build a comprehensive workspace symbol index
function M.build_workspace_symbol_index(root_file, tclsh_cmd)
	local cache_key = root_file .. ":" .. (tclsh_cmd or "default")

	-- Check if we have a valid cached index
	if symbol_index_cache[cache_key] then
		local cached = symbol_index_cache[cache_key]
		local current_time = os.time()

		-- Cache valid for 5 minutes or until any indexed file changes
		if (current_time - cached.created_time) < 300 then
			local cache_valid = true
			for file_path, file_mtime in pairs(cached.file_mtimes) do
				if vim.fn.getftime(file_path) > file_mtime then
					cache_valid = false
					break
				end
			end

			if cache_valid then
				return cached.index
			end
		end
	end

	-- Get all related files
	local related_files = M.build_source_dependencies(root_file, tclsh_cmd)

	-- Add common workspace files
	local workspace_files = vim.fn.glob("**/*.tcl", false, true)
	for _, file in ipairs(workspace_files) do
		if not vim.tbl_contains(related_files, file) and utils.file_exists(file) then
			table.insert(related_files, file)
		end
	end

	local index = {
		files = {},
		symbols = {},
		by_name = {},
		by_type = {},
		by_namespace = {},
		qualified_names = {},
		cross_references = {},
		total_symbols = 0,
		file_count = #related_files,
	}

	local file_mtimes = {}

	for _, file_path in ipairs(related_files) do
		if utils.file_exists(file_path) then
			local file_symbols = M.analyze_single_file_symbols(file_path, tclsh_cmd)
			file_mtimes[file_path] = vim.fn.getftime(file_path)

			if file_symbols then
				index.files[file_path] = {
					path = file_path,
					symbols = file_symbols,
					symbol_count = #file_symbols,
				}

				for _, symbol in ipairs(file_symbols) do
					-- Add file reference
					symbol.source_file = file_path
					symbol.is_external = (file_path ~= root_file)

					-- Add to main symbol list
					table.insert(index.symbols, symbol)

					-- Index by name
					if not index.by_name[symbol.name] then
						index.by_name[symbol.name] = {}
					end
					table.insert(index.by_name[symbol.name], symbol)

					-- Index by qualified name if different
					if symbol.qualified_name and symbol.qualified_name ~= symbol.name then
						if not index.qualified_names[symbol.qualified_name] then
							index.qualified_names[symbol.qualified_name] = {}
						end
						table.insert(index.qualified_names[symbol.qualified_name], symbol)
					end

					-- Index by type
					if not index.by_type[symbol.type] then
						index.by_type[symbol.type] = {}
					end
					table.insert(index.by_type[symbol.type], symbol)

					-- Index by namespace
					if symbol.namespace_context then
						if not index.by_namespace[symbol.namespace_context] then
							index.by_namespace[symbol.namespace_context] = {}
						end
						table.insert(index.by_namespace[symbol.namespace_context], symbol)
					end

					index.total_symbols = index.total_symbols + 1
				end
			end
		end
	end

	-- Cache the index
	symbol_index_cache[cache_key] = {
		index = index,
		file_mtimes = file_mtimes,
		created_time = os.time(),
	}

	return index
end

-- Enhanced symbol resolution using the workspace index
function M.resolve_symbol_with_workspace_index(symbol_name, root_file, cursor_line, tclsh_cmd)
	local index = M.build_workspace_symbol_index(root_file, tclsh_cmd)

	local candidates = {}

	-- 1. Look for exact name matches
	if index.by_name[symbol_name] then
		for _, symbol in ipairs(index.by_name[symbol_name]) do
			table.insert(candidates, {
				symbol = symbol,
				score = symbol.is_external and 80 or 100, -- Prefer local symbols
				match_type = "exact_name",
			})
		end
	end

	-- 2. Look for qualified name matches
	if index.qualified_names[symbol_name] then
		for _, symbol in ipairs(index.qualified_names[symbol_name]) do
			table.insert(candidates, {
				symbol = symbol,
				score = symbol.is_external and 85 or 95,
				match_type = "exact_qualified",
			})
		end
	end

	-- 3. Look for unqualified matches of qualified symbols
	if symbol_name:match("::") then
		local unqualified = symbol_name:match("([^:]+)$")
		if index.by_name[unqualified] then
			for _, symbol in ipairs(index.by_name[unqualified]) do
				if symbol.qualified_name and symbol.qualified_name:match("::" .. unqualified .. "$") then
					table.insert(candidates, {
						symbol = symbol,
						score = symbol.is_external and 70 or 90,
						match_type = "unqualified_of_qualified",
					})
				end
			end
		end
	else
		-- 4. Look for qualified versions of unqualified search
		for qualified_name, symbols in pairs(index.qualified_names) do
			if qualified_name:match("::" .. symbol_name .. "$") then
				for _, symbol in ipairs(symbols) do
					table.insert(candidates, {
						symbol = symbol,
						score = symbol.is_external and 60 or 75,
						match_type = "qualified_of_unqualified",
					})
				end
			end
		end
	end

	-- 5. Type-specific bonuses
	for _, candidate in ipairs(candidates) do
		local symbol = candidate.symbol

		-- Boost procedures and namespaces
		if symbol.type == "procedure" or symbol.type == "namespace" then
			candidate.score = candidate.score + 10
		end

		-- Boost public symbols
		if symbol.visibility == "public" then
			candidate.score = candidate.score + 5
		end

		-- Boost symbols in same namespace context
		-- (You'd need to track current namespace from cursor position)
	end

	-- Sort by score
	table.sort(candidates, function(a, b)
		return a.score > b.score
	end)

	return candidates
end

-- Enhanced single file analysis with better context tracking
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
set brace_level 0

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
    
    # Namespace import tracking
    if {[regexp {^\s*namespace\s+import\s+(.+)$} $line match import_pattern]} {
        track_symbol "import" $import_pattern $line_num $current_namespace $current_proc "" "" "import" "public"
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
				qualified_name = qualified_name ~= "" and qualified_name or nil,
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

-- Find all symbols that could match a query across workspace
function M.find_workspace_symbol_candidates(symbol_name, root_file, tclsh_cmd)
	local index = M.build_workspace_symbol_index(root_file, tclsh_cmd)
	local candidates = M.resolve_symbol_with_workspace_index(symbol_name, root_file, 0, tclsh_cmd)

	return candidates, index
end

-- Enhanced cross-file reference finding with better scope resolution
function M.find_references_across_workspace(symbol_name, file_path, tclsh_cmd)
	local related_files = M.build_source_dependencies(file_path, tclsh_cmd)

	-- Also search broader workspace
	local workspace_files = vim.fn.glob("**/*.tcl", false, true)
	for _, tcl_file in ipairs(workspace_files) do
		if not vim.tbl_contains(related_files, tcl_file) then
			table.insert(related_files, tcl_file)
		end
	end

	local all_references = {}

	for _, search_file in ipairs(related_files) do
		if utils.file_exists(search_file) then
			local file_refs = M.find_references_in_single_file_enhanced(symbol_name, search_file, tclsh_cmd)
			if file_refs then
				for _, ref in ipairs(file_refs) do
					ref.source_file = search_file
					ref.is_external = (search_file ~= file_path)
					table.insert(all_references, ref)
				end
			end
		end
	end

	return all_references
end

-- Enhanced single-file reference finding with better context awareness
function M.find_references_in_single_file_enhanced(symbol_name, file_path, tclsh_cmd)
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
set current_namespace ""
set current_proc ""

# Check if target_symbol contains namespace qualifier
set is_qualified [string match "*::*" $target_symbol]
if {$is_qualified} {
    set parts [split $target_symbol "::"]
    set unqualified [lindex $parts end]
    set target_namespace [join [lrange $parts 0 end-1] "::"]
} else {
    set unqualified $target_symbol
    set target_namespace ""
}

foreach line $lines {
    incr line_num
    
    # Track current context
    if {[regexp {^\s*namespace\s+eval\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match ns_name]} {
        set current_namespace $ns_name
    }
    if {[regexp {^\s*proc\s+([a-zA-Z_][a-zA-Z0-9_:]*)} $line match proc_name]} {
        set current_proc $proc_name
    }
    
    # Enhanced reference detection
    set found_reference 0
    set ref_type "usage"
    set context_info ""
    
    # 1. Exact symbol match
    if {[regexp "\\y$target_symbol\\y" $line]} {
        set found_reference 1
        set context_info "exact:$current_namespace:$current_proc"
        
        # Determine reference type
        if {[regexp "^\\s*proc\\s+$target_symbol\\s" $line]} {
            set ref_type "definition:procedure"
        } elseif {[regexp "^\\s*set\\s+$target_symbol\\s" $line]} {
            set ref_type "definition:variable"
        } elseif {[regexp "^\\s*namespace\\s+eval\\s+$target_symbol\\s" $line]} {
            set ref_type "definition:namespace"
        } elseif {[regexp "\\$target_symbol\\y" $line]} {
            set ref_type "variable_usage"
        } elseif {[regexp "$target_symbol\\s*\\(" $line] || [regexp "$target_symbol\\s+\[^=\]" $line]} {
            set ref_type "procedure_call"
        }
    }
    
    # 2. Unqualified match (if target is qualified)
    if {!$found_reference && $is_qualified && [regexp "\\y$unqualified\\y" $line]} {
        # Check if we're in the right namespace context
        if {$current_namespace eq $target_namespace || $target_namespace eq ""} {
            set found_reference 1
            set context_info "unqualified:$current_namespace:$current_proc"
            set ref_type "usage_unqualified"
            
            if {[regexp "^\\s*proc\\s+$unqualified\\s" $line]} {
                set ref_type "definition:procedure_local"
            } elseif {[regexp "^\\s*set\\s+$unqualified\\s" $line]} {
                set ref_type "definition:variable_local"
            } elseif {[regexp "\\$unqualified\\y" $line]} {
                set ref_type "variable_usage_local"
            } elseif {[regexp "$unqualified\\s*\\(" $line]} {
                set ref_type "procedure_call_local"
            }
        }
    }
    
    # 3. Qualified match (if target is unqualified but line has qualified reference)
    if {!$found_reference && !$is_qualified} {
        if {[regexp "(\\w+::)*$target_symbol\\y" $line match_qualified]} {
            set found_reference 1
            set context_info "qualified:$current_namespace:$current_proc"
            set ref_type "usage_qualified"
        }
    }
    
    if {$found_reference} {
        puts "WORKSPACE_REF:$ref_type:$target_symbol:$line_num:$context_info:$line"
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
				method = "workspace_semantic_enhanced",
			})
		end
	end

	return references
end

-- Clear workspace cache when files change
function M.invalidate_workspace_cache()
	workspace_cache = {}
	source_dependency_cache = {}
	symbol_index_cache = {}
end

-- Get statistics about the workspace analysis
function M.get_workspace_stats(root_file, tclsh_cmd)
	local index = M.build_workspace_symbol_index(root_file, tclsh_cmd)

	return {
		total_files = index.file_count,
		total_symbols = index.total_symbols,
		symbols_by_type = {},
		namespaces = vim.tbl_count(index.by_namespace),
		external_dependencies = vim.tbl_count(M.build_source_dependencies(root_file, tclsh_cmd)) - 1,
	}
end

return M
