#!/usr/bin/env tclsh
# tcl/core/ast/parsers/lists.tcl
namespace eval ::ast::parsers {}

proc ::ast::parsers::parse_list {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 2} {
        return [dict create type "error" message "Invalid list syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set elements [list]
    for {set i 1} {$i < $word_count} {incr i} {
        lappend elements [::tokenizer::get_token $cmd_text $i]
    }
    return [dict create type "list" elements $elements \
        range [::ast::utils::make_range $start_line 1 $end_line 50]]
}

proc ::ast::parsers::parse_lappend {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 3} {
        return [dict create type "error" message "Invalid lappend syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set var_name [::tokenizer::get_token $cmd_text 1]
    set value [::tokenizer::get_token $cmd_text 2]
    return [dict create type "lappend" name $var_name value $value \
        range [::ast::utils::make_range $start_line 1 $end_line 50]]
}

proc ::ast::parsers::parse_puts {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 2} {
        return [dict create type "error" message "Invalid puts syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set args [list]
    for {set i 1} {$i < $word_count} {incr i} {
        lappend args [::tokenizer::get_token $cmd_text $i]
    }
    return [dict create type "puts" args $args \
        range [::ast::utils::make_range $start_line 1 $end_line 50]]
}
