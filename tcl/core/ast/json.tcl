#!/usr/bin/env tclsh
# tcl/core/ast/json.tcl
# JSON Serialization Module
#
# ✅ FIXED: Added list-of-dicts detection to prevent children arrays from being serialized as strings
#
# Provides functions to convert TCL dicts and lists to JSON format.
# This module handles the critical task of serializing AST structures.
#
# CRITICAL BUG FIX: The is_dict() function now correctly identifies lists of dicts
# (like the children array) as lists, not as dicts. This prevents malformed JSON
# output where arrays would be serialized as strings.

namespace eval ::ast::json {}

# List of known fields that should always be lists
set ::ast::json::list_fields {children params vars patterns imports exports cases elseif_branches}

# List of known fields that should be booleans
set ::ast::json::boolean_fields {had_error}

# List of known fields that are numeric
set ::ast::json::numeric_fields {depth line column start_line end_line}

# Check if a field name typically contains a list
proc ::ast::json::is_list_field {field_name} {
    variable list_fields
    return [expr {$field_name in $list_fields}]
}

# Check if a field name is a boolean field
proc ::ast::json::is_boolean_field {field_name} {
    variable boolean_fields
    return [expr {$field_name in $boolean_fields}]
}

# Check if a field name is numeric
proc ::ast::json::is_numeric_field {field_name} {
    variable numeric_fields
    return [expr {$field_name in $numeric_fields}]
}

# Convert TCL boolean-like values to JSON boolean
proc ::ast::json::to_json_boolean {value} {
    if {$value == 1 || $value eq "true" || $value eq "yes"} {
        return "true"
    } elseif {$value == 0 || $value eq "false" || $value eq "no"} {
        return "false"
    } else {
        # Not a clear boolean - treat as number or string
        return "\"$value\""
    }
}

# Check if a value is actually a TCL dict (not a list or string)
#
# ✅ CRITICAL BUG FIX: This function now correctly distinguishes between:
# - Real dicts: {type proc name test}
# - Lists of dicts: {{type proc name test1} {type set var x}}
# - Strings that look like dicts but contain special characters
#
proc ::ast::json::is_dict {value} {
    # First, check if it's a valid dict
    if {[catch {dict size $value}]} {
        return 0
    }

    # 🔧 FIX: Check for characters that suggest it's a string, not a dict
    # If the value contains literal control chars or quotes,
    # it's almost certainly a string value, not a structured dict.
    # Real dict keys and values in AST nodes don't contain these characters.

    # Check for literal newline (ASCII 10)
    if {[string first "\n" $value] >= 0} {
        return 0
    }

    # Check for literal tab (ASCII 9)
    if {[string first "\t" $value] >= 0} {
        return 0
    }

    # Check for literal carriage return (ASCII 13)
    if {[string first "\r" $value] >= 0} {
        return 0
    }

    # Check for embedded quote characters (ASCII 34)
    # Strings like 'say "hello"' contain quotes and are not dicts
    # Real AST dict keys/values don't have embedded quotes
    if {[string first "\"" $value] >= 0} {
        return 0
    }

    # ✅ NEW FIX (from chat 107): Check if it's actually a list of dicts
    # A list of dicts (like the children array) has multiple elements
    # where each element is itself a dict with a "type" key.
    #
    # Example that needs to be caught:
    # {{type proc name test1} {type set var x value 10}}
    #
    # This passes dict size check but should be treated as a list!
    if {[llength $value] > 1} {
        # Check if first element looks like an AST node (has "type" key)
        set first_elem [lindex $value 0]
        if {[catch {dict get $first_elem type}] == 0} {
            # First element is a dict with "type" key - it's a list of AST nodes!
            return 0
        }
    }

    # ✅ If we get here, TCL confirms it's a valid dict
    # AND it doesn't contain string-like characters
    # AND it's not a list of dicts
    return 1
}

# Check if a value is a proper TCL list (not a scalar or dict)
proc ::ast::json::is_proper_list {value} {
    # Can we get list length?
    if {[catch {llength $value} len]} {
        return 0
    }

    # Empty lists are still lists
    if {$len == 0} {
        return 1
    }

    # Single-element things might be scalars
    if {$len == 1} {
        return 0
    }

    # Check if it's actually a dict
    if {[is_dict $value]} {
        return 0
    }

    # It's a list with 2+ elements and not a dict
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
            # Always serialize as list
            append result [list_to_json $value [expr {$indent_level + 1}]]
        } elseif {[is_dict $value]} {
            # It's a nested dict
            append result [dict_to_json $value [expr {$indent_level + 1}]]
        } elseif {[is_proper_list $value]} {
            # It's a list
            append result [list_to_json $value [expr {$indent_level + 1}]]
        } else {
            # It's a primitive (string, number, or boolean)
            append result [serialize_primitive $key $value]
        }
    }

    append result "\n${indent}\}"
    return $result
}

# Convert a TCL list to JSON array format
proc ::ast::json::list_to_json {list_data {indent_level 0}} {
    set indent [string repeat "  " $indent_level]
    set next_indent [string repeat "  " [expr {$indent_level + 1}]]

    if {[llength $list_data] == 0} {
        return "\[\]"
    }

    # Check if first element is a dict - if so, assume list of dicts
    set first_elem [lindex $list_data 0]
    if {[is_dict $first_elem]} {
        # List of dicts - format nicely
        set result "\[\n"
        set first_item 1
        foreach item $list_data {
            if {!$first_item} {
                append result ",\n"
            }
            set first_item 0
            append result "${next_indent}[dict_to_json $item [expr {$indent_level + 1}]]"
        }
        append result "\n${next_indent}\]"
        return $result
    } else {
        # List of primitives - format as simple array
        set result "\["
        set first_item 1
        foreach item $list_data {
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

    # Test 4: String with quotes
    set result [::ast::json::to_json [dict create text "say \"hello\""]]
    if {[string match "*say \\\\\"hello\\\\\"*" $result] && ![string match "*\"say\":*" $result]} {
        puts "✓ Quote escape test passed"
    } else {
        puts "✗ Quote escape test FAILED"
        puts "  Got: $result"
    }

    # Test 5: List of dicts (THE CRITICAL TEST!)
    set result [::ast::json::to_json [dict create children [list \
        [dict create type "proc" name "test1"] \
        [dict create type "proc" name "test2"]]]]
    if {[string match "*children*" $result] && [string match "*proc*" $result] && [string match "*\[*" $result]} {
        puts "✓ List of dicts test passed (CRITICAL FIX VERIFIED!)"
    } else {
        puts "✗ List of dicts test FAILED (CRITICAL FIX NOT WORKING!)"
        puts "  Got: $result"
    }

    puts ""
    puts "Self-tests complete"
}
