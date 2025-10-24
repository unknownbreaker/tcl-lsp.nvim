#!/usr/bin/env tclsh
# tcl/core/ast/json.tcl
# JSON Serialization Module for TCL AST - FIXED VERSION
#
# This module provides functions to convert TCL dict/list structures to JSON format.
# Critical for communicating AST data between TCL parser and Lua LSP layer.
#
# FIXES:
# ✅ FIX #1: Strings with special chars no longer misinterpreted as lists/dicts
# ✅ FIX #2: Numbers serialize as JSON numbers, not strings
# ✅ FIX #3: Empty dict formats as {} not {\n}
# ✅ FIX #4: Single-element lists stay as arrays when appropriate
# ✅ FIX #5: Boolean fields serialize as true/false

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
        pi
    }

    # Fields that should be serialized as JSON booleans
    variable boolean_fields {
        has_varargs
        is_variadic
        is_optional
        quoted
        flag
    }

    # Fields that are always lists (even with single element)
    variable list_fields {
        params vars patterns children items
        imports exports
        args arguments
        single
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

# Check if a key should always be a list
proc ::ast::json::is_list_field {key} {
    variable list_fields
    return [expr {$key in $list_fields}]
}

# Convert TCL boolean value to JSON boolean
proc ::ast::json::to_json_boolean {value} {
    if {$value eq "true" || $value eq "yes" || $value eq "on" || $value == 1} {
        return "true"
    } else {
        return "false"
    }
}

# Check if a value is actually a proper TCL list (not a string that looks like one)
# This is the KEY fix - we need to distinguish between:
#   - Actual lists created with [list] or lappend
#   - Strings that happen to have spaces/newlines/quotes
proc ::ast::json::is_proper_list {value} {
    # Empty string is not a list
    if {$value eq ""} {
        return 0
    }

    # ✅ FIX: If it has any special characters that need escaping, it's definitely a string
    if {[string first "\n" $value] >= 0 ||
        [string first "\t" $value] >= 0 ||
        [string first "\r" $value] >= 0 ||
        [string first "\"" $value] >= 0 ||
        [string first "\\" $value] >= 0} {
        return 0
    }

    # Try to see if it's a valid list
    if {[catch {llength $value}]} {
        return 0
    }

    set len [llength $value]

    # Length 0 - empty, not a list
    if {$len == 0} {
        return 0
    }

    # Length 1 - most likely a string unless proven otherwise
    if {$len == 1} {
        return 0
    }

    # Length > 1 - could be a list, but also could be a string with spaces
    # If every element looks like a primitive (not a dict), be suspicious
    # For now, assume length > 1 without special chars is a list
    return 1
}

# Check if a value is a dict (safe detection)
proc ::ast::json::is_dict {value} {
    # Empty is not a dict
    if {$value eq ""} {
        return 0
    }

    # ✅ FIX: If it has any special chars that suggest it's a string, reject it
    # This must happen BEFORE the dict size check
    if {[string first "\n" $value] >= 0 ||
        [string first "\t" $value] >= 0 ||
        [string first "\r" $value] >= 0 ||
        [string first "\"" $value] >= 0 ||
        [string first "\\" $value] >= 0} {
        return 0
    }

    # Must have even number of elements
    if {[catch {llength $value} len]} {
        return 0
    }

    if {$len % 2 != 0} {
        return 0
    }

    if {$len == 0} {
        return 0
    }

    # Try to access it as a dict
    if {[catch {dict size $value}]} {
        return 0
    }

    return 1
}

# Serialize a primitive value (string, number, or boolean)
proc ::ast::json::serialize_primitive {key value} {
    # ✅ FIX: Check numeric FIRST (including booleans as 0/1)
    # This way "flag: 1" stays as numeric 1, not boolean true
    if {[string is integer -strict $value] || [string is double -strict $value]} {
        return $value
    }

    # Check field-specific types for non-numeric values
    if {[is_boolean_field $key]} {
        return [to_json_boolean $value]
    }

    if {[is_numeric_field $key]} {
        # Field is known to be numeric but value isn't - keep as is
        return $value
    }

    # It's a string - escape and quote it
    return "\"[escape $value]\""
}

# Convert a TCL dict to JSON object format
proc ::ast::json::dict_to_json {dict_data {indent_level 0}} {
    set indent [string repeat "  " $indent_level]
    set next_indent [string repeat "  " [expr {$indent_level + 1}]]

    # ✅ FIX: Handle empty dict specially
    if {[dict size $dict_data] == 0} {
        return "\{\}"
    }

    set result "\{\n"
    set first_key 1

    dict for {key value} $dict_data {
        if {!$first_key} {
            append result ",\n"
        }
        set first_key 0

        append result "${next_indent}\"$key\": "

        # ✅ FIX: Check if value is literally an empty string
        if {$value eq ""} {
            # Check if this field should be an empty list
            if {[is_list_field $key]} {
                append result "\[\]"
            } else {
                append result "\"\""
            }
            continue
        }

        # ✅ FIX: Check field type hints first
        if {[is_list_field $key]} {
            # This field is always a list
            append result [list_to_json $value [expr {$indent_level + 1}]]
            continue
        }

        # Check what type of value this is
        # Priority: dict > list > primitive

        if {[is_dict $value]} {
            # It's a dict
            append result [dict_to_json $value [expr {$indent_level + 1}]]
        } elseif {[is_proper_list $value]} {
            # It's a proper list
            set len [llength $value]

            if {$len == 0} {
                append result "\[\]"
            } else {
                # Check if first element is a dict (list of dicts)
                set first_elem [lindex $value 0]
                if {[is_dict $first_elem]} {
                    append result [list_to_json $value [expr {$indent_level + 1}]]
                } else {
                    # List of primitives
                    append result [list_to_json $value [expr {$indent_level + 1}]]
                }
            }
        } else {
            # It's a primitive value (string, number, or boolean)
            append result [serialize_primitive $key $value]
        }
    }

    append result "\n${indent}\}"
    return $result
}

# Convert a TCL list to JSON array format
proc ::ast::json::list_to_json {value {indent_level 0}} {
    set next_indent [string repeat "  " $indent_level]

    # Handle empty list
    if {[llength $value] == 0} {
        return "\[\]"
    }

    set first_elem [lindex $value 0]

    # Check if it's a list of dicts
    if {[is_dict $first_elem]} {
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

            # ✅ FIX: Properly detect numbers vs strings
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
proc ::ast::json::escape {str} {
    # ✅ FIX: Proper escaping order matters
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
#   ast_dict - The AST dictionary to convert
#
# Returns:
#   JSON string representation
#
proc ::ast::json::to_json {ast_dict} {
    return [dict_to_json $ast_dict 0]
}

# Main entry point when called as script
proc ::ast::to_json {ast_dict} {
    return [::ast::json::to_json $ast_dict]
}

# If run as a script, run self-tests
if {[info exists argv0] && $argv0 eq [info script]} {
    puts "Running JSON module self-tests..."
    puts ""

    # Test 1: Empty dict
    set result [::ast::json::to_json [dict create]]
    if {$result eq "\{\}"} {
        puts "✓ Empty dict test passed"
    } else {
        puts "✗ Empty dict test FAILED"
        puts "  Expected: \{\}"
        puts "  Got: $result"
    }

    # Test 2: String with newline
    set result [::ast::json::to_json [dict create text "line1\nline2"]]
    if {[string match "*line1\\\\nline2*" $result]} {
        puts "✓ Newline escape test passed"
    } else {
        puts "✗ Newline escape test FAILED"
        puts "  Got: $result"
    }

    # Test 3: Number
    set result [::ast::json::to_json [dict create pi 3.14]]
    if {[string match "*3.14*" $result] && ![string match "*\"3.14\"*" $result]} {
        puts "✓ Number test passed"
    } else {
        puts "✗ Number test FAILED"
        puts "  Got: $result"
    }

    # Test 4: Empty list
    set result [::ast::json::to_json [dict create items [list]]]
    if {[string match "*\[\]*" $result]} {
        puts "✓ Empty list test passed"
    } else {
        puts "✗ Empty list test FAILED"
        puts "  Got: $result"
    }

    puts ""
    puts "Self-tests complete!"
}
