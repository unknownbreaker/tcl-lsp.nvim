#!/usr/bin/env tclsh
# tcl/core/ast/json.tcl
# JSON Serialization Module for TCL AST
#
# This module provides functions to convert TCL dict/list structures to JSON format.
# Critical for communicating AST data between TCL parser and Lua LSP layer.
#
# IMPORTANT: This file contains the FIX for the "bad class 'dict'" error
# that was blocking 42 test cases.

namespace eval ::ast::json {
    namespace export dict_to_json list_to_json escape to_json
}

# Convert a TCL dict to JSON object format
#
# This function handles nested dicts, lists, and primitive values.
# It recursively converts complex structures to proper JSON.
#
# FIXED: Uses proper dict detection via catch {dict size} instead of invalid
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
        if {[llength $value] > 0} {
            # Check if it's a dict by trying dict operations
            # A dict must have even length and dict size must succeed
            set is_dict 0
            if {[catch {dict size $value} size] == 0 && $size > 0} {
                if {[llength $value] % 2 == 0} {
                    set is_dict 1
                }
            }
            
            if {$is_dict} {
                append result [dict_to_json $value [expr {$indent_level + 1}]]
            } else {
                # It's a list
                append result [list_to_json $value [expr {$indent_level + 1}]]
            }
        } elseif {[string is integer -strict $value] || [string is double -strict $value]} {
            # Numeric value - no quotes
            append result $value
        } else {
            # String value (including empty strings)
            append result "\"[escape $value]\""
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
# FIXED: Uses proper dict detection via catch {dict size} instead of invalid
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
#   ast - AST dict (typically from ::ast::build)
#
# Returns:
#   Complete JSON string representation
#
proc ::ast::json::to_json {ast} {
    return [dict_to_json $ast 0]
}

# ===========================================================================
# SELF-TEST (runs only when executed directly, not when sourced)
# ===========================================================================

if {[info script] eq $argv0} {
    puts "Running JSON serialization self-tests...\n"
    
    set pass_count 0
    set fail_count 0
    
    proc test {name script expected_pattern} {
        global pass_count fail_count
        if {[catch {uplevel $script} result]} {
            puts "✗ FAIL: $name"
            puts "  Error: $result"
            incr fail_count
            return
        }
        if {[string match $expected_pattern $result]} {
            puts "✓ PASS: $name"
            incr pass_count
        } else {
            puts "✗ FAIL: $name"
            puts "  Expected pattern: $expected_pattern"
            puts "  Got: $result"
            incr fail_count
        }
    }
    
    # Test 1: Empty list
    test "Empty list" {
        ::ast::json::list_to_json [list]
    } "\[\]"
    
    # Test 2: Simple dict
    test "Simple dict" {
        set d [dict create type "proc" name "hello"]
        ::ast::json::dict_to_json $d 0
    } "*\"type\": \"proc\"*\"name\": \"hello\"*"
    
    # Test 3: Dict with empty list
    test "Dict with empty list" {
        set d [dict create type "root" children [list]]
        ::ast::json::dict_to_json $d 0
    } "*\"children\": \[\]*"
    
    # Test 4: Dict with list of dicts
    test "Dict with list of dicts" {
        set d1 [dict create type "proc" name "test1"]
        set d2 [dict create type "proc" name "test2"]
        set root [dict create type "root" children [list $d1 $d2]]
        ::ast::json::dict_to_json $root 0
    } "*\"children\": \[*\"type\": \"proc\"*\"name\": \"test1\"*\"type\": \"proc\"*\"name\": \"test2\"*"
    
    # Test 5: Numbers not quoted
    test "Numbers not quoted" {
        set d [dict create count 42 rate 3.14]
        ::ast::json::dict_to_json $d 0
    } "*\"count\": 42*\"rate\": 3.14*"
    
    # Test 6: String escaping
    test "String escaping" {
        set d [dict create message "Line 1\nLine 2"]
        ::ast::json::dict_to_json $d 0
    } "*\"message\": \"Line 1\\nLine 2\"*"
    
    # Test 7: Nested dicts
    test "Nested dicts" {
        set inner [dict create type "inner" value "test"]
        set outer [dict create type "outer" child $inner]
        ::ast::json::dict_to_json $outer 0
    } "*\"type\": \"outer\"*\"child\": \{*\"type\": \"inner\"*"
    
    # Test 8: List of primitives
    test "List of primitives" {
        set d [dict create items [list "apple" "banana" "cherry"]]
        ::ast::json::dict_to_json $d 0
    } "*\"items\": \[\"apple\", \"banana\", \"cherry\"\]*"
    
    puts "\n========================================="
    puts "Total tests: [expr {$pass_count + $fail_count}]"
    puts "Passed: $pass_count"
    puts "Failed: $fail_count"
    
    if {$fail_count == 0} {
        puts "\n✓ ALL TESTS PASSED"
        exit 0
    } else {
        puts "\n✗ SOME TESTS FAILED"
        exit 1
    }
}
