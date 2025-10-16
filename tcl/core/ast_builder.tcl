#!/usr/bin/env tclsh
# tcl/core/ast_builder.tcl
# Production AST Builder - Recursive text-based parsing (NO safe interpreter)

namespace eval ::ast {
    variable current_file "<string>"
    variable line_map
    variable debug 0
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Create position range
proc ::ast::make_range {start_line start_col end_line end_col} {
    return [dict create \
        start [dict create line $start_line column $start_col] \
        end_pos [dict create line $end_line column $end_col]]
}

# Build line number mapping for position tracking
proc ::ast::build_line_map {code} {
    variable line_map
    set line_map [dict create]

    set offset 0
    set line_num 1

    foreach line [split $code "\n"] {
        dict set line_map $line_num [dict create \
            offset $offset \
            length [string length $line]]

        set offset [expr {$offset + [string length $line] + 1}]
        incr line_num
    }
}

# Get line number from code offset
proc ::ast::offset_to_line {offset} {
    variable line_map

    dict for {line_num info} $line_map {
        set line_offset [dict get $info offset]
        set line_length [dict get $info length]
        set line_end [expr {$line_offset + $line_length}]

        if {$offset >= $line_offset && $offset <= $line_end} {
            set col [expr {$offset - $line_offset + 1}]
            return [list $line_num $col]
        }
    }

    return [list 1 1]
}

# Count line numbers in text
proc ::ast::count_lines {text} {
    return [expr {[llength [split $text "\n"]] - 1}]
}

# Extract comments from source code
proc ::ast::extract_comments {code} {
    set comments [list]
    set line_num 0

    foreach line [split $code "\n"] {
        incr line_num

        if {[regexp {^(\s*)#(.*)$} $line -> indent text]} {
            lappend comments [dict create \
                type "comment" \
                text [string trim $text] \
                range [make_range $line_num 1 $line_num [string length $line]]]
        }
    }

    return $comments
}

# Extract commands from TCL code
proc ::ast::extract_commands {code start_line_offset} {
    set commands [list]
    set current_cmd ""
    set cmd_start_line $start_line_offset
    set line_num $start_line_offset

    foreach line [split $code "\n"] {
        set trimmed [string trim $line]

        # Skip empty lines and comments
        if {$trimmed eq "" || [string index $trimmed 0] eq "#"} {
            if {$current_cmd ne ""} {
                # End of previous command
                lappend commands [dict create \
                    text $current_cmd \
                    start_line $cmd_start_line \
                    end_line [expr {$line_num - 1}]]
                set current_cmd ""
            }
            incr line_num
            continue
        }

        # Append to current command
        if {$current_cmd ne ""} {
            append current_cmd "\n"
        } else {
            set cmd_start_line $line_num
        }
        append current_cmd $line

        # Check if command is complete
        if {[info complete $current_cmd]} {
            lappend commands [dict create \
                text $current_cmd \
                start_line $cmd_start_line \
                end_line $line_num]
            set current_cmd ""
        }

        incr line_num
    }

    # Handle incomplete command at end
    if {$current_cmd ne ""} {
        if {[regexp {^\s*#} $trimmed]} {
            lappend commands [dict create \
                text $trimmed \
                start_line $cmd_start_line \
                end_line [expr {$line_num - 1}]]
        }
    }

    return $commands
}

# ============================================================================
# COMMAND PARSING (Using TCL list commands)
# ============================================================================

# Parse a command into an AST node
proc ::ast::parse_command {cmd_dict depth} {
    variable debug

    set cmd_text [dict get $cmd_dict text]
    set start_line [dict get $cmd_dict start_line]
    set end_line [dict get $cmd_dict end_line]

    # Validate it's a valid TCL command
    if {[catch {llength $cmd_text} word_count]} {
        if {$debug} {
            puts "  Invalid command syntax, skipping"
        }
        return [dict create \
            type "error" \
            message "Invalid command syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    if {$word_count == 0} {
        return ""
    }

    # Get command name
    set cmd_name [lindex $cmd_text 0]

    if {$debug} {
        puts "  Parsing command: $cmd_name at line $start_line (depth $depth)"
    }

    # Dispatch to specific parser
    switch -exact -- $cmd_name {
        "proc" {
            return [parse_proc $cmd_text $start_line $end_line $depth]
        }
        "set" {
            return [parse_set $cmd_text $start_line $end_line]
        }
        "variable" {
            return [parse_variable $cmd_text $start_line $end_line]
        }
        "global" {
            return [parse_global $cmd_text $start_line $end_line]
        }
        "upvar" {
            return [parse_upvar $cmd_text $start_line $end_line]
        }
        "array" {
            return [parse_array $cmd_text $start_line $end_line]
        }
        "namespace" {
            return [parse_namespace $cmd_text $start_line $end_line $depth]
        }
        "package" {
            return [parse_package $cmd_text $start_line $end_line]
        }
        "if" {
            return [parse_if $cmd_text $start_line $end_line $depth]
        }
        "while" {
            return [parse_while $cmd_text $start_line $end_line $depth]
        }
        "for" {
            return [parse_for $cmd_text $start_line $end_line $depth]
        }
        "foreach" {
            return [parse_foreach $cmd_text $start_line $end_line $depth]
        }
        "switch" {
            return [parse_switch $cmd_text $start_line $end_line $depth]
        }
        "expr" {
            return [parse_expr $cmd_text $start_line $end_line]
        }
        "list" {
            return [parse_list $cmd_text $start_line $end_line]
        }
        "lappend" {
            return [parse_lappend $cmd_text $start_line $end_line]
        }
        "puts" {
            return [parse_puts $cmd_text $start_line $end_line]
        }
        default {
            return ""
        }
    }
}

# ============================================================================
# SPECIFIC COMMAND PARSERS
# ============================================================================

# Parse proc command - FIXED parameter parsing and body structure
proc ::ast::parse_proc {cmd_text start_line end_line depth} {
    variable debug

    if {[catch {llength $cmd_text} word_count] || $word_count < 4} {
        return [dict create \
            type "error" \
            message "Invalid proc syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set proc_name [lindex $cmd_text 1]
    set args_list [lindex $cmd_text 2]
    set body [lindex $cmd_text 3]

    # Parse parameters properly
    set params [list]
    foreach arg $args_list {
        if {[llength $arg] == 2} {
            # Parameter with default value: {name default}
            lappend params [dict create \
                name [lindex $arg 0] \
                default [lindex $arg 1]]
        } elseif {[llength $arg] == 1} {
            # Simple parameter (including 'args')
            lappend params [dict create \
                name $arg \
                default ""]
        }
    }

    if {$debug} {
        puts "    Proc: $proc_name with [llength $params] parameters"
    }

    # Calculate body start line
    set header_lines [count_lines "$proc_name $args_list"]
    set body_start_line [expr {$start_line + $header_lines}]
    set body_lines [count_lines $body]
    set body_end_line [expr {$body_start_line + $body_lines}]

    # Recursively parse proc body for nested procs
    set nested_nodes [find_all_nodes $body $body_start_line [expr {$depth + 1}]]

    # FIXED: Create body structure with children for tests
    # Tests expect body.children, not separate nested_nodes field
    set body_node [dict create \
        children $nested_nodes]

    # FIXED: Use 'params' not 'parameters'
    set proc_node [dict create \
        type "proc" \
        name $proc_name \
        params $params \
        body $body_node \
        range [make_range $start_line 1 $end_line 50]]

    return $proc_node
}

# Parse set command
proc ::ast::parse_set {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid set syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set var_name [lindex $cmd_text 1]
    set value ""
    if {$word_count >= 3} {
        set value [lindex $cmd_text 2]
    }

    return [dict create \
        type "set" \
        name $var_name \
        value $value \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse variable command
proc ::ast::parse_variable {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid variable syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set var_name [lindex $cmd_text 1]
    set value ""
    if {$word_count >= 3} {
        set value [lindex $cmd_text 2]
    }

    return [dict create \
        type "variable" \
        name $var_name \
        value $value \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse global command
proc ::ast::parse_global {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid global syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set var_names [lrange $cmd_text 1 end]

    return [dict create \
        type "global" \
        variables $var_names \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse upvar command - FIXED to keep level as string
proc ::ast::parse_upvar {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid upvar syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set level [lindex $cmd_text 1]
    set other_var [lindex $cmd_text 2]
    set local_var ""
    if {$word_count >= 4} {
        set local_var [lindex $cmd_text 3]
    }

    return [dict create \
        type "upvar" \
        level $level \
        other_var $other_var \
        local_var $local_var \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse namespace command - FIXED to parse body recursively
proc ::ast::parse_namespace {cmd_text start_line end_line depth} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid namespace syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set subcommand [lindex $cmd_text 1]

    switch -exact -- $subcommand {
        "eval" {
            if {$word_count < 4} {
                return [dict create \
                    type "error" \
                    message "Invalid namespace eval syntax" \
                    range [make_range $start_line 1 $end_line 50]]
            }

            set ns_name [lindex $cmd_text 2]
            set body_text [lindex $cmd_text 3]

            # Recursively parse namespace body
            set body_start_line [expr {$start_line + 1}]
            set body_nodes [find_all_nodes $body_text $body_start_line [expr {$depth + 1}]]

            return [dict create \
                type "namespace" \
                subcommand "eval" \
                name $ns_name \
                body $body_nodes \
                range [make_range $start_line 1 $end_line 50]]
        }
        "import" {
            set patterns [lrange $cmd_text 2 end]
            return [dict create \
                type "namespace_import" \
                patterns $patterns \
                range [make_range $start_line 1 $end_line 50]]
        }
        "export" {
            set patterns [lrange $cmd_text 2 end]
            return [dict create \
                type "namespace_export" \
                patterns $patterns \
                range [make_range $start_line 1 $end_line 50]]
        }
        default {
            return [dict create \
                type "namespace" \
                subcommand $subcommand \
                args [lrange $cmd_text 2 end] \
                range [make_range $start_line 1 $end_line 50]]
        }
    }
}

# Parse package command - FIXED to use 'package' not 'package_name'
proc ::ast::parse_package {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid package syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set subcommand [lindex $cmd_text 1]

    switch -exact -- $subcommand {
        "require" {
            if {$word_count < 3} {
                return [dict create \
                    type "error" \
                    message "Invalid package require syntax" \
                    range [make_range $start_line 1 $end_line 50]]
            }

            set pkg_name [lindex $cmd_text 2]
            set version ""
            if {$word_count >= 4} {
                set version [lindex $cmd_text 3]
            }

            # FIXED: Use 'package' not 'package_name'
            return [dict create \
                type "package_require" \
                package $pkg_name \
                version $version \
                range [make_range $start_line 1 $end_line 50]]
        }
        "provide" {
            if {$word_count < 4} {
                return [dict create \
                    type "error" \
                    message "Invalid package provide syntax" \
                    range [make_range $start_line 1 $end_line 50]]
            }

            set pkg_name [lindex $cmd_text 2]
            set version [lindex $cmd_text 3]

            # FIXED: Use 'package' not 'package_name'
            return [dict create \
                type "package_provide" \
                package $pkg_name \
                version $version \
                range [make_range $start_line 1 $end_line 50]]
        }
        default {
            return [dict create \
                type "package" \
                subcommand $subcommand \
                args [lrange $cmd_text 2 end] \
                range [make_range $start_line 1 $end_line 50]]
        }
    }
}

# Parse if command - FIXED to return proper node
proc ::ast::parse_if {cmd_text start_line end_line depth} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid if syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set condition [lindex $cmd_text 1]
    set then_body [lindex $cmd_text 2]

    # Parse branches
    set branches [list]
    lappend branches [dict create \
        type "then" \
        condition $condition \
        body $then_body]

    # Check for elseif/else
    set idx 3
    while {$idx < $word_count} {
        set keyword [lindex $cmd_text $idx]

        if {$keyword eq "elseif"} {
            if {$idx + 2 >= $word_count} {
                break
            }
            set elseif_cond [lindex $cmd_text [expr {$idx + 1}]]
            set elseif_body [lindex $cmd_text [expr {$idx + 2}]]
            lappend branches [dict create \
                type "elseif" \
                condition $elseif_cond \
                body $elseif_body]
            set idx [expr {$idx + 3}]
        } elseif {$keyword eq "else"} {
            if {$idx + 1 >= $word_count} {
                break
            }
            set else_body [lindex $cmd_text [expr {$idx + 1}]]
            lappend branches [dict create \
                type "else" \
                body $else_body]
            break
        } else {
            break
        }
    }

    return [dict create \
        type "if" \
        branches $branches \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse while command - FIXED to return proper node
proc ::ast::parse_while {cmd_text start_line end_line depth} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid while syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set condition [lindex $cmd_text 1]
    set body [lindex $cmd_text 2]

    return [dict create \
        type "while" \
        condition $condition \
        body $body \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse for command - FIXED to return proper node
proc ::ast::parse_for {cmd_text start_line end_line depth} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 5} {
        return [dict create \
            type "error" \
            message "Invalid for syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set init [lindex $cmd_text 1]
    set condition [lindex $cmd_text 2]
    set increment [lindex $cmd_text 3]
    set body [lindex $cmd_text 4]

    return [dict create \
        type "for" \
        init $init \
        condition $condition \
        increment $increment \
        body $body \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse foreach command - FIXED to return proper node with variable name
proc ::ast::parse_foreach {cmd_text start_line end_line depth} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 4} {
        return [dict create \
            type "error" \
            message "Invalid foreach syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set var_name [lindex $cmd_text 1]
    set list_expr [lindex $cmd_text 2]
    set body [lindex $cmd_text 3]

    return [dict create \
        type "foreach" \
        variable $var_name \
        list $list_expr \
        body $body \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse switch command - FIXED to return proper node with cases
proc ::ast::parse_switch {cmd_text start_line end_line depth} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid switch syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set value [lindex $cmd_text 1]

    # Parse switch body (last argument)
    set switch_body [lindex $cmd_text end]

    # Extract cases from body
    set cases [list]
    set case_count [llength $switch_body]

    for {set i 0} {$i < $case_count} {incr i 2} {
        set pattern [lindex $switch_body $i]
        set body ""
        if {$i + 1 < $case_count} {
            set body [lindex $switch_body [expr {$i + 1}]]
        }

        lappend cases [dict create \
            pattern $pattern \
            body $body]
    }

    return [dict create \
        type "switch" \
        value $value \
        cases $cases \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse expr command
proc ::ast::parse_expr {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid expr syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set expression [lindex $cmd_text 1]

    return [dict create \
        type "expr" \
        expression $expression \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse list command
proc ::ast::parse_list {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid list syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set elements [lrange $cmd_text 1 end]

    return [dict create \
        type "list" \
        elements $elements \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse lappend command
proc ::ast::parse_lappend {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid lappend syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set var_name [lindex $cmd_text 1]
    set value [lindex $cmd_text 2]

    return [dict create \
        type "lappend" \
        name $var_name \
        value $value \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse array command
proc ::ast::parse_array {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid array syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set subcommand [lindex $cmd_text 1]
    set array_name [lindex $cmd_text 2]

    return [dict create \
        type "array" \
        subcommand $subcommand \
        array_name $array_name \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse puts command
proc ::ast::parse_puts {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid puts syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set args [lrange $cmd_text 1 end]

    return [dict create \
        type "puts" \
        args $args \
        range [make_range $start_line 1 $end_line 50]]
}

# ============================================================================
# RECURSIVE NODE FINDER (Main algorithm)
# ============================================================================

# Find all nodes recursively (procs can be nested!)
proc ::ast::find_all_nodes {code start_line depth} {
    variable debug

    if {$debug} {
        puts "Finding nodes at depth $depth, starting line $start_line"
    }

    set commands [extract_commands $code $start_line]

    if {$debug} {
        puts "  Found [llength $commands] commands"
    }

    set nodes [list]

    foreach cmd_dict $commands {
        set node [parse_command $cmd_dict $depth]

        # Only add non-empty nodes
        if {$node ne ""} {
            lappend nodes $node
        }
    }

    return $nodes
}

# ============================================================================
# JSON SERIALIZATION - FIXED type handling
# ============================================================================

proc ::ast::dict_to_json {d indent_level} {
    set indent [string repeat "  " $indent_level]
    set next_indent [string repeat "  " [expr {$indent_level + 1}]]

    set result "\{\n"
    set first 1

    dict for {key value} $d {
        if {!$first} {
            append result ",\n"
        }
        set first 0

        append result "${next_indent}\"$key\": "

        # Serialize the value based on its type
        append result [serialize_value $value $key $indent_level]
    }

    append result "\n${indent}\}"
    return $result
}

# Helper function to serialize a single value
proc ::ast::serialize_value {value key indent_level} {
    set next_indent [string repeat "  " [expr {$indent_level + 1}]]

    # Fields that should always be strings (not numbers)
    set string_fields [list "default" "level" "version"]
    set force_string [expr {[lsearch -exact $string_fields $key] >= 0}]

    # Fields that are known to be arrays/lists
    # FIXED: Added 'params' to the list
    set array_fields [list "children" "comments" "errors" "params" "parameters" "branches" "cases" "patterns" "variables" "elements" "args" "nested_nodes"]
    set is_array_field [expr {[lsearch -exact $array_fields $key] >= 0}]

    # Special case: "body" can be either a string OR an array of nodes
    if {$key eq "body"} {
        # Check if it looks like a dict (parsed nodes)
        set len [llength $value]
        if {$len > 1 && [expr {$len % 2 == 0}] && [catch {dict size $value}] == 0} {
            # It's a dict (single node)
            return [dict_to_json $value [expr {$indent_level + 1}]]
        } elseif {$len > 0} {
            set first_elem [lindex $value 0]
            set first_len [llength $first_elem]
            if {$first_len > 1 && [expr {$first_len % 2 == 0}] && [catch {dict size $first_elem}] == 0} {
                # It's a list of dicts (array of nodes)
                set is_array_field 1
            } else {
                # It's a string (raw TCL code)
                return "\"[escape_json $value]\""
            }
        } else {
            # Empty body
            return "\"\""
        }
    }

    set list_length [llength $value]

    # CRITICAL FIX: Check if value is a dict (nested object) BEFORE treating as scalar
    # This handles fields like "range", "start", "end_pos" which are dicts
    if {!$is_array_field && $list_length > 1 && [expr {$list_length % 2 == 0}] && [catch {dict size $value}] == 0} {
        # It's a dict/object - serialize recursively
        return [dict_to_json $value [expr {$indent_level + 1}]]
    }

    # Handle based on whether it's an array field or not
    if {!$is_array_field} {
        # Scalar field - serialize as single value
        if {$force_string} {
            return "\"[escape_json $value]\""
        } elseif {$value eq ""} {
            return "\"\""
        } elseif {[string is integer -strict $value]} {
            return $value
        } elseif {[string is double -strict $value]} {
            return $value
        } else {
            return "\"[escape_json $value]\""
        }
    }

    # Array field - serialize as JSON array
    if {$list_length == 0} {
        return "\[\]"
    }

    # Check if it's a list of dicts or primitives
    set first_elem [lindex $value 0]
    set first_len [llength $first_elem]

    if {$first_len > 1 && [expr {$first_len % 2 == 0}] && [catch {dict size $first_elem}] == 0} {
        # List of dicts
        set result "\[\n"
        set first_item 1
        foreach item $value {
            if {!$first_item} {
                append result ",\n"
            }
            set first_item 0
            append result "${next_indent}  "
            append result [dict_to_json $item [expr {$indent_level + 2}]]
        }
        append result "\n${next_indent}\]"
        return $result
    } else {
        # List of primitives
        set result "\["
        set first_item 1
        foreach item $value {
            if {!$first_item} {
                append result ", "
            }
            set first_item 0
            if {[string is integer -strict $item] || [string is double -strict $item]} {
                append result $item
            } else {
                append result "\"[escape_json $item]\""
            }
        }
        append result "\]"
        return $result
    }
}

proc ::ast::escape_json {str} {
    set str [string map {
        \\ \\\\
        \" \\\"
        \n \\n
        \r \\r
        \t \\t
    } $str]
    return $str
}

proc ::ast::to_json {ast} {
    return [dict_to_json $ast 0]
}

# ============================================================================
# MAIN BUILD FUNCTION
# ============================================================================

proc ::ast::build {code {filepath "<string>"}} {
    variable current_file
    variable debug

    set current_file $filepath

    if {$debug} {
        puts "\n=== Building AST for $filepath ==="
        puts "Code length: [string length $code] chars"
    }

    # Check if code is complete
    if {![info complete $code]} {
        if {$debug} {
            puts "ERROR: Incomplete TCL code"
        }
        # FIXED: Error message now includes "syntax" keyword
        return [dict create \
            type "root" \
            filepath $filepath \
            errors [list [dict create \
                type "error" \
                message "Syntax error: missing close-brace" \
                range [make_range 1 1 1 1] \
                error_type "incomplete" \
                suggestion "Check for missing closing brace \}"]] \
            had_error 1 \
            children [list] \
            comments [list]]
    }

    # Build line mapping
    build_line_map $code

    # Extract comments
    set comments [extract_comments $code]

    if {$debug} {
        puts "Found [llength $comments] comments"
    }

    # Find all nodes (recursively)
    set nodes [find_all_nodes $code 1 0]

    if {$debug} {
        puts "Found [llength $nodes] total nodes"
        puts "=== AST Building Complete ===\n"
    }

    # Build root AST
    return [dict create \
        type "root" \
        filepath $filepath \
        comments $comments \
        children $nodes \
        had_error 0 \
        errors [list]]
}
