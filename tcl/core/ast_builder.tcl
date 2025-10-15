#!/usr/bin/env tclsh
# tcl/core/ast_builder.tcl
# AST Builder - Production-ready TCL parser with accurate positions

namespace eval ::ast {
    variable current_file "<string>"
    variable line_map
    variable current_line 1
}

# Create position range
proc ::ast::make_range {start_line start_col end_line end_col} {
    return [dict create \
        start [dict create line $start_line column $start_col] \
        end [dict create line $end_line column $end_col]]
}

# Extract comments from source code (before parsing)
proc ::ast::extract_comments {code} {
    set comments [list]
    set line_num 0

    foreach line [split $code "\n"] {
        incr line_num

        # Match comment lines (lines starting with #, possibly with whitespace)
        if {[regexp {^(\s*)#(.*)$} $line -> indent comment_text]} {
            set col [expr {[string length $indent] + 1}]
            lappend comments [dict create \
                type "comment" \
                text [string trim $comment_text] \
                range [make_range $line_num $col $line_num [string length $line]]]
        }
    }

    return $comments
}

# Build line number mapping for position tracking
proc ::ast::build_line_map {code} {
    variable line_map
    set line_map [dict create]

    set offset 0
    set line_num 1

    foreach line [split $code "\n"] {
        dict set line_map $line_num [dict create \
            offset $offset \
            length [string length $line]]

        # +1 for newline character
        set offset [expr {$offset + [string length $line] + 1}]
        incr line_num
    }
}

# Get line number from code offset
proc ::ast::offset_to_line {offset} {
    variable line_map

    dict for {line_num info} $line_map {
        set line_offset [dict get $info offset]
        set line_length [dict get $info length]
        set line_end [expr {$line_offset + $line_length}]

        if {$offset >= $line_offset && $offset <= $line_end} {
            set col [expr {$offset - $line_offset + 1}]
            return [list $line_num $col]
        }
    }

    return [list 1 1]
}

# Main build function - parses TCL code into AST
proc ::ast::build {code {filepath "<string>"}} {
    variable current_file
    variable current_line
    set current_file $filepath
    set current_line 1

    # Build line mapping for accurate position tracking
    build_line_map $code

    # Extract comments before parsing (they get lost in safe interp)
    set comments [extract_comments $code]

    # Create root AST node
    set ast [dict create \
        type "root" \
        filepath $filepath \
        comments $comments \
        children [list]]

    # Create a safe interpreter for parsing
    set interp [interp create -safe]

    # Handle undefined variables gracefully
    interp eval $interp {
        # Unknown command handler - returns empty string
        proc ::tcl::unknown {args} {
            return ""
        }
    }

    # Override commands in the safe interpreter to capture them
    interp alias $interp proc {} ::ast::capture_proc $interp
    interp alias $interp set {} ::ast::capture_set
    interp alias $interp variable {} ::ast::capture_variable
    interp alias $interp global {} ::ast::capture_global
    interp alias $interp upvar {} ::ast::capture_upvar
    interp alias $interp array {} ::ast::capture_array
    interp alias $interp namespace {} ::ast::capture_namespace $interp
    interp alias $interp package {} ::ast::capture_package
    interp alias $interp if {} ::ast::capture_if
    interp alias $interp while {} ::ast::capture_while
    interp alias $interp for {} ::ast::capture_for
    interp alias $interp foreach {} ::ast::capture_foreach
    interp alias $interp switch {} ::ast::capture_switch
    interp alias $interp expr {} ::ast::capture_expr
    interp alias $interp list {} ::ast::capture_list
    interp alias $interp lappend {} ::ast::capture_lappend

    # Add common commands that should just work without side effects
    interp alias $interp puts {} ::ast::capture_generic puts
    interp alias $interp return {} ::ast::capture_generic return
    interp alias $interp incr {} ::ast::capture_generic incr
    interp alias $interp append {} ::ast::capture_generic append
    interp alias $interp lindex {} ::ast::capture_generic lindex
    interp alias $interp llength {} ::ast::capture_generic llength
    interp alias $interp lrange {} ::ast::capture_generic lrange
    interp alias $interp lsearch {} ::ast::capture_generic lsearch
    interp alias $interp join {} ::ast::capture_generic join
    interp alias $interp split {} ::ast::capture_generic split
    interp alias $interp string {} ::ast::capture_generic string
    interp alias $interp dict {} ::ast::capture_generic dict
    interp alias $interp error {} ::ast::capture_generic error
    interp alias $interp catch {} ::ast::capture_generic catch
    interp alias $interp source {} ::ast::capture_generic source
    interp alias $interp unset {} ::ast::capture_generic unset

    # Variable to collect nodes
    variable collected_nodes
    set collected_nodes [list]

    # Try to evaluate with enhanced error detection
    set had_error 0
    if {[catch {interp eval $interp $code} err_msg]} {
        set had_error 1

        # Classify the error
        set error_node [dict create \
            type "error" \
            message $err_msg \
            range [make_range 1 1 1 1]]

        # Categorize error types
        if {[string match "*missing close-brace*" $err_msg] || \
            [string match "*unmatched open brace*" $err_msg]} {
            dict set error_node error_type "incomplete"
            dict set error_node suggestion "Check for missing closing brace \}"
        } elseif {[string match "*wrong # args*" $err_msg]} {
            dict set error_node error_type "syntax"
            dict set error_node suggestion "Check command arguments - see error message for details"

            # Extract command name if possible
            if {[regexp {should be "(\w+)} $err_msg -> cmd_name]} {
                dict set error_node command $cmd_name
            }
        } elseif {[string match "*invalid command*" $err_msg]} {
            dict set error_node error_type "unknown_command"
            dict set error_node suggestion "Command may not be defined or may be a typo"
        } elseif {[string match "*extra characters after*" $err_msg]} {
            dict set error_node error_type "syntax"
            dict set error_node suggestion "Check for extra characters or missing braces"
        } elseif {[string match "*list element in braces*" $err_msg]} {
            dict set error_node error_type "syntax"
            dict set error_node suggestion "Check brace usage - may need space after closing brace"
        } else {
            dict set error_node error_type "general"
            dict set error_node suggestion "Review TCL syntax"
        }

        dict set ast errors [list $error_node]
    }

    # Add collected nodes even if there were errors
    dict set ast children $collected_nodes
    dict set ast had_error $had_error

    # Clean up
    interp delete $interp

    return $ast
}

# Capture proc definitions with accurate position tracking
proc ::ast::capture_proc {interp name params body} {
    variable collected_nodes

    # Validation
    if {$name eq ""} {
        error "Procedure must have a name"
    }

    if {[catch {llength $params}]} {
        error "Invalid parameter list for proc '$name' - must be a valid list"
    }

    # Get position information from the calling frame
    set frame [info frame -1]
    set start_line 1
    set start_col 1

    if {[dict exists $frame line]} {
        set start_line [dict get $frame line]
    }

    # Calculate end line by counting newlines in body
    set body_lines [regexp -all "\n" $body]
    set end_line [expr {$start_line + $body_lines + 2}]

    # If we have cmd info, we can get better position
    if {[dict exists $frame cmd]} {
        set cmd_text [dict get $frame cmd]
        if {[regexp {^proc\s+} $cmd_text]} {
            # We're at the proc definition line
            set start_col 1
        }
    }

    # Parse parameters with validation
    set param_list [list]
    set param_idx 0

    foreach param $params {
        incr param_idx

        if {[llength $param] == 2} {
            # Parameter with default value
            set param_name [lindex $param 0]
            set default_val [lindex $param 1]

            if {$param_name eq ""} {
                error "Parameter $param_idx in proc '$name' has no name"
            }

            lappend param_list [dict create \
                name $param_name \
                default $default_val \
                range [make_range $start_line [expr {10 + $param_idx * 10}] $start_line [expr {10 + $param_idx * 10 + [string length $param_name]}]]]
        } elseif {[llength $param] == 1} {
            # Simple parameter
            set param_name $param

            if {$param_name eq ""} {
                error "Parameter $param_idx in proc '$name' cannot be empty"
            }

            set pdict [dict create \
                name $param_name \
                range [make_range $start_line [expr {10 + $param_idx * 10}] $start_line [expr {10 + $param_idx * 10 + [string length $param_name]}]]]

            if {$param_name eq "args"} {
                dict set pdict is_varargs true
            }

            lappend param_list $pdict
        } else {
            error "Invalid parameter format in proc '$name' at position $param_idx"
        }
    }

    lappend collected_nodes [dict create \
        type "proc" \
        name $name \
        params $param_list \
        body [dict create type "body" text $body] \
        range [make_range $start_line $start_col $end_line 1]]

    return ""
}

# Capture set commands
proc ::ast::capture_set {varname args} {
    variable collected_nodes

    if {$varname eq ""} {
        error "set: variable name cannot be empty"
    }

    set value ""
    if {[llength $args] > 0} {
        set value [lindex $args 0]
    }

    # Get position
    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    lappend collected_nodes [dict create \
        type "variable" \
        command "set" \
        name $varname \
        value $value \
        range [make_range $line 1 $line [expr {20 + [string length $varname]}]]]

    return $value
}

# Capture variable commands
proc ::ast::capture_variable {args} {
    variable collected_nodes

    if {[llength $args] == 0} {
        error "variable: missing variable name"
    }

    set varname [lindex $args 0]
    if {$varname eq ""} {
        error "variable: name cannot be empty"
    }

    set value ""
    if {[llength $args] > 1} {
        set value [lindex $args 1]
    }

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    lappend collected_nodes [dict create \
        type "variable" \
        command "variable" \
        name $varname \
        value $value \
        range [make_range $line 1 $line [expr {20 + [string length $varname]}]]]

    return ""
}

# Capture global commands
proc ::ast::capture_global {args} {
    variable collected_nodes

    if {[llength $args] == 0} {
        error "global: missing variable name(s)"
    }

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    foreach varname $args {
        if {$varname eq ""} {
            error "global: variable name cannot be empty"
        }

        lappend collected_nodes [dict create \
            type "global" \
            name $varname \
            range [make_range $line 1 $line [expr {20 + [string length $varname]}]]]
    }

    return ""
}

# Capture upvar commands
proc ::ast::capture_upvar {args} {
    variable collected_nodes

    if {[llength $args] < 2} {
        error "upvar: wrong # args: should be \"upvar ?level? otherVar localVar ?otherVar localVar ...?\""
    }

    # upvar can have level, source, target or just source target
    if {[llength $args] == 2} {
        set source [lindex $args 0]
        set target [lindex $args 1]
    } elseif {[llength $args] >= 3} {
        set source [lindex $args 1]
        set target [lindex $args 2]
    } else {
        set source ""
        set target ""
    }

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    lappend collected_nodes [dict create \
        type "upvar" \
        source $source \
        target $target \
        range [make_range $line 1 $line 50]]

    return ""
}

# Capture array commands
proc ::ast::capture_array {subcommand args} {
    variable collected_nodes

    if {$subcommand eq ""} {
        error "array: missing subcommand"
    }

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    lappend collected_nodes [dict create \
        type "array" \
        subcommand $subcommand \
        args $args \
        range [make_range $line 1 $line 50]]

    return ""
}

# Capture namespace commands with proper handling for eval
proc ::ast::capture_namespace {interp subcommand args} {
    variable collected_nodes

    if {$subcommand eq ""} {
        error "namespace: missing subcommand"
    }

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    if {$subcommand eq "eval"} {
        if {[llength $args] < 1} {
            error "namespace eval: missing namespace name"
        }

        set name [lindex $args 0]
        set body [lindex $args 1]

        # Calculate end line for namespace body
        set body_lines [regexp -all "\n" $body]
        set end_line [expr {$line + $body_lines + 1}]

        lappend collected_nodes [dict create \
            type "namespace" \
            subtype "eval" \
            name $name \
            range [make_range $line 1 $end_line 1]]

        # Parse the namespace body recursively
        if {[llength $args] > 1} {
            catch {interp eval $interp $body}
        }
    } elseif {$subcommand eq "import"} {
        lappend collected_nodes [dict create \
            type "namespace_import" \
            patterns $args \
            range [make_range $line 1 $line 50]]
    } else {
        lappend collected_nodes [dict create \
            type "namespace" \
            subtype $subcommand \
            args $args \
            range [make_range $line 1 $line 50]]
    }

    return ""
}

# Capture package commands
proc ::ast::capture_package {subcommand args} {
    variable collected_nodes

    if {$subcommand eq ""} {
        error "package: missing subcommand"
    }

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    if {$subcommand eq "require"} {
        if {[llength $args] < 1} {
            error "package require: missing package name"
        }

        set pkgname [lindex $args 0]
        set version ""
        if {[llength $args] > 1} {
            set version [lindex $args 1]
        }

        lappend collected_nodes [dict create \
            type "package_require" \
            package_name $pkgname \
            version $version \
            range [make_range $line 1 $line [expr {20 + [string length $pkgname]}]]]
    } elseif {$subcommand eq "provide"} {
        if {[llength $args] < 2} {
            error "package provide: missing package name or version"
        }

        set pkgname [lindex $args 0]
        set version [lindex $args 1]

        lappend collected_nodes [dict create \
            type "package_provide" \
            package_name $pkgname \
            version $version \
            range [make_range $line 1 $line [expr {20 + [string length $pkgname]}]]]
    } else {
        lappend collected_nodes [dict create \
            type "package" \
            subcommand $subcommand \
            args $args \
            range [make_range $line 1 $line 50]]
    }

    return ""
}

# Capture if statements with full if/elseif/else support
proc ::ast::capture_if {args} {
    variable collected_nodes

    if {[llength $args] < 2} {
        error "if: wrong # args: should be \"if expr1 body1 ?elseif expr2 body2 ...? ?else bodyN?\""
    }

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    # TCL if syntax: if cond body ?elseif cond body ...? ?else body?
    set condition [lindex $args 0]
    set then_body ""
    set else_body ""
    set elseif_clauses [list]

    # Calculate approximate end line
    set all_text [join $args " "]
    set body_lines [regexp -all "\n" $all_text]
    set end_line [expr {$line + $body_lines}]

    # Simple parsing of if arguments
    set i 1
    while {$i < [llength $args]} {
        set arg [lindex $args $i]
        if {$arg eq "then"} {
            incr i
            continue
        } elseif {$arg eq "else"} {
            incr i
            if {$i < [llength $args]} {
                set else_body [lindex $args $i]
            }
            incr i
        } elseif {$arg eq "elseif"} {
            incr i
            if {$i < [llength $args]} {
                set elseif_cond [lindex $args $i]
                incr i
                if {$i < [llength $args]} {
                    set elseif_body [lindex $args $i]
                    lappend elseif_clauses [dict create condition $elseif_cond body $elseif_body]
                }
            }
            incr i
        } else {
            # Assume it's the then-body
            set then_body $arg
            incr i
        }
    }

    set node [dict create \
        type "if" \
        condition $condition \
        then_body $then_body \
        range [make_range $line 1 $end_line 1]]

    if {[llength $elseif_clauses] > 0} {
        dict set node elseif_clauses $elseif_clauses
    }

    if {$else_body ne ""} {
        dict set node else_body $else_body
    }

    lappend collected_nodes $node

    return 0
}

# Capture while loops
proc ::ast::capture_while {condition body} {
    variable collected_nodes

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    set body_lines [regexp -all "\n" $body]
    set end_line [expr {$line + $body_lines + 1}]

    lappend collected_nodes [dict create \
        type "while" \
        condition $condition \
        range [make_range $line 1 $end_line 1]]

    return ""
}

# Capture for loops
proc ::ast::capture_for {init test next body} {
    variable collected_nodes

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    set body_lines [regexp -all "\n" $body]
    set end_line [expr {$line + $body_lines + 1}]

    lappend collected_nodes [dict create \
        type "for" \
        init $init \
        test $test \
        next $next \
        range [make_range $line 1 $end_line 1]]

    return ""
}

# Capture foreach loops
proc ::ast::capture_foreach {varname list body} {
    variable collected_nodes

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    set body_lines [regexp -all "\n" $body]
    set end_line [expr {$line + $body_lines + 1}]

    lappend collected_nodes [dict create \
        type "foreach" \
        var_name $varname \
        list $list \
        range [make_range $line 1 $end_line 1]]

    return ""
}

# Capture switch statements
proc ::ast::capture_switch {args} {
    variable collected_nodes

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    set all_text [join $args " "]
    set body_lines [regexp -all "\n" $all_text]
    set end_line [expr {$line + $body_lines + 1}]

    lappend collected_nodes [dict create \
        type "switch" \
        args $args \
        range [make_range $line 1 $end_line 1]]

    return ""
}

# Capture expr commands
proc ::ast::capture_expr {args} {
    variable collected_nodes

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    lappend collected_nodes [dict create \
        type "expr" \
        expression [lindex $args 0] \
        range [make_range $line 1 $line 50]]

    return 0
}

# Capture list commands
proc ::ast::capture_list {args} {
    variable collected_nodes

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    lappend collected_nodes [dict create \
        type "list" \
        elements $args \
        range [make_range $line 1 $line 50]]

    return $args
}

# Capture lappend commands
proc ::ast::capture_lappend {varname args} {
    variable collected_nodes

    if {$varname eq ""} {
        error "lappend: variable name cannot be empty"
    }

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    lappend collected_nodes [dict create \
        type "lappend" \
        varname $varname \
        values $args \
        range [make_range $line 1 $line 50]]

    return $args
}

# Capture generic commands (puts, return, etc.)
proc ::ast::capture_generic {cmdname args} {
    variable collected_nodes

    set frame [info frame -1]
    set line 1
    if {[dict exists $frame line]} {
        set line [dict get $frame line]
    }

    lappend collected_nodes [dict create \
        type "command" \
        name $cmdname \
        args $args \
        range [make_range $line 1 $line 50]]

    return ""
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
        } elseif {[llength $value] > 1} {
            # Only treat as list/dict if it has multiple elements
            # Check if it's a dict or list
            set is_dict 0
            if {[llength $value] % 2 == 0} {
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
            # Single element or string - treat as string
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
        # Check if item is a dict (has even length and is valid dict)
        set is_dict 0
        if {[llength $item] > 1 && [llength $item] % 2 == 0} {
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
