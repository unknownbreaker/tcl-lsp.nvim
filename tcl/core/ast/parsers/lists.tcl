#!/usr/bin/env tclsh
# tcl/core/ast/parsers/lists.tcl
# List Operations Parsing Module
#
# UPDATED: Ensures puts command always returns args field

namespace eval ::ast::parsers::lists {
    namespace export parse_list parse_lappend parse_puts
}

# Parse a list command
#
# Syntax: list element1 [element2 ...]
#
# Args:
#   cmd_text   - The list command text
#   start_line - Starting line number
#   end_line   - Ending line number
#   depth      - Nesting depth
#
# Returns:
#   AST node dict for the list
#
proc ::ast::parsers::lists::parse_list {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    # Collect all elements
    set elements [list]
    for {set i 1} {$i < $word_count} {incr i} {
        set elem_token [::tokenizer::get_token $cmd_text $i]
        set elem [::ast::delimiters::normalize $elem_token]
        lappend elements $elem
    }

    return [dict create \
        type "list" \
        elements $elements \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse an lappend command
#
# Syntax: lappend varname value [value2 ...]
#
# Args:
#   cmd_text   - The lappend command text
#   start_line - Starting line number
#   end_line   - Ending line number
#   depth      - Nesting depth
#
# Returns:
#   AST node dict for the lappend
#
proc ::ast::parsers::lists::parse_lappend {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid lappend: expected 'lappend varname value [...]'" \
            range [::ast::utils::make_range $start_line 1 $end_line 1]]
    }

    set var_name_token [::tokenizer::get_token $cmd_text 1]
    set var_name [::ast::delimiters::strip_outer $var_name_token]

    set value_token [::tokenizer::get_token $cmd_text 2]
    set value [::ast::delimiters::normalize $value_token]

    return [dict create \
        type "lappend" \
        var_name $var_name \
        value $value \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse a puts command
#
# Syntax: puts [options] string
#
# ✅ FIX: Always returns args field as array
#
# Args:
#   cmd_text   - The puts command text
#   start_line - Starting line number
#   end_line   - Ending line number
#   depth      - Nesting depth
#
# Returns:
#   AST node dict for the puts command
#
proc ::ast::parsers::lists::parse_puts {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid puts: expected 'puts [options] string'" \
            range [::ast::utils::make_range $start_line 1 $end_line 1]]
    }

    # ✅ FIX: Collect all arguments as array (always present)
    set args [list]
    for {set i 1} {$i < $word_count} {incr i} {
        set arg_token [::tokenizer::get_token $cmd_text $i]
        set arg [::ast::delimiters::normalize $arg_token]
        lappend args $arg
    }

    return [dict create \
        type "puts" \
        args $args \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}
