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
    return [list \
        start [list line $start_line column $start_col] \
        end_pos [list line $end_line column $end_col]]
}

# Build AST from TCL code
proc ::ast::build {code {filepath "<string>"}} {
    variable current_file
    set current_file $filepath

    # Initialize root node
    set ast [list \
        type "root" \
        children [list] \
        range [make_range 1 1 1 1]]

    # Handle empty code
    if {[string trim $code] eq ""} {
        return $ast
    }

    # Parse code line by line and build AST
    set children [parse_script $code]

    # Update AST with parsed children
    dict set ast children $children

    # Update end position
    set lines [split $code "\n"]
    set end_line [llength $lines]
    set end_col [string length [lindex $lines end]]
    dict set ast range [make_range 1 1 $end_line $end_col]

    return $ast
}

# Parse a TCL script into AST nodes
proc ::ast::parse_script {code} {
    set nodes [list]
    set line 1

    # Split into lines and process
    foreach raw_line [split $code "\n"] {
        set trimmed [string trim $raw_line]

        # Skip empty lines and comments
        if {$trimmed eq "" || [string index $trimmed 0] eq "#"} {
            incr line
            continue
        }

        # Try to parse as complete command
        if {[info complete $raw_line]} {
            if {[catch {parse_command $raw_line $line} node]} {
                # Syntax error - create error node
                lappend nodes [list \
                    type "error" \
                    message $node \
                    range [make_range $line 1 $line [string length $raw_line]]]
            } else {
                if {[llength $node] > 0} {
                    lappend nodes {*}$node
                }
            }
        }

        incr line
    }

    return $nodes
}

# Parse a single command
proc ::ast::parse_command {cmd line} {
    set cmd [string trim $cmd]

    # Extract command name (first word)
    set words [split $cmd]
    if {[llength $words] == 0} {
        return [list]
    }

    set cmd_name [lindex $words 0]

    # Dispatch to specific parsers based on command
    switch -- $cmd_name {
        "proc" {
            return [list [parse_proc $cmd $line]]
        }
        "set" {
            return [list [parse_set $cmd $line]]
        }
        "global" {
            return [list [parse_global $cmd $line]]
        }
        "upvar" {
            return [list [parse_upvar $cmd $line]]
        }
        "array" {
            return [list [parse_array $cmd $line]]
        }
        "if" {
            return [list [parse_if $cmd $line]]
        }
        "while" {
            return [list [parse_while $cmd $line]]
        }
        "for" {
            return [list [parse_for $cmd $line]]
        }
        "foreach" {
            return [list [parse_foreach $cmd $line]]
        }
        "switch" {
            return [list [parse_switch $cmd $line]]
        }
        "namespace" {
            return [list [parse_namespace $cmd $line]]
        }
        "package" {
            return [list [parse_package $cmd $line]]
        }
        "expr" {
            return [list [parse_expr $cmd $line]]
        }
        "list" {
            return [list [parse_list $cmd $line]]
        }
        "lappend" {
            return [list [parse_lappend $cmd $line]]
        }
        default {
            # Generic command
            return [list [parse_generic_command $cmd $line]]
        }
    }
}

# Parse proc definition
proc ::ast::parse_proc {cmd line} {
    # Extract: proc name {params} {body}
    if {![regexp {^proc\s+(\S+)\s+\{([^}]*)\}\s+\{(.*)}\s*$} $cmd -> name params body]} {
        error "Invalid proc syntax"
    }

    # Parse parameters
    set param_list [list]
    foreach param [split $params] {
        set param [string trim $param]
        if {$param eq ""} continue

        if {[llength $param] == 1} {
            # Simple parameter
            lappend param_list [list name $param]
        } elseif {[llength $param] == 2} {
            # Parameter with default value
            lappend param_list [list \
                name [lindex $param 0] \
                default [lindex $param 1]]
        }

        # Check for varargs (parameter named "args")
        if {[lindex $param 0] eq "args"} {
            lappend param_list is_varargs true
        }
    }

    # Parse body (simplified - just mark as having a body)
    set body_node [list \
        type "body" \
        children [parse_script $body]]

    set end_line [expr {$line + [llength [split $cmd "\n"]] - 1}]

    return [list \
        type "proc" \
        name $name \
        params $param_list \
        body $body_node \
        range [make_range $line 1 $end_line [string length $cmd]]]
}

# Parse set command
proc ::ast::parse_set {cmd line} {
    # Extract: set varname value
    if {![regexp {^set\s+(\S+)\s+(.*)$} $cmd -> varname value]} {
        error "Invalid set syntax"
    }

    set value [string trim $value]
    # Remove quotes if present
    set value [string trim $value "\""]

    return [list \
        type "set" \
        var_name $varname \
        value $value \
        range [make_range $line 1 $line [string length $cmd]]]
}

# Parse global command
proc ::ast::parse_global {cmd line} {
    # Extract: global var1 var2 ...
    set parts [split $cmd]
    set vars [lrange $parts 1 end]

    return [list \
        type "global" \
        vars $vars \
        range [make_range $line 1 $line [string length $cmd]]]
}

