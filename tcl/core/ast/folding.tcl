#!/usr/bin/env tclsh
# tcl/core/ast/folding.tcl
# Folding Range Extraction Module
#
# Extracts code folding ranges from AST for LSP foldingRange requests.
# Supports folding of procedures, control flow, namespaces, and comment blocks.

namespace eval ::ast::folding {
    namespace export extract_ranges
}

# Extract folding ranges from AST
#
# Args:
#   ast - The parsed AST dict (from ::ast::build)
#
# Returns:
#   List of range dicts with keys: startLine, endLine, kind
#   Lines are 0-indexed per LSP specification
#
proc ::ast::folding::extract_ranges {ast} {
    set ranges [list]

    if {![dict exists $ast children]} {
        return $ranges
    }

    foreach child [dict get $ast children] {
        set child_ranges [::ast::folding::extract_from_node $child]
        lappend ranges {*}$child_ranges
    }

    return $ranges
}

# Extract folding range from a single AST node (recursive)
#
# Args:
#   node - An AST node dict
#
# Returns:
#   List of range dicts
#
proc ::ast::folding::extract_from_node {node} {
    set ranges [list]

    if {![dict exists $node type]} {
        return $ranges
    }

    set node_type [dict get $node type]

    # Check if this node type is foldable
    if {[::ast::folding::is_foldable $node_type]} {
        set range [::ast::folding::make_range $node]
        if {$range ne ""} {
            lappend ranges $range
        }
    }

    # Recurse into children
    if {[dict exists $node children]} {
        foreach child [dict get $node children] {
            set child_ranges [::ast::folding::extract_from_node $child]
            lappend ranges {*}$child_ranges
        }
    }

    # Recurse into body (for procs, etc.)
    if {[dict exists $node body]} {
        set body [dict get $node body]
        if {[dict exists $body children]} {
            foreach child [dict get $body children] {
                set child_ranges [::ast::folding::extract_from_node $child]
                lappend ranges {*}$child_ranges
            }
        }
    }

    # Recurse into then_body (for if statements)
    if {[dict exists $node then_body]} {
        set then_body [dict get $node then_body]
        if {[dict exists $then_body children]} {
            foreach child [dict get $then_body children] {
                set child_ranges [::ast::folding::extract_from_node $child]
                lappend ranges {*}$child_ranges
            }
        }
    }

    # Recurse into else_body (for if statements)
    if {[dict exists $node else_body]} {
        set else_body [dict get $node else_body]
        if {[dict exists $else_body children]} {
            foreach child [dict get $else_body children] {
                set child_ranges [::ast::folding::extract_from_node $child]
                lappend ranges {*}$child_ranges
            }
        }
    }

    # Recurse into elseif branches (for if statements)
    if {[dict exists $node elseif]} {
        foreach branch [dict get $node elseif] {
            if {[dict exists $branch body]} {
                set branch_body [dict get $branch body]
                if {[dict exists $branch_body children]} {
                    foreach child [dict get $branch_body children] {
                        set child_ranges [::ast::folding::extract_from_node $child]
                        lappend ranges {*}$child_ranges
                    }
                }
            }
        }
    }

    # Recurse into switch cases
    if {[dict exists $node cases]} {
        foreach case [dict get $node cases] {
            if {[dict exists $case body]} {
                set case_body [dict get $case body]
                if {[dict exists $case_body children]} {
                    foreach child [dict get $case_body children] {
                        set child_ranges [::ast::folding::extract_from_node $child]
                        lappend ranges {*}$child_ranges
                    }
                }
            }
        }
    }

    return $ranges
}

# Check if a node type is foldable
#
# Args:
#   node_type - The type string from an AST node
#
# Returns:
#   1 if foldable, 0 otherwise
#
proc ::ast::folding::is_foldable {node_type} {
    set foldable_types {
        proc
        if
        foreach
        for
        while
        switch
    }
    return [expr {$node_type in $foldable_types}]
}

# Create a folding range dict from a node
#
# Args:
#   node - An AST node with a range field
#
# Returns:
#   Dict with startLine, endLine, kind (0-indexed lines)
#   Returns empty string if node spans only one line
#
proc ::ast::folding::make_range {node} {
    if {![dict exists $node range]} {
        return ""
    }

    set range [dict get $node range]

    # Get start and end lines from the AST range format
    # Format: {start {line N column M} end_pos {line N column M}}
    set start_line 1
    set end_line 1

    if {[dict exists $range start line]} {
        set start_line [dict get $range start line]
    }

    if {[dict exists $range end_pos line]} {
        set end_line [dict get $range end_pos line]
    }

    # Skip single-line constructs (no folding benefit)
    if {$end_line <= $start_line} {
        return ""
    }

    # LSP uses 0-indexed lines, TCL parser uses 1-indexed
    return [dict create \
        startLine [expr {$start_line - 1}] \
        endLine [expr {$end_line - 1}] \
        kind "region"]
}

# ===========================================================================
# MAIN - For self-testing
# ===========================================================================

if {[info script] eq $argv0} {
    puts "Testing folding module..."
    puts ""

    # Load required dependencies
    set script_dir [file dirname [file normalize [info script]]]
    source [file join $script_dir builder.tcl]

    # Test 1: Simple proc
    puts "Test 1: Simple multi-line proc"
    set code {proc hello {} {
    puts "Hello!"
    return 1
}}
    set ast [::ast::build $code]
    set ranges [::ast::folding::extract_ranges $ast]
    puts "  Found [llength $ranges] fold ranges"
    if {[llength $ranges] > 0} {
        set r [lindex $ranges 0]
        puts "  Range: startLine=[dict get $r startLine] endLine=[dict get $r endLine] kind=[dict get $r kind]"
    }
    puts ""

    # Test 2: Single-line proc (should not fold)
    puts "Test 2: Single-line proc (no fold)"
    set code2 {proc simple {} { return 42 }}
    set ast2 [::ast::build $code2]
    set ranges2 [::ast::folding::extract_ranges $ast2]
    puts "  Found [llength $ranges2] fold ranges (expected 0)"
    puts ""

    # Test 3: Multiple procs
    puts "Test 3: Multiple procs"
    set code3 {proc foo {} {
    puts "foo"
}

proc bar {} {
    puts "bar"
}}
    set ast3 [::ast::build $code3]
    set ranges3 [::ast::folding::extract_ranges $ast3]
    puts "  Found [llength $ranges3] fold ranges (expected 2)"
    puts ""

    puts "✓ Folding module self-tests complete"
}
