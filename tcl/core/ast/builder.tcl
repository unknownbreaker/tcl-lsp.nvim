#!/usr/bin/env tclsh
# tcl/core/ast/builder.tcl
# Main AST Builder - Orchestrator Module
#
# This is the main entry point for AST building. It:
# 1. Loads all sub-modules
# 2. Provides the public ::ast::build API
# 3. Coordinates parsing workflow

# Get script directory for loading modules
set script_dir [file dirname [file normalize [info script]]]

# Load tokenizer (from parent directory)
set parent_dir [file dirname $script_dir]
if {[catch {source [file join $parent_dir tokenizer.tcl]} err]} {
    puts stderr "Error loading tokenizer.tcl: $err"
    exit 1
}

# Load all AST core modules
foreach module {utils delimiters comments commands json} {
    if {[catch {source [file join $script_dir ${module}.tcl]} err]} {
        puts stderr "Error loading ${module}.tcl: $err"
        exit 1
    }
}

# Load all parser modules
set parsers_dir [file join $script_dir parsers]
foreach parser {procedures variables control_flow namespaces packages expressions lists} {
    if {[catch {source [file join $parsers_dir ${parser}.tcl]} err]} {
        puts stderr "Error loading parsers/${parser}.tcl: $err"
        exit 1
    }
}

# IMPORTANT: Load parser_utils AFTER all parsers are loaded
# This file contains ::ast::find_all_nodes and ::ast::parse_command
# which reference the parser functions above
if {[catch {source [file join $script_dir parser_utils.tcl]} err]} {
    puts stderr "Error loading parser_utils.tcl: $err"
    exit 1
}

# Main AST namespace
namespace eval ::ast {
    variable current_file "<string>"
    variable debug 0
}

# ===========================================================================
# PUBLIC API
# ===========================================================================

# Build an Abstract Syntax Tree from TCL source code
#
# This is the main entry point that coordinates the entire parsing process.
#
# Args:
#   code     - The TCL source code to parse
#   filepath - Path to the source file (for error reporting)
#
# Returns:
#   AST dict with type, filepath, comments, children, had_error, errors keys
#
proc ::ast::build {code {filepath "<string>"}} {
    variable current_file
    variable debug

    set current_file $filepath

    if {$debug} {
        puts "\n=== Building AST for $filepath ==="
        puts "Code length: [string length $code] chars"
    }

    # Check if the code is syntactically complete
    if {![info complete $code]} {
        if {$debug} {
            puts "ERROR: Incomplete TCL code"
        }
        return [dict create \
            type "root" \
            filepath $filepath \
            errors [list [dict create \
                type "error" \
                message "Syntax error: missing close-brace" \
                range [::ast::utils::make_range 1 1 1 1] \
                error_type "incomplete" \
                suggestion "Check for missing closing brace \}"]] \
            had_error 1 \
            children [list] \
            comments [list]]
    }

    # Build position tracking map
    ::ast::utils::build_line_map $code

    # Extract comments
    set comments [::ast::comments::extract $code]

    if {$debug} {
        puts "Found [llength $comments] comments"
    }

    # Parse all top-level nodes using the shared function from parser_utils.tcl
    set nodes [::ast::find_all_nodes $code 1 0]

    if {$debug} {
        puts "Found [llength $nodes] total nodes"
    }

    # Collect any error nodes
    set error_nodes [list]
    foreach node $nodes {
        if {[dict exists $node type] && [dict get $node type] eq "error"} {
            lappend error_nodes $node
        }
    }

    set had_error 0
    if {[llength $error_nodes] > 0} {
        set had_error 1
    }

    if {$debug} {
        puts "Found [llength $error_nodes] errors"
        puts "=== AST Building Complete ===\n"
    }

    # Return the complete AST
    return [dict create \
        type "root" \
        filepath $filepath \
        comments $comments \
        children $nodes \
        had_error $had_error \
        errors $error_nodes]
}

# Convenience function: Convert AST to JSON
#
# PUBLIC API
#
proc ::ast::to_json {ast} {
    return [::ast::json::to_json $ast]
}

# ===========================================================================
# MAIN - For testing
# ===========================================================================

if {[info script] eq $argv0} {
    if {$argc != 1} {
        puts stderr "Usage: $argv0 <tcl_file>"
        puts stderr "   or: $argv0 test  (to run self-tests)"
        exit 1
    }

    if {[lindex $argv 0] eq "test"} {
        puts "Running builder integration tests...\n"
        set ::ast::debug 1

        # Test 1: Simple proc
        set code1 "proc hello {} \{ puts \"Hello!\" \}"
        set ast1 [::ast::build $code1 "test1.tcl"]
        puts "\nTest 1 Result:"
        puts [::ast::to_json $ast1]

        # Test 2: Multiple commands
        set code2 "set x 1\nset y 2\nproc add \{a b\} \{ return \[expr \{\$a + \$b\}\] \}"
        set ast2 [::ast::build $code2 "test2.tcl"]
        puts "\nTest 2 Result:"
        puts [::ast::to_json $ast2]

        puts "\n✓ Builder tests complete"
    } else {
        # Parse file
        set filepath [lindex $argv 0]
        if {![file exists $filepath]} {
            puts stderr "Error: File not found: $filepath"
            exit 1
        }

        set fp [open $filepath r]
        set code [read $fp]
        close $fp

        set ast [::ast::build $code $filepath]
        puts [::ast::to_json $ast]
    }
}
