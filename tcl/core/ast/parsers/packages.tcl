#!/usr/bin/env tclsh
# tcl/core/ast/parsers/packages.tcl
namespace eval ::ast::parsers::packages {
    namespace export parse_package parse_source
}
proc ::ast::parsers::packages::parse_package {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    set subcommand [::tokenizer::get_token $cmd_text 1]
    set package_name [expr {$word_count >= 3 ? [::tokenizer::get_token $cmd_text 2] : ""}]
    set version [expr {$word_count >= 4 ? [::tokenizer::get_token $cmd_text 3] : ""}]

    # Determine type based on subcommand
    set node_type "package"
    if {$subcommand eq "require"} {
        set node_type "package_require"
    } elseif {$subcommand eq "provide"} {
        set node_type "package_provide"
    }

    return [dict create \
        type $node_type \
        package_name $package_name \
        version $version \
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
