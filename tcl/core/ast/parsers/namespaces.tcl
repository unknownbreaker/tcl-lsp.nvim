#!/usr/bin/env tclsh
# tcl/core/ast/parsers/namespaces.tcl
namespace eval ::ast::parsers::namespaces {
    namespace export parse_namespace
}
proc ::ast::parsers::namespaces::parse_namespace {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]
    set subcommand [::tokenizer::get_token $cmd_text 1]

    if {$subcommand eq "eval" && $word_count >= 4} {
        # namespace eval name {body}
        set ns_name [::tokenizer::get_token $cmd_text 2]
        set body_token [::tokenizer::get_token $cmd_text 3]
        set body_text [::ast::delimiters::strip_outer $body_token]

        # Recursively parse body for nested structures (procs, variables, etc.)
        set nested_nodes [::ast::find_all_nodes $body_text $start_line [expr {$depth + 1}]]
        set body [dict create children $nested_nodes]

        return [dict create \
            type "namespace_eval" \
            name $ns_name \
            body $body \
            range [::ast::utils::make_range $start_line 1 $end_line 1] \
            depth $depth]
    } elseif {$subcommand eq "import" && $word_count >= 3} {
        # namespace import pattern1 pattern2 ...
        set patterns [list]
        for {set i 2} {$i < $word_count} {incr i} {
            lappend patterns [::tokenizer::get_token $cmd_text $i]
        }

        return [dict create \
            type "namespace_import" \
            patterns $patterns \
            range [::ast::utils::make_range $start_line 1 $end_line 1] \
            depth $depth]
    } elseif {$subcommand eq "export" && $word_count >= 3} {
        # namespace export pattern1 pattern2 ...
        set exports [list]
        for {set i 2} {$i < $word_count} {incr i} {
            lappend exports [::tokenizer::get_token $cmd_text $i]
        }

        return [dict create \
            type "namespace_export" \
            exports $exports \
            range [::ast::utils::make_range $start_line 1 $end_line 1] \
            depth $depth]
    }

    # Generic namespace command
    return [dict create \
        type "namespace" \
        subcommand $subcommand \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}
