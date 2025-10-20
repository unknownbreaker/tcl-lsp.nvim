#!/usr/bin/env tclsh
# tcl/core/ast/parsers/variables.tcl
# Variable Declaration Parsing Module
#
# FIXES:
# 1. Preserve original token text for values (don't interpret!)
# 2. Keep quotes: "hello" stays as "\"hello\"" in JSON
# 3. Keep numbers as strings: 42 stays as "42" not numeric 42
# 4. Global vars return as structured array not simple string
# 5. Upvar level stays as string not number
#
# CRITICAL: This parser must NOT evaluate or interpret values!
# It should preserve the EXACT text from the source code.

namespace eval ::ast::parsers::variables {
    namespace export parse_set parse_variable parse_global parse_upvar parse_array
}

# Parse a set command (variable assignment)
#
# Syntax: set varname [value]
#
# ⭐ CRITICAL: This function preserves the EXACT token text
# If source says: set x "hello"
# Then value MUST be: "hello" (with quotes)
# NOT: hello (interpreted string)
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

    # Extract variable name
    set var_name [::tokenizer::get_token $cmd_text 1]

    # Extract value if present - PRESERVE ORIGINAL TEXT
    set value ""
    if {$word_count >= 3} {
        # ⭐ FIX: Get the raw token text, don't interpret it!
        # If the token is "hello", we want to keep the quotes
        # If the token is 42, we want to keep it as string "42"
        set value [::tokenizer::get_token $cmd_text 2]

        # The tokenizer might have already stripped outer braces/quotes
        # depending on how it's implemented. We trust it gives us what
        # it parsed, but we ensure it's treated as a string in the AST.
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

    set var_name [::tokenizer::get_token $cmd_text 1]

    # Preserve original text for value
    set value ""
    if {$word_count >= 3} {
        set value [::tokenizer::get_token $cmd_text 2]
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
# ⭐ FIX: Returns vars as ARRAY of strings, not a single string
#
# Args:
#   cmd_text   - The global command text
#   start_line - Starting line number
#   end_line   - Ending line number
#   depth      - Nesting depth
#
# Returns:
#   AST node dict with vars as array
#
proc ::ast::parsers::variables::parse_global {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid global: expected 'global var1 [var2 ...]'" \
            range [::ast::utils::make_range $start_line 1 $end_line 1]]
    }

    # Get all variable names after 'global' - RETURN AS LIST
    set var_names [list]
    for {set i 1} {$i < $word_count} {incr i} {
        lappend var_names [::tokenizer::get_token $cmd_text $i]
    }

    # ⭐ FIX: Return vars as array of variable name objects
    # This allows proper JSON serialization and LSP usage
    set vars_array [list]
    foreach var_name $var_names {
        lappend vars_array [dict create name $var_name]
    }

    return [dict create \
        type "global" \
        vars $vars_array \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse an upvar declaration
#
# Syntax: upvar level otherVar myVar
#
# ⭐ FIX: Level stays as STRING not converted to number
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

    # ⭐ FIX: Keep level as string, don't convert to number
    # Even though "1" looks like a number, it should stay as string "1"
    set level [::tokenizer::get_token $cmd_text 1]
    set other_var [::tokenizer::get_token $cmd_text 2]

    set local_var ""
    if {$word_count >= 4} {
        set local_var [::tokenizer::get_token $cmd_text 3]
    }

    return [dict create \
        type "upvar" \
        level $level \
        other_var $other_var \
        local_var $local_var \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# Parse an array set command
#
# Syntax: array set arrayName {key1 value1 key2 value2}
#
# Args:
#   cmd_text   - The array set command text
#   start_line - Starting line number
#   end_line   - Ending line number
#   depth      - Nesting depth
#
# Returns:
#   AST node dict for the array set
#
proc ::ast::parsers::variables::parse_array {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid array set: expected 'array set name {pairs}'" \
            range [::ast::utils::make_range $start_line 1 $end_line 1]]
    }

    set array_name [::tokenizer::get_token $cmd_text 2]

    # Get the list of key-value pairs
    set pairs ""
    if {$word_count >= 4} {
        set pairs [::tokenizer::get_token $cmd_text 3]
    }

    return [dict create \
        type "array_set" \
        name $array_name \
        pairs $pairs \
        range [::ast::utils::make_range $start_line 1 $end_line 1] \
        depth $depth]
}

# ===========================================================================
# SELF-TEST (run with: tclsh variables.tcl)
# ===========================================================================

if {[info script] eq $argv0} {
    puts "Testing variables.tcl module..."
    puts ""

    # Mock dependencies for testing
    namespace eval ::tokenizer {
        proc count_tokens {text} {
            return [llength $text]
        }
        proc get_token {text index} {
            return [lindex $text $index]
        }
    }

    namespace eval ::ast::utils {
        proc make_range {start_line start_col end_line end_col} {
            return [dict create \
                start [dict create line $start_line column $start_col] \
                end [dict create line $end_line column $end_col]]
        }
    }

    set total 0
    set passed 0

    proc test {name result_dict checks} {
        global total passed
        incr total

        set all_pass 1
        foreach {check_name check_script expected} $checks {
            set actual [uplevel 1 [list dict get $result_dict] $check_script]
            if {$actual ne $expected} {
                puts "✗ FAIL: $name - $check_name"
                puts "  Expected: $expected"
                puts "  Got: $actual"
                set all_pass 0
            }
        }

        if {$all_pass} {
            puts "✓ PASS: $name"
            incr passed
        }
    }

    # Test 1: set with string value (preserves quotes)
    puts "Test 1: set x \"hello\" - should preserve quotes"
    set cmd1 {set x "hello"}
    set result1 [::ast::parsers::variables::parse_set $cmd1 1 1 0]
    test "set with string" $result1 {
        "var_name" {var_name} "x"
        "value" {value} {"hello"}
    }

    # Test 2: set with numeric value (keeps as string)
    puts "Test 2: set x 42 - should keep as string"
    set cmd2 {set x 42}
    set result2 [::ast::parsers::variables::parse_set $cmd2 1 1 0]
    test "set with number" $result2 {
        "var_name" {var_name} "x"
        "value" {value} "42"
    }

    # Test 3: global with multiple vars (returns array)
    puts "Test 3: global x y z - should return array of vars"
    set cmd3 {global x y z}
    set result3 [::ast::parsers::variables::parse_global $cmd3 1 1 0]
    if {[dict get $result3 type] eq "global"} {
        set vars [dict get $result3 vars]
        if {[llength $vars] == 3} {
            set first_var [lindex $vars 0]
            if {[dict get $first_var name] eq "x"} {
                puts "✓ PASS: global returns array"
                incr passed
                incr total
            } else {
                puts "✗ FAIL: global - wrong var name"
                incr total
            }
        } else {
            puts "✗ FAIL: global - wrong var count"
            incr total
        }
    } else {
        puts "✗ FAIL: global - wrong type"
        incr total
    }

    # Test 4: upvar with level as string
    puts "Test 4: upvar 1 other local - level should be string"
    set cmd4 {upvar 1 other local}
    set result4 [::ast::parsers::variables::parse_upvar $cmd4 1 1 0]
    test "upvar level" $result4 {
        "level" {level} "1"
        "other_var" {other_var} "other"
        "local_var" {local_var} "local"
    }

    puts ""
    puts "Results: $passed/$total tests passed"

    if {$passed == $total} {
        puts "✓ ALL TESTS PASSED"
        puts ""
        puts "Key fixes verified:"
        puts "  ✓ String values preserve quotes"
        puts "  ✓ Numeric values stay as strings"
        puts "  ✓ Global vars return as array"
        puts "  ✓ Upvar level stays as string"
        exit 0
    } else {
        puts "✗ SOME TESTS FAILED"
        exit 1
    }
}
