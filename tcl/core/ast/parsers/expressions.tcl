#!/usr/bin/env tclsh
# tcl/core/ast/parsers/expressions.tcl
namespace eval ::ast::parsers {}

proc ::ast::parsers::parse_expr {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 2} {
        return [dict create type "error" message "Invalid expr syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set expression [::tokenizer::get_token $cmd_text 1]
    return [dict create type "expr" expression $expression \
        range [::ast::utils::make_range $start_line 1 $end_line 50]]
}
