#!/usr/bin/env tclsh
# tcl/core/ast_builder.tcl
# AST Builder - Parses TCL code and builds Abstract Syntax Tree

namespace eval ::ast {
    variable line_number 1
    variable column_number 1
    variable current_file "<string>"
}

# Create position range
proc ::ast::make_range {start_line start_col end_line end_col} {
    return [dict create \
        start [dict create line $start_line column $start_col] \
        end [dict create line $end_line column $end_col]]
}

# Build AST from TCL code
proc ::ast::build {code {filepath "<string>"}} {
    variable current_file
    set current_file $filepath

    # Initialize root node
    set ast [dict create \
        type "root" \
        filepath $filepath \
        children [list]]

    # Split code into lines for processing
    set lines [split $code "\n"]
    set line_num 1
    set in_comment 0

    foreach line $lines {
        set trimmed [string trim $line]

        # Skip empty lines
        if {$trimmed eq ""} {
            incr line_num
            continue
        }

        # Handle comments
        if {[string index $trimmed 0] eq "#"} {
            set comment_node [parse_comment $line $line_num]
            dict lappend ast children $comment_node
            incr line_num
            continue
        }

        # Try to identify command type
        set cmd_type [lindex $trimmed 0]

        switch -glob -- $cmd_type {
            "proc" {
                if {[catch {set proc_node [parse_proc $line $line_num]} err]} {
                    # On error, create error node
                    dict lappend ast children [dict create \
                        type "error" \
                        message $err \
                        range [make_range $line_num 1 $line_num [string length $line]]]
                } else {
                    dict lappend ast children $proc_node
                }
            }
            "set" - "variable" {
                set var_node [parse_variable $line $line_num]
                dict lappend ast children $var_node
            }
            "namespace" {
                set ns_node [parse_namespace $line $line_num]
                dict lappend ast children $ns_node
            }
            "package" {
                set pkg_node [parse_package $line $line_num]
                dict lappend ast children $pkg_node
            }
            "if" - "while" - "for" - "foreach" - "switch" {
                set ctrl_node [parse_control_flow $line $line_num $cmd_type]
                dict lappend ast children $ctrl_node
            }
            default {
                set cmd_node [parse_generic_command $line $line_num]
                dict lappend ast children $cmd_node
            }
        }

        incr line_num
    }

    return $ast
}

# Parse comment line
proc ::ast::parse_comment {line line_num} {
    return [dict create \
        type "comment" \
        text [string range $line 1 end] \
        range [make_range $line_num 1 $line_num [string length $line]]]
}

# Parse procedure definition
proc ::ast::parse_proc {line line_num} {
    # Try to extract proc components using regexp
    # Format: proc name {params} {body}
    if {![regexp {^\s*proc\s+(\S+)\s+\{([^\}]*)\}\s+\{(.*)$} $line -> name params body_start]} {
        # Try simpler pattern
        if {![regexp {^\s*proc\s+(\S+)\s+\{([^\}]*)\}} $line -> name params]} {
            error "Invalid proc syntax"
        }
        set body_start ""
    }

    # Parse parameters
    set param_list [list]
    foreach param_def [split $params] {
        set param_def [string trim $param_def]
        if {$param_def eq ""} {
            continue
        }

        # Check if it has default value
        if {[llength $param_def] == 2} {
            lappend param_list [dict create \
                name [lindex $param_def 0] \
                default [lindex $param_def 1]]
        } elseif {[llength $param_def] == 1} {
            set pname $param_def
            set param_dict [dict create name $pname]
            # Check for 'args' (varargs)
            if {$pname eq "args"} {
                dict set param_dict is_varargs true
            }
            lappend param_list $param_dict
        }
    }

    return [dict create \
        type "proc" \
        name $name \
        params $param_list \
        body [dict create type "body" text $body_start] \
        range [make_range $line_num 1 $line_num [string length $line]]]
}

# Parse variable assignment
proc ::ast::parse_variable {line line_num} {
    # Extract: set var_name value  OR  variable var_name value
    if {[regexp {^\s*(set|variable)\s+(\S+)\s*(.*)$} $line -> cmd var_name value]} {
        return [dict create \
            type "variable" \
            command $cmd \
            name $var_name \
            value $value \
            range [make_range $line_num 1 $line_num [string length $line]]]
    }

    return [dict create \
        type "variable" \
        range [make_range $line_num 1 $line_num [string length $line]]]
}

