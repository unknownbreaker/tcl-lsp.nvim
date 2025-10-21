#!/usr/bin/env tclsh
# tcl/core/ast/parsers/procedures.tcl
# Procedure (proc) Parsing Module
#
# UPDATED: Uses delimiter helper and fixes:
# - Empty params returns [] instead of ""
# - is_varargs returns boolean true instead of number 1
# - Default values are strings not numbers

namespace eval ::ast::parsers::procedures {
    namespace export parse_proc
}

# Parse a proc command into an AST node
#
# Handles: proc name {args} {body}
#
# Args:
#   cmd_text   - The proc command text
#   start_line - Starting line number
#   end_line   - Ending line number
#   depth      - Nesting depth
#
# Returns:
#   AST node dict for the procedure
#
proc ::ast::parsers::procedures::parse_proc {cmd_text start_line end_line depth} {
    # Use tokenizer to safely extract parts
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 4} {
        return [dict create \
            type "error" \
            message "Invalid proc: expected 'proc name args body'" \
            range [::ast::utils::make_range $start_line 1 $end_line 1]]
    }

    set proc_name_token [::tokenizer::get_token $cmd_text 1]
    set proc_name [::ast::delimiters::strip_outer $proc_name_token]

    set args_list_token [::tokenizer::get_token $cmd_text 2]
    set args_list [::ast::delimiters::strip_outer $args_list_token]

    set body_token [::tokenizer::get_token $cmd_text 3]
    set body [::ast::delimiters::strip_outer $body_token]

    # ⭐ FIX: Initialize params as EMPTY LIST not empty string
    set params [list]

    # Only process if we actually have parameters
    if {[string trim $args_list] ne ""} {
        # Parse parameter list - handle both "x y z" and "{x 10} y {z 20}"
        foreach arg $args_list {
            if {[llength $arg] == 2} {
                # Parameter with default value: {name default}
                set param_name [lindex $arg 0]
                set param_default [lindex $arg 1]

                # ⭐ FIX: Keep default as STRING not number
                # Strip quotes if present but keep it as string
                if {[string index $param_default 0] eq "\"" && [string index $param_default end] eq "\""} {
                    set param_default [string range $param_default 1 end-1]
                }

                # ⭐ FIX: Force to stay as string even if it looks like a number
                # This prevents TCL from converting "10" to integer 10
                set param_default "$param_default"

                lappend params [dict create \
                    name $param_name \
                    default $param_default]
            } elseif {[llength $arg] == 1} {
                # Simple parameter
                set param_dict [dict create name $arg]

                # ⭐ FIX: is_varargs should be BOOLEAN true not number 1
                if {$arg eq "args"} {
                    dict set param_dict is_varargs true
                }

                lappend params $param_dict
            }
        }
    }
    # If args_list was empty or whitespace, params is already [] from initialization

    # Recursively parse the procedure body for nested structures
    set body_start_line [expr {$start_line + 1}]
    set nested_nodes [::ast::find_all_nodes $body $body_start_line [expr {$depth + 1}]]

    set body_node [dict create children $nested_nodes]

    # Build the procedure node
    return [dict create \
        type "proc" \
        name $proc_name \
        params $params \
        body $body_node \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}
