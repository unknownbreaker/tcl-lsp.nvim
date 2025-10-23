#!/usr/bin/env tclsh
# tcl/core/ast/json.tcl
# JSON Serialization Module for TCL AST (Phase 3 Fix - List & Boolean Handling)
#
# This module provides functions to convert TCL dict/list structures to JSON format.
# Critical for communicating AST data between TCL parser and Lua LSP layer.
#
# PHASE 3 FIXES:
# ⭐ FIX #1: Empty lists serialize as [] not ""
# ⭐ FIX #2: Single-element lists serialize as ["item"] not "item"
# ⭐ FIX #3: Boolean fields serialize as true/false not "true"/"false"
# ⭐ FIX #4: Proper list detection to avoid converting lists to dicts

namespace eval ::ast::json {
    namespace export dict_to_json list_to_json escape to_json

    # Fields that should be serialized as JSON numbers (not strings)
    variable numeric_fields {
        line column
        start_line end_line start_col end_col
        start end
        had_error
        depth
        count size length
    }

    # Fields that should be serialized as JSON booleans
    # These will convert TCL 1/0 or "true"/"false" to JSON true/false
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

# Check if a value is a dict (safe detection)
proc ::ast::json::is_dict {value} {
    # A dict must have even number of elements and be valid
    if {[llength $value] % 2 != 0} {
        return 0
    }
    if {[llength $value] == 0} {
        return 0
    }
    # Try to access it as a dict
    if {[catch {dict size $value}]} {
        return 0
    }
    return 1
}

# Convert a TCL dict to JSON object format
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

        # ⭐ PHASE 3 FIX: Check for empty list FIRST before checking length
        if {[llength $value] == 0} {
            # ⭐ FIX: Empty list must serialize as [] not ""
            append result "\[\]"
            continue
        }

        # Get value length
        set value_len [llength $value]

        # Check if it's a list (more than 1 element) or potential single-element list
        if {$value_len == 1} {
            # Single element - could be:
            # 1. A simple string/number
            # 2. A dict
            # 3. A single-element list containing a dict

            set first_elem [lindex $value 0]

            # Check if the single element is itself a dict
            if {[is_dict $first_elem]} {
                # It's a list containing one dict - serialize as array with one object
                append result [list_to_json $value [expr {$indent_level + 1}]]
            } elseif {[is_dict $value]} {
                # The value itself is a dict - serialize as object
                append result [dict_to_json $value [expr {$indent_level + 1}]]
            } else {
                # ⭐ PHASE 3 FIX: Check if this should be a single-element array
                # If the key suggests it's a list (params, vars, patterns, etc.), keep it as array
                if {$key eq "params" || $key eq "vars" || $key eq "patterns" ||
                    $key eq "children" || $key eq "items" || [string match "*s" $key]} {
                    # Serialize as single-element array
                    append result [list_to_json $value [expr {$indent_level + 1}]]
                } else {
                    # It's a primitive value - serialize based on field type
                    if {[is_boolean_field $key]} {
                        append result [to_json_boolean $value]
                    } elseif {[is_numeric_field $key] && ([string is integer -strict $value] || [string is double -strict $value])} {
                        append result $value
                    } else {
                        append result "\"[escape $value]\""
                    }
                }
            }
        } elseif {$value_len > 1} {
            # Multiple elements - could be a list or a dict

            set first_elem [lindex $value 0]

            # Check if first element is a dict (list of dicts pattern)
            if {[is_dict $first_elem]} {
                # It's a list of dicts
                append result [list_to_json $value [expr {$indent_level + 1}]]
            } elseif {[is_dict $value]} {
                # The value itself is a dict
                append result [dict_to_json $value [expr {$indent_level + 1}]]
            } else {
                # It's a list of primitives
                append result [list_to_json $value [expr {$indent_level + 1}]]
            }
        }
    }

    append result "\n${indent}\}"
    return $result
}

# Convert a TCL list to JSON array format
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

    # ⭐ PHASE 3 FIX: Handle empty list properly
    if {[llength $value] == 0} {
        return "\[\]"
    }

    set first_elem [lindex $value 0]

    # Check if first element is a dict
    set is_dict_list 0
    if {[is_dict $first_elem]} {
        set is_dict_list 1
    }

    if {$is_dict_list} {
        # List of dicts - format as array of objects
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
        # List of primitives - format as simple array
        set result "\["
        set first_item 1
        foreach item $value {
            if {!$first_item} {
                append result ", "
            }
            set first_item 0

            # Check if item should be numeric or string
            if {[string is integer -strict $item] || [string is double -strict $item]} {
                # Keep as number in arrays of primitives
                append result $item
            } else {
                # Quote as string
                append result "\"[escape $item]\""
            }
        }
        append result "\]"
        return $result
    }
}

# Escape special characters for JSON strings
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
    puts "Testing JSON module - Phase 3 Fixes..."
    puts ""

    # Test 1: Empty list
    puts "Test 1: Empty list"
    set test1 [dict create type "proc" params [list]]
    puts [::ast::json::to_json $test1]
    puts "Expected: params as empty array \[\]"
    puts ""

    # Test 2: Single-element list
    puts "Test 2: Single-element list (vars)"
    set test2 [dict create type "global" vars [list "myvar"]]
    puts [::ast::json::to_json $test2]
    puts "Expected: vars as array \[\"myvar\"\]"
    puts ""

    # Test 3: Boolean field
    puts "Test 3: Boolean field (has_varargs)"
    set test3 [dict create type "param" name "args" has_varargs 1]
    puts [::ast::json::to_json $test3]
    puts "Expected: has_varargs as boolean true"
    puts ""

    # Test 4: Namespace import patterns
    puts "Test 4: Namespace import patterns"
    set test4 [dict create type "namespace_import" patterns [list "::Other::*"]]
    puts [::ast::json::to_json $test4]
    puts "Expected: patterns as array \[\"::Other::*\"\]"
    puts ""

    # Test 5: Multiple params
    puts "Test 5: Multiple params"
    set test5 [dict create type "proc" name "add" params [list \
        [dict create name "x"] \
        [dict create name "y"]]]
    puts [::ast::json::to_json $test5]
    puts "Expected: params as array of objects"
    puts ""

    puts "✓ Phase 3 JSON tests complete"
}
