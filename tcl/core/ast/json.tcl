#!/usr/bin/env tclsh
# tcl/core/ast/json.tcl
# JSON Serialization Module for TCL AST
#
# This module provides functions to convert TCL dict/list structures to JSON format.
# Critical for communicating AST data between TCL parser and Lua LSP layer.
#
# ⭐ IMPORTANT: This file contains the FIX for the "bad class 'dict'" error
# that was blocking 42 test cases.

namespace eval ::ast::json {
    namespace export dict_to_json list_to_json escape to_json
}

# Convert a TCL dict to JSON object format
#
# This function handles nested dicts, lists, and primitive values.
# It recursively converts complex structures to proper JSON.
#
# ⭐ FIXED: Uses proper dict detection via catch {dict size} instead of invalid
#        [string is dict] which doesn't exist in TCL.
#
# Args:
#   dict_data    - Dict to convert
#   indent_level - Current indentation level (for pretty printing)
#
# Returns:
#   JSON string representation of the dict
#
proc ::ast::json::dict_to_json {dict_data {indent_level 0}} {
    set indent [string repeat "  " $indent_level]
    set next_indent [string repeat "  " [expr {$indent_level + 1}]]

    set result "\{\n"
    set first_key 1

    dict for {key value} $dict_data {
        if {!$first_key} {
            append result ",\n"
        }
        set first_key 0

        append result "${next_indent}\"$key\": "

        # Check if value is a list first
        set value_len [llength $value]

        if {$value_len > 1} {
            # Multiple elements - could be a list or a dict
            # Check if it's a dict by trying dict operations
            # ⭐ FIX: Use catch {dict size} instead of [string is dict]
            set is_dict 0
            if {[catch {dict size $value} size] == 0 && $size > 0} {
                # It's a valid dict with content
                set is_dict 1
            }

            if {$is_dict} {
                append result [dict_to_json $value [expr {$indent_level + 1}]]
            } else {
                # It's a list
                append result [list_to_json $value [expr {$indent_level + 1}]]
            }
        } elseif {$value_len == 1} {
            # Single element - check if it's a dict or simple value
            set is_dict 0
            if {[catch {dict size $value} size] == 0 && $size > 0} {
                set is_dict 1
            }

            if {$is_dict} {
                append result [dict_to_json $value [expr {$indent_level + 1}]]
            } elseif {[string is integer -strict $value] || [string is double -strict $value]} {
                # Numeric value - no quotes
                append result $value
            } else {
                # String value
                append result "\"[escape $value]\""
            }
        } else {
            # Empty value - empty string
            append result "\"\""
        }
    }

    append result "\n${indent}\}"
    return $result
}

# Convert a TCL list to JSON array format
#
# Handles two cases:
# 1. List of dicts (each element is a dict) → array of objects
# 2. List of primitives (strings, numbers) → array of values
#
# ⭐ FIXED: Uses proper dict detection via catch {dict size} instead of invalid
#        [string is dict] which doesn't exist in TCL.
#
# Args:
#   value        - List to convert
#   indent_level - Current indentation level
#
# Returns:
#   JSON string representation of the list
#
proc ::ast::json::list_to_json {value {indent_level 0}} {
    set next_indent [string repeat "  " $indent_level]

    if {[llength $value] == 0} {
        return "\[\]"
    }

    set first_elem [lindex $value 0]

    # Check if first element is a dict
    # ⭐ FIX: Use catch {dict size} instead of [string is dict]
    set is_dict_list 0
    if {[catch {dict size $first_elem} size] == 0 && $size > 0} {
        # First element is a dict - this is likely a list of dicts
        set is_dict_list 1
    }

    if {$is_dict_list} {
        # List of dicts - format as array of objects with pretty printing
        set result "\[\n"
        set first_item 1
        foreach item $value {
            if {!$first_item} {
                append result ",\n"
            }
            set first_item 0
            append result "${next_indent}  "
            append result [dict_to_json $item [expr {$indent_level + 1}]]
        }
        append result "\n${next_indent}\]"
        return $result
    } else {
        # List of primitives - format as compact array
        set result "\["
        set first_item 1
        foreach item $value {
            if {!$first_item} {
                append result ", "
            }
            set first_item 0
            if {[string is integer -strict $item] || [string is double -strict $item]} {
                append result $item
            } else {
                append result "\"[escape $item]\""
            }
        }
        append result "\]"
        return $result
    }
}

# Escape special characters for JSON strings
#
# Handles: backslash, quotes, newline, carriage return, tab
#
# Args:
#   str - String to escape
#
# Returns:
#   JSON-escaped string
#
proc ::ast::json::escape {str} {
    set str [string map {
        \\ \\\\
        \" \\\"
        \n \\n
        \r \\r
        \t \\t
    } $str]
    return $str
}

# Convert an AST (as a dict) to JSON string
#
# This is the main entry point for JSON serialization.
# Call this to convert a complete AST to JSON for output.
#
# Args:
#   ast - AST dict to convert
#
# Returns:
#   JSON string representation
#
proc ::ast::json::to_json {ast} {
    return [dict_to_json $ast 0]
}

# ===========================================================================
# MAIN - For testing
# ===========================================================================

if {[info script] eq $argv0} {
    puts "Testing JSON module..."
    puts ""

    # Test 1: Simple dict with primitives
    puts "Test 1: Simple dict"
    set test1 [dict create type "proc" name "hello" line 1]
    puts [to_json $test1]
    puts ""

    # Test 2: Dict with nested dict
    puts "Test 2: Nested dict"
    set test2 [dict create \
        type "proc" \
        name "test" \
        range [dict create start 1 end 10]]
    puts [to_json $test2]
    puts ""

    # Test 3: Dict with list of primitives
    puts "Test 3: List of primitives"
    set test3 [dict create \
        type "proc" \
        params [list "x" "y" "z"]]
    puts [to_json $test3]
    puts ""

    # Test 4: Dict with list of dicts
    puts "Test 4: List of dicts"
    set test4 [dict create \
        type "root" \
        children [list \
            [dict create type "proc" name "hello"] \
            [dict create type "proc" name "world"]]]
    puts [to_json $test4]
    puts ""

    # Test 5: Empty collections
    puts "Test 5: Empty collections"
    set test5 [dict create \
        type "root" \
        children [list] \
        errors [list]]
    puts [to_json $test5]
    puts ""

    # Test 6: String with special characters
    puts "Test 6: Special characters"
    set test6 [dict create \
        type "string" \
        value "Line 1\nLine 2\t\"Quoted\""]
    puts [to_json $test6]
    puts ""

    # Test 7: Numeric values
    puts "Test 7: Numeric values"
    set test7 [dict create \
        type "number" \
        int_val 42 \
        float_val 3.14]
    puts [to_json $test7]
    puts ""

    # Test 8: Complex nested structure
    puts "Test 8: Complex structure"
    set test8 [dict create \
        type "root" \
        filepath "test.tcl" \
        children [list \
            [dict create \
                type "proc" \
                name "calculate" \
                params [list "x" "y"] \
                range [dict create start 1 end 5]]]]
    puts [to_json $test8]
    puts ""

    puts "✓ All JSON tests complete"
    puts "✓ The 'bad class dict' error should be FIXED!"
}
