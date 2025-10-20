#!/usr/bin/env tclsh
# tcl/core/ast/parsers/variables.tcl
# Variable Declaration Parsing Module

namespace eval ::ast::parsers::variables {
    namespace export parse_set parse_global parse_upvar parse_variable parse_array
}

# Parse a set command
proc ::ast::parsers::variables::parse_set {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid set: expected 'set varname value'" \
            range [::ast::utils::make_range $start_line 1 $end_line 1]]
    }

    set var_name [::tokenizer::get_token $cmd_text 1]
    set value [::tokenizer::get_token $cmd_text 2]

    return [dict create \
        type "set" \
        var_name $var_name \
        value $value \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse global command
proc ::ast::parsers::variables::parse_global {cmd_text start_line end_line depth} {
    set var_names [list]
    set word_count [::tokenizer::count_tokens $cmd_text]

    for {set i 1} {$i < $word_count} {incr i} {
        lappend var_names [::tokenizer::get_token $cmd_text $i]
    }

    return [dict create \
        type "global" \
        vars $var_names \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse upvar command
proc ::ast::parsers::variables::parse_upvar {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create type "error" message "Invalid upvar"]
    }

    set level [::tokenizer::get_token $cmd_text 1]
    set other_var [::tokenizer::get_token $cmd_text 2]
    set local_var [expr {$word_count >= 4 ? [::tokenizer::get_token $cmd_text 3] : $other_var}]

    return [dict create \
        type "upvar" \
        level $level \
        other_var $other_var \
        local_var $local_var \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse variable command
proc ::ast::parsers::variables::parse_variable {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    set var_name [::tokenizer::get_token $cmd_text 1]
    set value [expr {$word_count >= 3 ? [::tokenizer::get_token $cmd_text 2] : ""}]

    return [dict create \
        type "variable" \
        name $var_name \
        value $value \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse array set command
proc ::ast::parsers::variables::parse_array {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    set subcommand [::tokenizer::get_token $cmd_text 1]

    if {$subcommand eq "set" && $word_count >= 4} {
        set array_name [::tokenizer::get_token $cmd_text 2]
        set pairs [::tokenizer::get_token $cmd_text 3]

        return [dict create \
            type "array" \
            array_name $array_name \
            pairs $pairs \
            range [::ast::utils::make_range $start_line 1 $end_line 1] \
            depth $depth]
    }

    return [dict create \
        type "array" \
        subcommand $subcommand \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}
