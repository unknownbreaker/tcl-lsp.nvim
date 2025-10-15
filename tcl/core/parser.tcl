#!/usr/bin/env tclsh
# tcl/core/parser.tcl
# TCL Parser - Uses TCL's built-in parser to build AST
# Outputs JSON representation of the AST

# Load the AST builder
set script_dir [file dirname [info script]]
source [file join $script_dir ast_builder.tcl]

# Simple JSON encoder
proc dict_to_json {dict} {
    set items [list]
    dict for {key value} $dict {
        set json_key "\"$key\""

        if {[string is list $value] && [llength $value] > 0} {
            # Check if it's a dict (even number of elements with string keys)
            if {[llength $value] % 2 == 0} {
                set first [lindex $value 0]
                if {[string is alpha [string index $first 0]]} {
                    # Likely a dict
                    set json_value [dict_to_json $value]
                } else {
                    # List of values
                    set json_value "\[[list_to_json $value]\]"
                }
            } else {
                # Odd number - treat as list
                set json_value "\[[list_to_json $value]\]"
            }
        } elseif {[string is integer $value] || [string is double $value]} {
            set json_value $value
        } elseif {$value eq "true" || $value eq "false"} {
            set json_value $value
        } else {
            set json_value "\"[string map {\" \\\" \\ \\\\ \n \\n \r \\r \t \\t} $value]\""
        }

        lappend items "$json_key: $json_value"
    }

    return "\{[join $items ", "]\}"
}

proc list_to_json {list} {
    set items [list]
    foreach item $list {
        if {[string is list $item] && [llength $item] > 0 && [llength $item] % 2 == 0} {
            lappend items [dict_to_json $item]
        } elseif {[string is integer $item] || [string is double $item]} {
            lappend items $item
        } elseif {$item eq "true" || $item eq "false"} {
            lappend items $item
        } else {
            lappend items "\"[string map {\" \\\" \\ \\\\ \n \\n \r \\r \t \\t} $item]\""
        }
    }
    return [join $items ", "]
}

# Main entry point
proc parse_file {filepath} {
    # Read file content
    if {![file readable $filepath]} {
        error "File not readable: $filepath"
    }

    set fp [open $filepath r]
    set content [read $fp]
    close $fp

    # Parse content and build AST
    set ast [::ast::build $content $filepath]

    # Convert to JSON and output
    puts [dict_to_json $ast]
}

# Check command line arguments
if {$argc != 1} {
    puts stderr "Usage: $argv0 <tcl_file>"
    exit 1
}

set filepath [lindex $argv 0]

# Parse file and handle errors
if {[catch {parse_file $filepath} error]} {
    puts stderr "Parse error: $error"
    exit 1
}

exit 0