# Parse namespace command
proc ::ast::parse_namespace {line line_num} {
    if {[regexp {^\s*namespace\s+eval\s+(\S+)} $line -> name]} {
        return [dict create \
            type "namespace" \
            subtype "eval" \
            name $name \
            range [make_range $line_num 1 $line_num [string length $line]]]
    }

    if {[regexp {^\s*namespace\s+import\s+(.+)$} $line -> patterns]} {
        return [dict create \
            type "namespace" \
            subtype "import" \
            patterns [split $patterns] \
            range [make_range $line_num 1 $line_num [string length $line]]]
    }

    return [dict create \
        type "namespace" \
        range [make_range $line_num 1 $line_num [string length $line]]]
}

# Parse package command
proc ::ast::parse_package {line line_num} {
    if {[regexp {^\s*package\s+require\s+(\S+)\s*(\S*)$} $line -> pkgname version]} {
        return [dict create \
            type "package" \
            subtype "require" \
            package_name $pkgname \
            version $version \
            range [make_range $line_num 1 $line_num [string length $line]]]
    }

    if {[regexp {^\s*package\s+provide\s+(\S+)\s*(\S*)$} $line -> pkgname version]} {
        return [dict create \
            type "package" \
            subtype "provide" \
            package_name $pkgname \
            version $version \
            range [make_range $line_num 1 $line_num [string length $line]]]
    }

    return [dict create \
        type "package" \
        range [make_range $line_num 1 $line_num [string length $line]]]
}

# Parse control flow structures
proc ::ast::parse_control_flow {line line_num cmd_type} {
    return [dict create \
        type "control_flow" \
        subtype $cmd_type \
        range [make_range $line_num 1 $line_num [string length $line]]]
}

# Parse generic command
proc ::ast::parse_generic_command {line line_num} {
    set parts [split [string trim $line]]
    set cmd_name [lindex $parts 0]

    return [dict create \
        type "command" \
        name $cmd_name \
        range [make_range $line_num 1 $line_num [string length $line]]]
}

# Convert dict to JSON
proc ::ast::dict_to_json {d {indent 0}} {
    set ind [string repeat " " $indent]
    set items [list]

    dict for {key value} $d {
        set json_key "\"$key\""

        # Handle different value types
        if {[string is integer -strict $value] || [string is double -strict $value]} {
            set json_value $value
        } elseif {[string is boolean -strict $value]} {
            set json_value [expr {$value ? "true" : "false"}]
        } elseif {[string is list $value] && [llength $value] > 0} {
            # Check if it's a dict or list
            if {[llength $value] % 2 == 0} {
                set first [lindex $value 0]
                # If first element looks like a key, treat as dict
                if {[regexp {^[a-zA-Z_]} $first]} {
                    set json_value [dict_to_json $value [expr {$indent + 2}]]
                } else {
                    set json_value [list_to_json $value [expr {$indent + 2}]]
                }
            } else {
                set json_value [list_to_json $value [expr {$indent + 2}]]
            }
        } else {
            # String value - escape special characters
            set escaped [string map {
                \\  \\\\
                \"  \\\"
                \n  \\n
                \r  \\r
                \t  \\t
            } $value]
            set json_value "\"$escaped\""
        }

        lappend items "$ind  $json_key: $json_value"
    }

    return "\{\n[join $items ",\n"]\n$ind\}"
}

# Convert list to JSON array
proc ::ast::list_to_json {lst {indent 0}} {
    set ind [string repeat " " $indent]
    set items [list]

    foreach item $lst {
        if {[string is list $item] && [llength $item] % 2 == 0} {
            lappend items [dict_to_json $item [expr {$indent + 2}]]
        } elseif {[string is integer -strict $item] || [string is double -strict $item]} {
            lappend items $item
        } else {
            set escaped [string map {
                \\  \\\\
                \"  \\\"
                \n  \\n
                \r  \\r
                \t  \\t
            } $item]
            lappend items "\"$escaped\""
        }
    }

    return "\[\n$ind  [join $items ",\n$ind  "]\n$ind\]"
}

# Convert AST to JSON string
proc ::ast::to_json {ast} {
    return [dict_to_json $ast 0]
}
