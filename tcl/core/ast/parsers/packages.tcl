#!/usr/bin/env tclsh
# tcl/core/ast/parsers/packages.tcl
namespace eval ::ast::parsers::packages {
    namespace export parse_package parse_source
}
proc ::ast::parsers::packages::parse_package {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    set subcommand [::tokenizer::get_token $cmd_text 1]
    set package_name [expr {$word_count >= 3 ? [::tokenizer::get_token $cmd_text 2] : ""}]

    return [dict create \
        type "package" \
        subcommand $subcommand \
        package_name $package_name \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}
proc ::ast::parsers::packages::parse_source {cmd_text start_line end_line depth} {
    set filepath [::tokenizer::get_token $cmd_text 1]
    return [dict create \
        type "source" \
        filepath $filepath \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}
