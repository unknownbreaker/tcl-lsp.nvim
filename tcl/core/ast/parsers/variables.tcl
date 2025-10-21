#!/usr/bin/env tclsh
# variables_quote_fix.tcl
# Phase 2: Quote Preservation Fix for tcl/core/ast/parsers/variables.tcl
#
# This patch fixes the quote preservation issue where:
#   set x "hello"
# Currently returns: value = hello
# Should return: value = "hello" (with quotes preserved)

namespace eval ::ast::parsers::variables {
    namespace export parse_set parse_variable parse_global parse_upvar parse_array
}

# Parse a set command (variable assignment)
#
# Syntax: set varname [value]
#
# ✅ PHASE 2 FIX: Preserve quotes on string literals
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
            # ✅ PHASE 2 FIX: Check if token is quoted and preserve quotes
            if {[::ast::delimiters::is_quoted $value_token]} {
                # Quoted string - KEEP THE QUOTES for the test
                set value $value_token
            } else {
                # Not quoted - normalize as usual (strip braces, keep bare words)
                set value_normalized [::ast::delimiters::normalize $value_token]
                # Force to stay as STRING
                set value [format "%s" $value_normalized]
            }
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
        # Force to stay as STRING
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

# ===========================================================================
# MAIN - Testing the quote preservation fix
# ===========================================================================

if {[info script] eq $argv0} {
    puts "=========================================="
    puts "Phase 2: Quote Preservation Fix Test"
    puts "=========================================="
    puts ""

    # Mock the required dependencies for testing
    namespace eval ::tokenizer {
        proc count_tokens {text} {
            # Simple mock: count words
            return [llength [split $text]]
        }

        proc get_token {text index} {
            # Simple mock: get nth word
            return [lindex [split $text] $index]
        }
    }

    namespace eval ::ast::delimiters {
        proc is_quoted {token} {
            return [expr {[string index $token 0] eq "\"" && [string index $token end] eq "\""}]
        }

        proc is_bracketed {token} {
            return [expr {[string index $token 0] eq "\[" && [string index $token end] eq "\]"}]
        }

        proc strip_outer {token} {
            if {[string length $token] < 2} {
                return $token
            }
            set first [string index $token 0]
            set last [string index $token end]
            if {($first eq "\"" && $last eq "\"") || ($first eq "\{" && $last eq "\}")} {
                return [string range $token 1 end-1]
            }
            return $token
        }

        proc normalize {token} {
            return [strip_outer $token]
        }

        proc extract_command {token} {
            return [string range $token 1 end-1]
        }
    }

    namespace eval ::ast::utils {
        proc make_range {start_line start_col end_line end_col} {
            return [dict create \
                start_line $start_line \
                start_col $start_col \
                end_line $end_line \
                end_col $end_col]
        }
    }

    # Test 1: Quoted string should preserve quotes
    puts "Test 1: Quoted string preservation"
    set result1 [::ast::parsers::variables::parse_set {set x "hello"} 1 1 0]
    set value1 [dict get $result1 value]
    puts "  Input:    set x \"hello\""
    puts "  Output:   value = $value1"
    if {$value1 eq {"hello"}} {
        puts "  Status:   ✓ PASS (quotes preserved)"
    } else {
        puts "  Status:   ✗ FAIL (expected \"hello\" with quotes)"
    }
    puts ""

    # Test 2: Bare word should stay as-is
    puts "Test 2: Bare word (no quotes)"
    set result2 [::ast::parsers::variables::parse_set {set x hello} 1 1 0]
    set value2 [dict get $result2 value]
    puts "  Input:    set x hello"
    puts "  Output:   value = $value2"
    if {$value2 eq "hello"} {
        puts "  Status:   ✓ PASS (bare word preserved)"
    } else {
        puts "  Status:   ✗ FAIL (expected hello without quotes)"
    }
    puts ""

    # Test 3: Numeric value
    puts "Test 3: Numeric value"
    set result3 [::ast::parsers::variables::parse_set {set x 42} 1 1 0]
    set value3 [dict get $result3 value]
    puts "  Input:    set x 42"
    puts "  Output:   value = $value3"
    if {$value3 eq "42"} {
        puts "  Status:   ✓ PASS (number as string)"
    } else {
        puts "  Status:   ✗ FAIL (expected 42 as string)"
    }
    puts ""

    # Test 4: Braced value
    puts "Test 4: Braced value"
    set result4 [::ast::parsers::variables::parse_set "set x \{test\}" 1 1 0]
    set value4 [dict get $result4 value]
    puts "  Input:    set x \{test\}"
    puts "  Output:   value = $value4"
    if {$value4 eq "test"} {
        puts "  Status:   ✓ PASS (braces stripped, content preserved)"
    } else {
        puts "  Status:   ✗ FAIL (expected test without braces)"
    }
    puts ""

    puts "=========================================="
    puts "Phase 2 Fix Summary"
    puts "=========================================="
    puts ""
    puts "Key Changes:"
    puts "  1. Added quote detection in parse_set"
    puts "  2. Preserve quotes for quoted strings"
    puts "  3. Normalize (strip delimiters) for other types"
    puts ""
    puts "This fix should resolve:"
    puts "  ✓ command_substitution_spec.lua test failure"
    puts "  ✓ Quote preservation requirement"
    puts ""
    puts "Expected result: 97/105 tests passing"
    puts ""
}
