#!/usr/bin/env tclsh
# tcl/core/ast/json.tcl
# JSON Serialization Module for TCL AST - CRITICAL BUG FIX
#
# CRITICAL FIX: is_dict function was rejecting valid dicts that contained
# values with quotes/backslashes. This caused children arrays to serialize
# as arrays of strings instead of arrays of objects.
#
# BUG LOCATION: list_to_json calls is_dict on first element
# - If is_dict returns false, treats list as primitives (strings)
# - If is_dict returns true, treats list as objects (dicts)
#
# ROOT CAUSE: is_dict rejected dicts with special chars in values
# - Dict: {type "set" var_name "x" value {"hello"}}
# - Contains: {\"hello\"} which has backslash and quote
# - Old is_dict: REJECTED (returned 0) - thought it was a string
# - New is_dict: ACCEPTS (returns 1) - recognizes it's a dict
#
# RESULT: children now serialize as JSON objects, not strings!

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
proc ::ast::json::is_proper_list {value} {
    # Empty string is not a list
    if {$value eq ""} {
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
    return 1
}

# Check if a value is a dict (safe detection)
# 🔧 CRITICAL FIX: Removed overly aggressive special character check
#
# OLD VERSION (BROKEN):
#   if {[string first "\n" $value] >= 0 || [string first "\"" $value] >= 0 ...} {
#       return 0  # ❌ Rejected dicts with special chars in values!
#   }
#
# NEW VERSION (FIXED):
#   Rely on TCL's dict size command, which is the authoritative check
#   Don't reject based on content - TCL dicts can have ANY string values
#
proc ::ast::json::is_dict {value} {
    # Empty is not a dict
    if {$value eq ""} {
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

    # 🔧 CRITICAL FIX: This is the ONLY reliable check
    # If TCL can treat it as a dict, it IS a dict
    # Don't second-guess TCL's dict implementation
    if {[catch {dict size $value}]} {
        return 0
    }

    # ✅ If we get here, TCL confirms it's a valid dict
    return 1
}

# Serialize a primitive value (string, number, or boolean)
proc ::ast::json::serialize_primitive {key value} {
    # Check numeric FIRST
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

    # Handle empty dict specially
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

        # Check if value is literally an empty string
        if {$value eq ""} {
            # Check if this field should be an empty list
            if {[is_list_field $key]} {
                append result "\[\]"
            } else {
                append result "\"\""
            }
            continue
        }

        # Check field type hints first
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
# 🔧 This function now works correctly because is_dict is fixed
proc ::ast::json::list_to_json {value {indent_level 0}} {
    set next_indent [string repeat "  " $indent_level]

    # Handle empty list
    if {[llength $value] == 0} {
        return "\[\]"
    }

    set first_elem [lindex $value 0]

    # 🔧 CRITICAL: This check now works correctly!
    # Before: is_dict returned 0 for dicts with special chars
    # After: is_dict returns 1 for all valid dicts
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

            # Properly detect numbers vs strings
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

    # 🔧 CRITICAL NEW TEST: List of dicts with special chars
    puts ""
    puts "🔧 CRITICAL BUG FIX TEST:"
    set child [dict create \
        type "set" \
        var_name "x" \
        value {"hello"}]
    set ast [dict create \
        type "root" \
        children [list $child]]
    set result [::ast::json::to_json $ast]

    if {[string match "*\"children\": \[\n    \{*\"type\": \"set\"*" $result]} {
        puts "✓ List of dicts with special chars test PASSED!"
        puts "  Children correctly serialized as array of objects"
    } else {
        puts "✗ List of dicts with special chars test FAILED"
        puts "  Got: [string range $result 0 200]..."
    }

    puts ""
    puts "Self-tests complete!"
}
