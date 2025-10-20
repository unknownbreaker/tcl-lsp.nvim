#!/usr/bin/env tclsh
# tcl/core/ast/parsers/namespaces.tcl
namespace eval ::ast::parsers::namespaces {
    namespace export parse_namespace
}
proc ::ast::parsers::namespaces::parse_namespace {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    set subcommand [::tokenizer::get_token $cmd_text 1]

    return [dict create \
        type "namespace" \
        subcommand $subcommand \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}
