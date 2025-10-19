#!/usr/bin/env tclsh
# tcl/core/ast/parsers/namespaces.tcl
namespace eval ::ast::parsers {}

proc ::ast::parsers::parse_namespace {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 2} {
        return [dict create type "error" message "Invalid namespace syntax" \
            range [::ast::utils::make_range $start_line 1 $end_line 50]]
    }
    set subcommand [::tokenizer::get_token $cmd_text 1]
    switch -exact -- $subcommand {
        "eval" {
            if {$word_count < 4} {
                return [dict create type "error" message "Invalid namespace eval syntax" \
                    range [::ast::utils::make_range $start_line 1 $end_line 50]]
            }
            set ns_name [::tokenizer::get_token $cmd_text 2]
            set body_raw [::tokenizer::get_token $cmd_text 3]
            if {[string index $body_raw 0] eq "\{" && [string index $body_raw end] eq "\}"} {
                set body_text [string range $body_raw 1 end-1]
            } else {
                set body_text $body_raw
            }
            set body_start_line [expr {$start_line + 1}]
            set body_nodes [::ast::find_all_nodes $body_text $body_start_line [expr {$depth + 1}]]
            return [dict create type "namespace" subcommand "eval" name $ns_name \
                body $body_nodes range [::ast::utils::make_range $start_line 1 $end_line 50]]
        }
        "import" - "export" {
            set patterns [list]
            for {set i 2} {$i < $word_count} {incr i} {
                lappend patterns [::tokenizer::get_token $cmd_text $i]
            }
            set type_name "namespace_${subcommand}"
            return [dict create type $type_name patterns $patterns \
                range [::ast::utils::make_range $start_line 1 $end_line 50]]
        }
        default {
            return [dict create type "namespace" subcommand $subcommand \
                range [::ast::utils::make_range $start_line 1 $end_line 50]]
        }
    }
}
