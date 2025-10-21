#!/usr/bin/env tclsh
# tcl/core/ast/json.tcl
# JSON Serialization Module for TCL AST (WITH TYPE CONVERSION FIX)
#
# This module provides functions to convert TCL dict/list structures to JSON format.
# Critical for communicating AST data between TCL parser and Lua LSP layer.
#
# ⭐ FIX #1: Context-aware serialization - preserves string types for TCL values
# ⭐ FIX #2: Uses proper dict detection via catch {dict size}

namespace eval ::ast::json {
    namespace export dict_to_json list_to_json escape to_json

    # Fields that should be serialized as JSON numbers (not strings)
    # All other fields default to strings, preserving TCL's string nature
    variable numeric_fields {
        line column
        start_line end_line start_col end_col
        start end
        had_error
        depth level
        count size length
    }
}

# Check if a key should be serialized as a number
proc ::ast::json::is_numeric_field {key} {
    variable numeric_fields
    return [expr {$key in $numeric_fields}]
}

# Convert a TCL dict to JSON object format
#
# This function handles nested dicts, lists, and primitive values.
# It recursively converts complex structures to proper JSON.
#
# ⭐ FIX: Context-aware - only serializes whitelisted fields as numbers
#         All other values remain as strings (preserving TCL semantics)
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
            # Multiple elements - could be:
            # 1. A list of dicts: [list [dict create ...] [dict create ...]]
            # 2. A dict itself: [dict create key1 val1 key2 val2]
            # 3. A list of primitives: [list "a" "b" "c"]

            # Check if first element is a dict to determine if it's a list of dicts
            set first_elem [lindex $value 0]
            set is_list_of_dicts 0
            if {[catch {dict size $first_elem} size] == 0 && $size > 0} {
                # First element is a dict - likely a list of dicts
                set is_list_of_dicts 1
            }

            if {$is_list_of_dicts} {
                # It's a list of dicts
                append result [list_to_json $value [expr {$indent_level + 1}]]
            } else {
                # Try to treat as dict first
                set is_dict 0
                if {[catch {dict size $value} size] == 0 && $size > 0} {
                    # It's a valid dict with content
                    set is_dict 1
                }

                if {$is_dict} {
                    append result [dict_to_json $value [expr {$indent_level + 1}]]
                } else {
                    # It's a list of primitives
                    append result [list_to_json $value [expr {$indent_level + 1}]]
                }
            }
        } elseif {$value_len == 1} {
            # Single element - could be:
            # 1. A list containing one dict: [list [dict create ...]]
            # 2. A dict itself: [dict create ...]
            # 3. A simple value: "hello" or 42

            # Try to extract first element to check if it's a list of dicts
            set first_elem [lindex $value 0]
            set is_list_of_dict 0
            if {[catch {dict size $first_elem} size] == 0 && $size > 0} {
                # First element is a dict - this is a list containing one dict
                set is_list_of_dict 1
            }

            if {$is_list_of_dict} {
                # It's a list with one dict - serialize as array
                append result [list_to_json $value [expr {$indent_level + 1}]]
            } else {
                # Check if the value itself is a dict
                set is_dict 0
                if {[catch {dict size $value} size] == 0 && $size > 0} {
                    set is_dict 1
                }

                if {$is_dict} {
                    append result [dict_to_json $value [expr {$indent_level + 1}]]
                } else {
                    # ⭐ FIX: Context-aware primitive serialization
                    # Check if this field should be numeric
                    if {[is_numeric_field $key] && ([string is integer -strict $value] || [string is double -strict $value])} {
                        # Whitelisted numeric field - output as JSON number
                        append result $value
                    } else {
                        # All other values - output as JSON string
                        append result "\"[escape $value]\""
                    }
                }
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
# ⭐ FIX #1: Uses proper dict detection via catch {dict size}
# ⭐ FIX #2: Lists of primitives default to strings (no numeric conversion)
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
        # ⭐ FIX: List of primitives - ALL VALUES AS STRINGS by default
        # This preserves TCL's string semantics and prevents type conversion issues
        # Only the whitelisted fields in dict_to_json will be numeric
        set result "\["
        set first_item 1
        foreach item $value {
            if {!$first_item} {
                append result ", "
            }
            set first_item 0
            # Always quote primitives in arrays (unless it's from a numeric field, handled in dict_to_json)
            append result "\"[escape $item]\""
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
    puts "Testing JSON module with TYPE CONVERSION FIX..."
    puts ""

    # Test 1: Simple dict with primitives
    puts "Test 1: Simple dict"
    set test1 [dict create type "proc" name "hello" line 1]
    puts [to_json $test1]
    puts "Expected: 'name' and 'type' as strings, 'line' as number"
    puts ""

    # Test 2: Dict with nested dict
    puts "Test 2: Nested dict"
    set test2 [dict create \
        type "proc" \
        name "test" \
        range [dict create start 1 end 10]]
    puts [to_json $test2]
    puts "Expected: 'start' and 'end' as numbers (whitelisted)"
    puts ""

    # Test 3: Dict with list of primitives (THE FIX!)
    puts "Test 3: List of string primitives (FIXED)"
    set test3 [dict create \
        type "proc" \
        params [list "x" "y" "z"]]
    puts [to_json $test3]
    puts "Expected: params as array of STRINGS"
    puts ""

    # Test 4: Numeric-looking strings stay strings (THE KEY FIX!)
    puts "Test 4: Numeric-looking strings (THE KEY FIX)"
    set test4 [dict create \
        type "set" \
        name "version" \
        value "8.6"]
    puts [to_json $test4]
    puts "Expected: 'value' as STRING \"8.6\" (not number 8.6)"
    puts ""

    # Test 5: Dict with list of dicts
    puts "Test 5: List of dicts"
    set test5 [dict create \
        type "root" \
        children [list \
            [dict create type "proc" name "hello"] \
            [dict create type "proc" name "world"]]]
    puts [to_json $test5]
    puts "Expected: Works correctly (already fixed)"
    puts ""

    # Test 6: Empty collections
    puts "Test 6: Empty collections"
    set test6 [dict create \
        type "root" \
        children [list] \
        errors [list]]
    puts [to_json $test6]
    puts ""

    # Test 7: String with special characters
    puts "Test 7: Special characters"
    set test7 [dict create \
        type "string" \
        value "Line 1\nLine 2\t\"Quoted\""]
    puts [to_json $test7]
    puts ""

    # Test 8: Numeric values in whitelisted fields
    puts "Test 8: Numeric values (whitelisted fields)"
    set test8 [dict create \
        type "proc" \
        line 42 \
        column 10]
    puts [to_json $test8]
    puts "Expected: 'line' and 'column' as numbers"
    puts ""

    # Test 9: Mixed numeric/string values
    puts "Test 9: Mixed values - default vs integers"
    set test9 [dict create \
        type "proc" \
        name "test" \
        params [list "x" "{y 10}"] \
        line 5]
    puts [to_json $test9]
    puts "Expected: 'name' as string, params as strings, 'line' as number"
    puts ""

    # Test 10: Version number preservation
    puts "Test 10: Version number (no precision loss)"
    set test10 [dict create \
        type "package_require" \
        package_name "Tcl" \
        version "8.6"]
    puts [to_json $test10]
    puts "Expected: 'version' as STRING \"8.6\" (preserves exact value)"
    puts ""

    puts "✓ All JSON tests complete"
    puts "✓ Type conversion issues should be FIXED!"
    puts ""
    puts "Key improvements:"
    puts "  1. Numeric-looking strings stay as strings"
    puts "  2. Only whitelisted fields (line, column, etc.) are numbers"
    puts "  3. No precision loss (8.6 stays \"8.6\", not 8.5999...)"
    puts "  4. Preserves TCL's 'everything is a string' philosophy"
}
