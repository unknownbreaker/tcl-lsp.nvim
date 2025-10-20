#!/usr/bin/env tclsh
# tcl/core/ast/parsers/procedures.tcl
# Procedure (proc) Parsing Module

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

    set proc_name [::tokenizer::get_token $cmd_text 1]
    set args_list [::tokenizer::get_token $cmd_text 2]
    set body [::tokenizer::get_token $cmd_text 3]

    # Parse parameters
    set params [list]
    foreach arg $args_list {
        if {[llength $arg] == 2} {
            # Parameter with default value
            lappend params [dict create \
                name [lindex $arg 0] \
                default [lindex $arg 1]]
        } else {
            # Simple parameter
            lappend params [dict create \
                name $arg \
                default ""]
        }
    }

    return [dict create \
        type "proc" \
        name $proc_name \
        parameters $params \
        body $body \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}
