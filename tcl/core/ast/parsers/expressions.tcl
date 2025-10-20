#!/usr/bin/env tclsh
# tcl/core/ast/parsers/expressions.tcl
namespace eval ::ast::parsers::expressions {
    namespace export parse_expr
}
proc ::ast::parsers::expressions::parse_expr {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    set expression [expr {$word_count >= 2 ? [::tokenizer::get_token $cmd_text 1] : ""}]

    return [dict create \
        type "expr" \
        expression $expression \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}
