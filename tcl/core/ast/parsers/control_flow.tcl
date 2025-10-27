#!/usr/bin/env tclsh
# tcl/core/ast/parsers/control_flow.tcl
# Control Flow Parsing Module (if, while, for, foreach, switch)
#
# PHASE 3 FIXES: All parsers now recursively parse body blocks
# This ensures bodies are AST nodes with children, not raw strings
#
# SWITCH FIX: Removed dependency on non-existent ::tokenizer::tokenize

namespace eval ::ast::parsers::control_flow {
    namespace export parse_if parse_while parse_for parse_foreach parse_switch
}

# Parse if statement
#
# FIXED: Recursively parses then_body, else_body, and elseif branches
#
proc ::ast::parsers::control_flow::parse_if {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create type "error" message "Invalid if"]
    }

    # Get condition (keep as string for now)
    set condition [::tokenizer::get_token $cmd_text 1]

    # Get then body and recursively parse it
    set then_body_token [::tokenizer::get_token $cmd_text 2]
    set then_body_text [::ast::delimiters::strip_outer $then_body_token]
    set then_children [::ast::find_all_nodes $then_body_text [expr {$start_line + 1}] [expr {$depth + 1}]]
    set then_body [dict create children $then_children]

    # Initialize result
    set result [dict create \
        type "if" \
        condition $condition \
        then_body $then_body \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]

    # Check for elseif/else branches
    set elseif_branches [list]
    set else_body [dict create children [list]]

    set i 3
    while {$i < $word_count} {
        set keyword [::tokenizer::get_token $cmd_text $i]

        if {$keyword eq "elseif"} {
            # Get elseif condition and body
            if {$i + 2 < $word_count} {
                set elseif_condition [::tokenizer::get_token $cmd_text [expr {$i + 1}]]
                set elseif_body_token [::tokenizer::get_token $cmd_text [expr {$i + 2}]]
                set elseif_body_text [::ast::delimiters::strip_outer $elseif_body_token]
                set elseif_children [::ast::find_all_nodes $elseif_body_text [expr {$start_line + 1}] [expr {$depth + 1}]]

                lappend elseif_branches [dict create \
                    condition $elseif_condition \
                    body [dict create children $elseif_children]]

                incr i 3
            } else {
                break
            }
        } elseif {$keyword eq "else"} {
            # Get else body
            if {$i + 1 < $word_count} {
                set else_body_token [::tokenizer::get_token $cmd_text [expr {$i + 1}]]
                set else_body_text [::ast::delimiters::strip_outer $else_body_token]
                set else_children [::ast::find_all_nodes $else_body_text [expr {$start_line + 1}] [expr {$depth + 1}]]
                set else_body [dict create children $else_children]
            }
            break
        } else {
            # Unknown keyword, stop parsing
            break
        }
    }

    # Add elseif branches if any exist
    if {[llength $elseif_branches] > 0} {
        dict set result elseif $elseif_branches
    }

    # Add else body if it has children
    if {[dict exists $else_body children] && [llength [dict get $else_body children]] > 0} {
        dict set result else_body $else_body
    }

    return $result
}

# Parse while loop
#
# FIXED: Recursively parses body
#
proc ::ast::parsers::control_flow::parse_while {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create type "error" message "Invalid while"]
    }

    # Get condition (keep as string)
    set condition [::tokenizer::get_token $cmd_text 1]

    # Get body and recursively parse it
    set body_token [::tokenizer::get_token $cmd_text 2]
    set body_text [::ast::delimiters::strip_outer $body_token]
    set body_children [::ast::find_all_nodes $body_text [expr {$start_line + 1}] [expr {$depth + 1}]]
    set body [dict create children $body_children]

    return [dict create \
        type "while" \
        condition $condition \
        body $body \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse for loop
#
# FIXED: Recursively parses body
#
proc ::ast::parsers::control_flow::parse_for {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 5} {
        return [dict create type "error" message "Invalid for"]
    }

    # Get init, condition, increment (keep as strings)
    set init [::tokenizer::get_token $cmd_text 1]
    set condition [::tokenizer::get_token $cmd_text 2]
    set increment [::tokenizer::get_token $cmd_text 3]

    # Get body and recursively parse it
    set body_token [::tokenizer::get_token $cmd_text 4]
    set body_text [::ast::delimiters::strip_outer $body_token]
    set body_children [::ast::find_all_nodes $body_text [expr {$start_line + 1}] [expr {$depth + 1}]]
    set body [dict create children $body_children]

    return [dict create \
        type "for" \
        init $init \
        condition $condition \
        increment $increment \
        body $body \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse foreach loop
#
# FIXED: Recursively parses body
#
proc ::ast::parsers::control_flow::parse_foreach {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 4} {
        return [dict create type "error" message "Invalid foreach"]
    }

    # Get var_name and list (keep as strings)
    set var_name [::tokenizer::get_token $cmd_text 1]
    set list_expr [::tokenizer::get_token $cmd_text 2]

    # Get body and recursively parse it
    set body_token [::tokenizer::get_token $cmd_text 3]
    set body_text [::ast::delimiters::strip_outer $body_token]
    set body_children [::ast::find_all_nodes $body_text [expr {$start_line + 1}] [expr {$depth + 1}]]
    set body [dict create children $body_children]

    return [dict create \
        type "foreach" \
        var_name $var_name \
        list $list_expr \
        body $body \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse switch statement
#
# FIXED: Now uses count_tokens/get_token instead of non-existent tokenize
# FIXED: Recursively parses case bodies
#
proc ::ast::parsers::control_flow::parse_switch {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create type "error" message "Invalid switch"]
    }

    # Check for options (-exact, -glob, -regexp, etc.)
    set option ""
    set expr_index 1
    set patterns_index 2

    set first_token [::tokenizer::get_token $cmd_text 1]
    if {[string match "-*" $first_token]} {
        set option $first_token
        set expr_index 2
        set patterns_index 3

        if {$word_count < 4} {
            return [dict create type "error" message "Invalid switch with option"]
        }
    }

    # Get expression (keep as string)
    set expression [::tokenizer::get_token $cmd_text $expr_index]

    # Get patterns/cases block
    set patterns_token [::tokenizer::get_token $cmd_text $patterns_index]
    set patterns_text [::ast::delimiters::strip_outer $patterns_token]

    # Parse switch cases (pattern-body pairs)
    set cases [list]

    # Count tokens in the patterns block
    set case_token_count [::tokenizer::count_tokens $patterns_text]

    # Process pattern-body pairs
    set i 0
    while {$i < [expr {$case_token_count - 1}]} {
        set pattern [::tokenizer::get_token $patterns_text $i]
        set body_token [::tokenizer::get_token $patterns_text [expr {$i + 1}]]

        # Recursively parse the case body
        set body_text [::ast::delimiters::strip_outer $body_token]
        set body_children [::ast::find_all_nodes $body_text [expr {$start_line + 1}] [expr {$depth + 1}]]

        lappend cases [dict create \
            pattern $pattern \
            body [dict create children $body_children]]

        incr i 2
    }

    # Build result dict
    set result [dict create \
        type "switch" \
        expression $expression \
        cases $cases \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]

    # Add option if present
    if {$option ne ""} {
        dict set result option $option
    }

    return $result
}
