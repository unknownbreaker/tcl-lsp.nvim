#!/usr/bin/env tclsh
# tcl/core/ast/parsers/lists.tcl
namespace eval ::ast::parsers::lists {
    namespace export parse_list parse_lappend
}
proc ::ast::parsers::lists::parse_list {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    set elements [list]
    for {set i 1} {$i < $word_count} {incr i} {
        lappend elements [::tokenizer::get_token $cmd_text $i]
    }

    return [dict create \
        type "list" \
        elements $elements \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}
proc ::ast::parsers::lists::parse_lappend {cmd_text start_line end_line depth} {
    set var_name [::tokenizer::get_token $cmd_text 1]
    set value [::tokenizer::get_token $cmd_text 2]

    return [dict create \
        type "lappend" \
        var_name $var_name \
        value $value \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}
