#!/usr/bin/env tclsh
# tcl/core/ast/parsers/variables.tcl
# Variable Declaration and Assignment Parser

namespace eval ::ast::parsers {
    # Exports: parse_set, parse_variable, parse_global, parse_upvar, parse_array
}

proc ::ast::parsers::parse_set {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 2} {
        return [dict create type "error" message "Invalid set syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set var_name [::tokenizer::get_token $cmd_text 1]
    set value ""
    if {$word_count >= 3} {
        set value [::tokenizer::get_token $cmd_text 2]
    }
    return [dict create type "set" var_name $var_name value $value \
        range [::ast::utils::make_range $start_line 1 $end_line 50]]
}

proc ::ast::parsers::parse_variable {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 2} {
        return [dict create type "error" message "Invalid variable syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set var_name [::tokenizer::get_token $cmd_text 1]
    set value ""
    if {$word_count >= 3} {
        set value [::tokenizer::get_token $cmd_text 2]
    }
    return [dict create type "variable" name $var_name value $value \
        range [::ast::utils::make_range $start_line 1 $end_line 50]]
}

proc ::ast::parsers::parse_global {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 2} {
        return [dict create type "error" message "Invalid global syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set var_names [list]
    for {set i 1} {$i < $word_count} {incr i} {
        lappend var_names [::tokenizer::get_token $cmd_text $i]
    }
    return [dict create type "global" vars $var_names \
        range [::ast::utils::make_range $start_line 1 $end_line 50]]
}

proc ::ast::parsers::parse_upvar {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 3} {
        return [dict create type "error" message "Invalid upvar syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set level [::tokenizer::get_token $cmd_text 1]
    set other_var [::tokenizer::get_token $cmd_text 2]
    set local_var ""
    if {$word_count >= 4} {
        set local_var [::tokenizer::get_token $cmd_text 3]
    }
    return [dict create type "upvar" level $level other_var $other_var \
        local_var $local_var range [::ast::utils::make_range $start_line 1 $end_line 50]]
}

proc ::ast::parsers::parse_array {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 3} {
        return [dict create type "error" message "Invalid array syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set subcommand [::tokenizer::get_token $cmd_text 1]
    set array_name [::tokenizer::get_token $cmd_text 2]
    return [dict create type "array" subcommand $subcommand array_name $array_name \
        range [::ast::utils::make_range $start_line 1 $end_line 50]]
}
