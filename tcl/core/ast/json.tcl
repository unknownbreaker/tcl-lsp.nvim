#!/usr/bin/env tclsh
# tcl/core/ast/json.tcl
# JSON Serialization Module for TCL AST (WITH TYPE CONVERSION FIX v2)
#
# This module provides functions to convert TCL dict/list structures to JSON format.
# Critical for communicating AST data between TCL parser and Lua LSP layer.
#
# ⭐ FIX #1: Context-aware serialization - preserves string types for TCL values
# ⭐ FIX #2: Uses proper dict detection via catch {dict size}
# ⭐ FIX #3: Separate handling for boolean fields
# ⭐ FIX #4: Removed 'level' from numeric whitelist (stays as string)

namespace eval ::ast::json {
    namespace export dict_to_json list_to_json escape to_json

    # Fields that should be serialized as JSON numbers (not strings)
    # All other fields default to strings, preserving TCL's string nature
    # NOTE: 'level' is NOT in this list - it should remain a string
    variable numeric_fields {
        line column
        start_line end_line start_col end_col
        start end
        had_error
        depth
        count size length
    }

    # Fields that should be serialized as JSON booleans
    # These will convert TCL "true"/"false" or 1/0 to JSON true/false
    variable boolean_fields {
        has_varargs
        is_variadic
        is_optional
        quoted
    }
}

# Check if a key should be serialized as a number
proc ::ast::json::is_numeric_field {key} {
    variable numeric_fields
    return [expr {$key in $numeric_fields}]
}

# Check if a key should be serialized as a boolean
proc ::ast::json::is_boolean_field {key} {
    variable boolean_fields
    return [expr {$key in $boolean_fields}]
}

# Convert TCL boolean value to JSON boolean
proc ::ast::json::to_json_boolean {value} {
    # Handle various TCL boolean representations
    if {$value eq "true" || $value eq "yes" || $value eq "on" || $value == 1} {
        return "true"
    } else {
        return "false"
    }
}

# Convert a TCL dict to JSON object format
#
# This function handles nested dicts, lists, and primitive values.
# It recursively converts complex structures to proper JSON.
#
# ⭐ FIX: Context-aware - only serializes whitelisted fields as numbers/booleans
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
            # 3. A list containing one dict: [list [dict create ...]]
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
                    # It's a list of primitives - serialize as array
                    append result [list_to_json $value [expr {$indent_level + 1}]]
                }
            }
        } elseif {$value_len == 1} {
            # Single element - could be:
            # 1. A list containing one dict: [list [dict create ...]]
            # 2. A dict itself: [dict create ...]
            # 3. A simple value: "hello" or 42

            set first_elem [lindex $value 0]

            # Check if it's a dict
            set is_dict 0
            if {[catch {dict size $first_elem} size] == 0 && $size > 0} {
                # It's a dict
                set is_dict 1
            }

            if {$is_dict} {
                # Check if value is the dict itself or a list containing the dict
                # We can check by seeing if the dict sizes match
                set outer_size 0
                catch {set outer_size [dict size $value]}

                if {$outer_size > 0 && $outer_size == $size} {
                    # Value is the dict itself
                    append result [dict_to_json $value [expr {$indent_level + 1}]]
                } else {
                    # Value is a list containing one dict
                    append result [list_to_json $value [expr {$indent_level + 1}]]
                }
            } else {
                # ⭐ FIX: Context-aware primitive serialization
                # Check field type: boolean > numeric > string (default)
                if {[is_boolean_field $key]} {
                    # Boolean field - convert to JSON boolean
                    append result [to_json_boolean $value]
                } elseif {[is_numeric_field $key] && ([string is integer -strict $value] || [string is double -strict $value])} {
                    # Whitelisted numeric field - output as JSON number
                    append result $value
                } else {
                    # All other values - output as JSON string
                    append result "\"[escape $value]\""
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
    puts "Testing JSON module with TYPE CONVERSION FIX v2..."
    puts ""

    # Test 1: Numeric field (should be number)
    puts "Test 1: Numeric field"
    set test1 [dict create type "proc" name "test" line 42]
    puts [::ast::json::to_json $test1]
    puts "Expected: line as number (42)"
    puts ""

    # Test 2: Level field (should be STRING, not number)
    puts "Test 2: Level field (FIXED - now string)"
    set test2 [dict create type "upvar" level "1" vars [list "x" "y"]]
    puts [::ast::json::to_json $test2]
    puts "Expected: level as STRING \"1\" (not number)"
    puts ""

    # Test 3: Boolean field (should be boolean)
    puts "Test 3: Boolean field (NEW FIX)"
    set test3 [dict create type "proc" name "test" has_varargs "true"]
    puts [::ast::json::to_json $test3]
    puts "Expected: has_varargs as boolean true"
    puts ""

    # Test 4: Version number (should be string)
    puts "Test 4: Version number"
    set test4 [dict create type "package_require" version "8.6"]
    puts [::ast::json::to_json $test4]
    puts "Expected: version as STRING \"8.6\""
    puts ""

    # Test 5: Default parameter (should be string)
    puts "Test 5: Default parameter"
    set test5 [dict create type "param" name "y" default "10"]
    puts [::ast::json::to_json $test5]
    puts "Expected: default as STRING \"10\""
    puts ""

    # Test 6: Mixed fields
    puts "Test 6: Mixed numeric/string/boolean fields"
    set test6 [dict create \
        type "proc" \
        name "test" \
        line 5 \
        has_varargs 1 \
        params [list "x" "y"]]
    puts [::ast::json::to_json $test6]
    puts "Expected: line=5 (number), has_varargs=true (boolean), params=\[strings\]"
    puts ""

    puts "✓ All JSON tests complete"
    puts "✓ Type conversion issues should be FIXED!"
    puts ""
    puts "Key improvements in v2:"
    puts "  1. Removed 'level' from numeric whitelist"
    puts "  2. Added boolean field support"
    puts "  3. Boolean fields: has_varargs, is_variadic, is_optional, quoted"
}