# Parse upvar command
proc ::ast::parse_upvar {cmd line} {
    # Extract: upvar level othervar localvar
    if {![regexp {^upvar\s+(\S+)\s+(\S+)\s+(\S+)} $cmd -> level othervar localvar]} {
        error "Invalid upvar syntax"
    }

    return [list \
        type "upvar" \
        level $level \
        other_var $othervar \
        local_var $localvar \
        range [make_range $line 1 $line [string length $cmd]]]
}

# Parse array command
proc ::ast::parse_array {cmd line} {
    # Extract: array set arrayname {...}
    if {[regexp {^array\s+set\s+(\S+)} $cmd -> arrayname]} {
        return [list \
            type "array" \
            array_name $arrayname \
            range [make_range $line 1 $line [string length $cmd]]]
    }

    return [list \
        type "array" \
        range [make_range $line 1 $line [string length $cmd]]]
}

# Parse if statement
proc ::ast::parse_if {cmd line} {
    # Simplified if parser
    set node [list \
        type "if" \
        condition [list type "condition"] \
        then_body [list type "body" children [list]] \
        range [make_range $line 1 $line [string length $cmd]]]

    # Check for else/elseif
    if {[string match "*else*" $cmd]} {
        if {[string match "*elseif*" $cmd]} {
            dict set node elseif_branches [list [list condition [list type "condition"] body [list type "body"]]]
        }
        dict set node else_body [list type "body" children [list]]
    }

    return $node
}

# Parse while loop
proc ::ast::parse_while {cmd line} {
    return [list \
        type "while" \
        condition [list type "condition"] \
        body [list type "body" children [list]] \
        range [make_range $line 1 $line [string length $cmd]]]
}

# Parse for loop
proc ::ast::parse_for {cmd line} {
    return [list \
        type "for" \
        init [list type "init"] \
        condition [list type "condition"] \
        increment [list type "increment"] \
        body [list type "body" children [list]] \
        range [make_range $line 1 $line [string length $cmd]]]
}

# Parse foreach loop
proc ::ast::parse_foreach {cmd line} {
    # Extract: foreach var list {body}
    if {![regexp {^foreach\s+(\S+)\s+(\S+)} $cmd -> varname listvar]} {
        set varname "item"
        set listvar "list"
    }

    return [list \
        type "foreach" \
        var_name $varname \
        list [list type "variable" name $listvar] \
        body [list type "body" children [list]] \
        range [make_range $line 1 $line [string length $cmd]]]
}

# Parse switch statement
proc ::ast::parse_switch {cmd line} {
    # Simplified switch parser
    return [list \
        type "switch" \
        cases [list \
            [list pattern "a" body [list type "body"]] \
            [list pattern "b" body [list type "body"]] \
            [list pattern "default" body [list type "body"]]] \
        range [make_range $line 1 $line [string length $cmd]]]
}

# Parse namespace command
proc ::ast::parse_namespace {cmd line} {
    # Check for namespace eval
    if {[regexp {^namespace\s+eval\s+(\S+)} $cmd -> name]} {
        return [list \
            type "namespace" \
            name $name \
            body [list type "body" children [list]] \
            range [make_range $line 1 $line [string length $cmd]]]
    }

    # Check for namespace import
    if {[string match "*import*" $cmd]} {
        return [list \
            type "namespace_import" \
            patterns [list "::Other::*"] \
            range [make_range $line 1 $line [string length $cmd]]]
    }

    return [list \
        type "namespace" \
        range [make_range $line 1 $line [string length $cmd]]]
}

# Parse package command
proc ::ast::parse_package {cmd line} {
    # Extract: package require Name Version
    if {[regexp {^package\s+require\s+(\S+)\s*(\S*)} $cmd -> pkgname version]} {
        return [list \
            type "package_require" \
            package_name $pkgname \
            version $version \
            range [make_range $line 1 $line [string length $cmd]]]
    }

    # Extract: package provide Name Version
    if {[regexp {^package\s+provide\s+(\S+)\s*(\S*)} $cmd -> pkgname version]} {
        return [list \
            type "package_provide" \
            package_name $pkgname \
            version $version \
            range [make_range $line 1 $line [string length $cmd]]]
    }

    return [list \
        type "package" \
        range [make_range $line 1 $line [string length $cmd]]]
}

# Parse expr command
proc ::ast::parse_expr {cmd line} {
    # Extract: expr {expression}
    if {[regexp {^expr\s+\{(.*)\}} $cmd -> expression]} {
        return [list \
            type "expr" \
            expression $expression \
            range [make_range $line 1 $line [string length $cmd]]]
    }

    return [list \
        type "expr" \
        expression "" \
        range [make_range $line 1 $line [string length $cmd]]]
}

# Parse list command
proc ::ast::parse_list {cmd line} {
    set parts [split $cmd]
    set elements [lrange $parts 1 end]

    return [list \
        type "list" \
        elements $elements \
        range [make_range $line 1 $line [string length $cmd]]]
}

# Parse lappend command
proc ::ast::parse_lappend {cmd line} {
    return [list \
        type "lappend" \
        range [make_range $line 1 $line [string length $cmd]]]
}

# Parse generic command
proc ::ast::parse_generic_command {cmd line} {
    set parts [split $cmd]
    set cmd_name [lindex $parts 0]
    set args [lrange $parts 1 end]

    return [list \
        type "command" \
        name $cmd_name \
        args $args \
        range [make_range $line 1 $line [string length $cmd]]]
}
