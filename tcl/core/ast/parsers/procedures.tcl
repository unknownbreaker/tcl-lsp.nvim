#!/usr/bin/env tclsh
# tcl/core/ast/parsers/procedures.tcl
# Procedure Definition Parser
#
# This module parses TCL proc definitions, extracting:
# - Procedure name
# - Parameters (with defaults and varargs)
# - Body (recursively parsed)

namespace eval ::ast::parsers {
    namespace export parse_proc
    variable debug 0
}

# Parse a proc (procedure) definition
#
# Syntax: proc name {args} {body}
#
# Handles:
# - Simple parameters: {arg1 arg2 arg3}
# - Default values: {arg1 {arg2 default} arg3}
# - Varargs: {arg1 args}
# - Nested body parsing
#
# Args:
#   cmd_text   - The command text
#   start_line - Starting line number
#   end_line   - Ending line number
#   depth      - Nesting depth (for recursive parsing)
#
# Returns:
#   AST node dict with type, name, params, body, range
#
proc ::ast::parsers::parse_proc {cmd_text start_line end_line depth} {
    variable debug

    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 4} {
        return [dict create \
            type "error" \
            message "Invalid proc syntax: expected 'proc name \{args\} \{body\}'" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }

    set proc_name [::tokenizer::get_token $cmd_text 1]
    set args_list_raw [::tokenizer::get_token $cmd_text 2]
    set body_raw [::tokenizer::get_token $cmd_text 3]

    # Remove surrounding braces from args and body
    # (they're part of the literal token from tokenizer)
    if {[string index $args_list_raw 0] eq "\{" && [string index $args_list_raw end] eq "\}"} {
        set args_list [string range $args_list_raw 1 end-1]
    } else {
        set args_list $args_list_raw
    }

    if {[string index $body_raw 0] eq "\{" && [string index $body_raw end] eq "\}"} {
        set body [string range $body_raw 1 end-1]
    } else {
        set body $body_raw
    }

    # Parse parameters - can be simple names or {name default} pairs
    set params [list]
    foreach arg $args_list {
        if {[llength $arg] == 2} {
            # Parameter with default value
            set param_name [lindex $arg 0]
            set param_default [lindex $arg 1]

            # Strip quotes from default if present
            if {[string index $param_default 0] eq "\"" && [string index $param_default end] eq "\""} {
                set param_default [string range $param_default 1 end-1]
            }

            lappend params [dict create \
                name $param_name \
                default $param_default]
        } elseif {[llength $arg] == 1} {
            # Simple parameter
            set param_dict [dict create name $arg]

            # Special handling for 'args' (varargs parameter)
            if {$arg eq "args"} {
                dict set param_dict is_varargs 1
            }

            lappend params $param_dict
        }
    }

    if {$debug} {
        puts "    Proc: $proc_name with [llength $params] parameters"
    }

    # Recursively parse the procedure body
    set body_start_line [expr {$start_line + 1}]
    set nested_nodes [::ast::find_all_nodes $body $body_start_line [expr {$depth + 1}]]

    set body_node [dict create children $nested_nodes]

    set proc_node [dict create \
        type "proc" \
        name $proc_name \
        params $params \
        body $body_node \
        range [::ast::utils::make_range $start_line 1 $end_line 50]]

    return $proc_node
}
