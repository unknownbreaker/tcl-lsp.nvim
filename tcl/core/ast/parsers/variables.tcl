#!/usr/bin/env tclsh
# tcl/core/ast/parsers/variables.tcl
# Variable Declaration Parsing Module
#
# UPDATED: Type conversion fixes for test compatibility
# - Values stay as strings not numbers
# - Global vars returns array of strings
# - Level in upvar stays as string

namespace eval ::ast::parsers::variables {
    namespace export parse_set parse_variable parse_global parse_upvar parse_array
}

# Parse a set command (variable assignment)
#
# Syntax: set varname [value]
#
# Args:
#   cmd_text   - The set command text
#   start_line - Starting line number
#   end_line   - Ending line number
#   depth      - Nesting depth
#
# Returns:
#   AST node dict for the variable assignment
#
proc ::ast::parsers::variables::parse_set {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid set: expected 'set varname [value]'" \
            range [::ast::utils::make_range $start_line 1 $end_line 1]]
    }

    # Extract variable name and strip delimiters
    set var_name_token [::tokenizer::get_token $cmd_text 1]
    set var_name [::ast::delimiters::strip_outer $var_name_token]

    # Extract value if present
    set value ""
    if {$word_count >= 3} {
        set value_token [::tokenizer::get_token $cmd_text 2]

        # Check if this is a command substitution
        if {[::ast::delimiters::is_bracketed $value_token]} {
            # Command substitution - needs recursive parsing
            set value [dict create \
                type "command_substitution" \
                command [::ast::delimiters::extract_command $value_token]]
        } else {
            # Simple value - normalize (strip delimiters)
            set value_normalized [::ast::delimiters::normalize $value_token]
            # ✅ FIX: Force to stay as STRING
            set value [format "%s" $value_normalized]
        }
    }

    return [dict create \
        type "set" \
        var_name $var_name \
        value $value \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse a variable declaration
#
# Syntax: variable name [value]
#
# Args:
#   cmd_text   - The variable command text
#   start_line - Starting line number
#   end_line   - Ending line number
#   depth      - Nesting depth
#
# Returns:
#   AST node dict for the variable declaration
#
proc ::ast::parsers::variables::parse_variable {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid variable: expected 'variable name [value]'" \
            range [::ast::utils::make_range $start_line 1 $end_line 1]]
    }

    set var_name_token [::tokenizer::get_token $cmd_text 1]
    set var_name [::ast::delimiters::strip_outer $var_name_token]

    # Extract value if present
    set value ""
    if {$word_count >= 3} {
        set value_token [::tokenizer::get_token $cmd_text 2]
        set value_normalized [::ast::delimiters::normalize $value_token]
        # ✅ FIX: Force to stay as STRING
        set value [format "%s" $value_normalized]
    }

    return [dict create \
        type "variable" \
        name $var_name \
        value $value \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse a global variable declaration
#
# Syntax: global var1 [var2 ...]
#
# ✅ FIX: Returns vars as array of strings (not single string)
#
# Args:
#   cmd_text   - The global command text
#   start_line - Starting line number
#   end_line   - Ending line number
#   depth      - Nesting depth
#
# Returns:
#   AST node dict with vars as array of variable names
#
proc ::ast::parsers::variables::parse_global {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid global: expected 'global var1 [var2 ...]'" \
            range [::ast::utils::make_range $start_line 1 $end_line 1]]
    }

    # ✅ FIX: Collect ALL variable names as array
    set vars [list]
    for {set i 1} {$i < $word_count} {incr i} {
        set var_token [::tokenizer::get_token $cmd_text $i]
        set var_name [::ast::delimiters::strip_outer $var_token]
        lappend vars $var_name
    }

    return [dict create \
        type "global" \
        vars $vars \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse an upvar declaration
#
# Syntax: upvar level otherVar myVar
#
# ✅ FIX: Level stays as string representation
#
# Args:
#   cmd_text   - The upvar command text
#   start_line - Starting line number
#   end_line   - Ending line number
#   depth      - Nesting depth
#
# Returns:
#   AST node dict for the upvar declaration
#
proc ::ast::parsers::variables::parse_upvar {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid upvar: expected 'upvar level otherVar myVar'" \
            range [::ast::utils::make_range $start_line 1 $end_line 1]]
    }

    # ✅ FIX: Keep level as STRING (even if it looks like a number)
    set level_token [::tokenizer::get_token $cmd_text 1]
    set level_value [::ast::delimiters::strip_outer $level_token]
    # Force string representation by concatenating with empty string
    set level [format "%s" $level_value]

    set other_var_token [::tokenizer::get_token $cmd_text 2]
    set other_var [::ast::delimiters::strip_outer $other_var_token]

    set local_var ""
    if {$word_count >= 4} {
        set local_var_token [::tokenizer::get_token $cmd_text 3]
        set local_var [::ast::delimiters::strip_outer $local_var_token]
    }

    return [dict create \
        type "upvar" \
        level $level \
        other_var $other_var \
        local_var $local_var \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse an array command
#
# Syntax: array operation arrayName [args...]
#
# Args:
#   cmd_text   - The array command text
#   start_line - Starting line number
#   end_line   - Ending line number
#   depth      - Nesting depth
#
# Returns:
#   AST node dict for the array operation
#
proc ::ast::parsers::variables::parse_array {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid array: expected 'array operation arrayName [args...]'" \
            range [::ast::utils::make_range $start_line 1 $end_line 1]]
    }

    set operation_token [::tokenizer::get_token $cmd_text 1]
    set operation [::ast::delimiters::strip_outer $operation_token]

    set array_name_token [::tokenizer::get_token $cmd_text 2]
    set array_name [::ast::delimiters::strip_outer $array_name_token]

    # Extract additional arguments if present
    set args [list]
    for {set i 3} {$i < $word_count} {incr i} {
        set arg_token [::tokenizer::get_token $cmd_text $i]
        set arg [::ast::delimiters::normalize $arg_token]
        lappend args $arg
    }

    return [dict create \
        type "array" \
        operation $operation \
        array_name $array_name \
        args $args \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}
