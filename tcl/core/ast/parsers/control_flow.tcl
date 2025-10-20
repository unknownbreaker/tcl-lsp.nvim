#!/usr/bin/env tclsh
# tcl/core/ast/parsers/control_flow.tcl
# Control Flow Parsing Module (if, while, for, foreach, switch)

namespace eval ::ast::parsers::control_flow {
    namespace export parse_if parse_while parse_for parse_foreach parse_switch
}

# Parse if statement
proc ::ast::parsers::control_flow::parse_if {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create type "error" message "Invalid if"]
    }

    set condition [::tokenizer::get_token $cmd_text 1]
    set then_body [::tokenizer::get_token $cmd_text 2]

    # Check for else/elseif
    set else_body ""
    if {$word_count >= 5} {
        set keyword [::tokenizer::get_token $cmd_text 3]
        if {$keyword eq "else"} {
            set else_body [::tokenizer::get_token $cmd_text 4]
        }
    }

    return [dict create \
        type "if" \
        condition $condition \
        then_body $then_body \
        else_body $else_body \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse while loop
proc ::ast::parsers::control_flow::parse_while {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create type "error" message "Invalid while"]
    }

    set condition [::tokenizer::get_token $cmd_text 1]
    set body [::tokenizer::get_token $cmd_text 2]

    return [dict create \
        type "while" \
        condition $condition \
        body $body \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse for loop
proc ::ast::parsers::control_flow::parse_for {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 5} {
        return [dict create type "error" message "Invalid for"]
    }

    set init [::tokenizer::get_token $cmd_text 1]
    set condition [::tokenizer::get_token $cmd_text 2]
    set increment [::tokenizer::get_token $cmd_text 3]
    set body [::tokenizer::get_token $cmd_text 4]

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
proc ::ast::parsers::control_flow::parse_foreach {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 4} {
        return [dict create type "error" message "Invalid foreach"]
    }

    set var_name [::tokenizer::get_token $cmd_text 1]
    set list_expr [::tokenizer::get_token $cmd_text 2]
    set body [::tokenizer::get_token $cmd_text 3]

    return [dict create \
        type "foreach" \
        var_name $var_name \
        list $list_expr \
        body $body \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse switch statement
proc ::ast::parsers::control_flow::parse_switch {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create type "error" message "Invalid switch"]
    }

    set expression [::tokenizer::get_token $cmd_text 1]
    set patterns [::tokenizer::get_token $cmd_text 2]

    return [dict create \
        type "switch" \
        expression $expression \
        patterns $patterns \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}
