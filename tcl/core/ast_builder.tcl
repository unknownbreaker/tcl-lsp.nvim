#!/usr/bin/env tclsh
# tcl/core/ast_builder.tcl
# AST Builder - Parses TCL code using TCL's native parser

namespace eval ::ast {
    variable current_file "<string>"
}

# Create position range
proc ::ast::make_range {start_line start_col end_line end_col} {
    return [dict create \
        start [dict create line $start_line column $start_col] \
        end [dict create line $end_line column $end_col]]
}

# Main build function - parses TCL code into AST
proc ::ast::build {code {filepath "<string>"}} {
    variable current_file
    set current_file $filepath

    # Create root AST node
    set ast [dict create \
        type "root" \
        filepath $filepath \
        children [list]]

    # Create a safe interpreter for parsing
    set interp [interp create -safe]

    # Override commands in the safe interpreter to capture them
    interp alias $interp proc {} ::ast::capture_proc
    interp alias $interp set {} ::ast::capture_set
    interp alias $interp variable {} ::ast::capture_variable
    interp alias $interp global {} ::ast::capture_global
    interp alias $interp upvar {} ::ast::capture_upvar
    interp alias $interp array {} ::ast::capture_array
    interp alias $interp namespace {} ::ast::capture_namespace
    interp alias $interp package {} ::ast::capture_package
    interp alias $interp if {} ::ast::capture_if
    interp alias $interp while {} ::ast::capture_while
    interp alias $interp for {} ::ast::capture_for
    interp alias $interp foreach {} ::ast::capture_foreach
    interp alias $interp switch {} ::ast::capture_switch
    interp alias $interp expr {} ::ast::capture_expr
    interp alias $interp list {} ::ast::capture_list
    interp alias $interp lappend {} ::ast::capture_lappend

    # Variable to collect nodes
    variable collected_nodes
    set collected_nodes [list]

    # Try to evaluate the code in the safe interpreter
    if {[catch {interp eval $interp $code} err]} {
        # If there's an error, create an error node
        dict lappend ast children [dict create \
            type "error" \
            message $err \
            range [make_range 1 1 1 1]]
    }

    # Add collected nodes to AST
    dict set ast children $collected_nodes

    # Clean up
    interp delete $interp

    return $ast
}

# Capture proc definitions
proc ::ast::capture_proc {name params body} {
    variable collected_nodes

    # Parse parameters
    set param_list [list]
    foreach param $params {
        if {[llength $param] == 2} {
            # Parameter with default value
            lappend param_list [dict create \
                name [lindex $param 0] \
                default [lindex $param 1]]
        } else {
            # Simple parameter
            set pdict [dict create name $param]
            if {$param eq "args"} {
                dict set pdict is_varargs true
            }
            lappend param_list $pdict
        }
    }

    lappend collected_nodes [dict create \
        type "proc" \
        name $name \
        params $param_list \
        body [dict create type "body" text $body] \
        range [make_range 1 1 1 100]]
}

# Capture set commands
proc ::ast::capture_set {varname args} {
    variable collected_nodes

    set value ""
    if {[llength $args] > 0} {
        set value [lindex $args 0]
    }

    lappend collected_nodes [dict create \
        type "variable" \
        command "set" \
        name $varname \
        value $value \
        range [make_range 1 1 1 100]]
}

# Capture variable commands
proc ::ast::capture_variable {args} {
    variable collected_nodes

    set varname [lindex $args 0]
    set value ""
    if {[llength $args] > 1} {
        set value [lindex $args 1]
    }

    lappend collected_nodes [dict create \
        type "variable" \
        command "variable" \
        name $varname \
        value $value \
        range [make_range 1 1 1 100]]
}

# Capture global commands
proc ::ast::capture_global {args} {
    variable collected_nodes

    foreach varname $args {
        lappend collected_nodes [dict create \
            type "global" \
            name $varname \
            range [make_range 1 1 1 100]]
    }
}

# Capture upvar commands
proc ::ast::capture_upvar {args} {
    variable collected_nodes

    # upvar can have level, source, target or just source target
    if {[llength $args] == 2} {
        set source [lindex $args 0]
        set target [lindex $args 1]
    } elseif {[llength $args] == 3} {
        set source [lindex $args 1]
        set target [lindex $args 2]
    } else {
        set source ""
        set target ""
    }

    lappend collected_nodes [dict create \
        type "upvar" \
        source $source \
        target $target \
        range [make_range 1 1 1 100]]
}

