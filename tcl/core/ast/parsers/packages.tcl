#!/usr/bin/env tclsh
# tcl/core/ast/parsers/packages.tcl
namespace eval ::ast::parsers {}

proc ::ast::parsers::parse_package {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 2} {
        return [dict create type "error" message "Invalid package syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set subcommand [::tokenizer::get_token $cmd_text 1]
    switch -exact -- $subcommand {
        "require" {
            if {$word_count < 3} {
                return [dict create type "error" message "Invalid package require syntax" \
                    range [::ast::utils::make_range $start_line 1 $end_line 50]]
            }
            set pkg_name [::tokenizer::get_token $cmd_text 2]
            set version ""
            if {$word_count >= 4} {
                set version [::tokenizer::get_token $cmd_text 3]
            }
            return [dict create type "package_require" package_name $pkg_name version $version \
                range [::ast::utils::make_range $start_line 1 $end_line 50]]
        }
        "provide" {
            if {$word_count < 4} {
                return [dict create type "error" message "Invalid package provide syntax" \
                    range [::ast::utils::make_range $start_line 1 $end_line 50]]
            }
            set pkg_name [::tokenizer::get_token $cmd_text 2]
            set version [::tokenizer::get_token $cmd_text 3]
            return [dict create type "package_provide" package $pkg_name version $version \
                range [::ast::utils::make_range $start_line 1 $end_line 50]]
        }
        default {
            return [dict create type "package" subcommand $subcommand \
                range [::ast::utils::make_range $start_line 1 $end_line 50]]
        }
    }
}