# Capture array commands
proc ::ast::capture_array {subcommand args} {
    variable collected_nodes

    lappend collected_nodes [dict create \
        type "array" \
        subcommand $subcommand \
        args $args \
        range [make_range 1 1 1 100]]
}

# Capture namespace commands
proc ::ast::capture_namespace {subcommand args} {
    variable collected_nodes

    if {$subcommand eq "eval"} {
        set name [lindex $args 0]
        lappend collected_nodes [dict create \
            type "namespace" \
            subtype "eval" \
            name $name \
            range [make_range 1 1 1 100]]
    } elseif {$subcommand eq "import"} {
        lappend collected_nodes [dict create \
            type "namespace_import" \
            patterns $args \
            range [make_range 1 1 1 100]]
    } else {
        lappend collected_nodes [dict create \
            type "namespace" \
            subtype $subcommand \
            args $args \
            range [make_range 1 1 1 100]]
    }
}

# Capture package commands
proc ::ast::capture_package {subcommand args} {
    variable collected_nodes

    if {$subcommand eq "require"} {
        set pkgname [lindex $args 0]
        set version ""
        if {[llength $args] > 1} {
            set version [lindex $args 1]
        }
        lappend collected_nodes [dict create \
            type "package_require" \
            package_name $pkgname \
            version $version \
            range [make_range 1 1 1 100]]
    } elseif {$subcommand eq "provide"} {
        set pkgname [lindex $args 0]
        set version ""
        if {[llength $args] > 1} {
            set version [lindex $args 1]
        }
        lappend collected_nodes [dict create \
            type "package_provide" \
            package_name $pkgname \
            version $version \
            range [make_range 1 1 1 100]]
    } else {
        lappend collected_nodes [dict create \
            type "package" \
            subcommand $subcommand \
            args $args \
            range [make_range 1 1 1 100]]
    }
}

# Capture if statements
proc ::ast::capture_if {args} {
    variable collected_nodes

    lappend collected_nodes [dict create \
        type "if" \
        condition [lindex $args 0] \
        range [make_range 1 1 1 100]]
}

# Capture while loops
proc ::ast::capture_while {condition body} {
    variable collected_nodes

    lappend collected_nodes [dict create \
        type "while" \
        condition $condition \
        range [make_range 1 1 1 100]]
}

# Capture for loops
proc ::ast::capture_for {init test next body} {
    variable collected_nodes

    lappend collected_nodes [dict create \
        type "for" \
        init $init \
        test $test \
        next $next \
        range [make_range 1 1 1 100]]
}

# Capture foreach loops
proc ::ast::capture_foreach {varname list body} {
    variable collected_nodes

    lappend collected_nodes [dict create \
        type "foreach" \
        var_name $varname \
        list $list \
        range [make_range 1 1 1 100]]
}

# Capture switch statements
proc ::ast::capture_switch {args} {
    variable collected_nodes

    lappend collected_nodes [dict create \
        type "switch" \
        args $args \
        range [make_range 1 1 1 100]]
}

# Capture expr commands
proc ::ast::capture_expr {args} {
    variable collected_nodes

    lappend collected_nodes [dict create \
        type "expr" \
        expression [lindex $args 0] \
        range [make_range 1 1 1 100]]
}

# Capture list commands
proc ::ast::capture_list {args} {
    variable collected_nodes

    lappend collected_nodes [dict create \
        type "list" \
        elements $args \
        range [make_range 1 1 1 100]]
}

# Capture lappend commands
proc ::ast::capture_lappend {varname args} {
    variable collected_nodes

    lappend collected_nodes [dict create \
        type "lappend" \
        varname $varname \
        values $args \
        range [make_range 1 1 1 100]]
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
            set is_dict 0
            if {[llength $value] % 2 == 0 && [llength $value] > 0} {
                if {[catch {dict size $value}] == 0} {
                    set is_dict 1
                }
            }

            if {$is_dict} {
                set json_value [dict_to_json $value [expr {$indent + 2}]]
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
        # Check if item is a dict
        set is_dict 0
        if {[string is list $item] && [llength $item] % 2 == 0 && [llength $item] > 0} {
            if {[catch {dict size $item}] == 0} {
                set is_dict 1
            }
        }

        if {$is_dict} {
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

    if {[llength $items] == 0} {
        return "\[\]"
    }

    return "\[\n$ind  [join $items ",\n$ind  "]\n$ind\]"
}

# Convert AST to JSON string
proc ::ast::to_json {ast} {
    return [dict_to_json $ast 0]
}
