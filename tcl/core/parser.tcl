#!/usr/bin/env tclsh
# tcl/core/parser.tcl
# TCL Parser - Main entry point for parsing TCL code

# Load the AST builder module
set script_dir [file dirname [file normalize [info script]]]
if {[catch {source [file join $script_dir ast_builder.tcl]} err]} {
    puts stderr "Error loading ast_builder.tcl: $err"
    exit 1
}

# Main parsing function
proc parse_file {filepath} {
    if {![file exists $filepath]} {
        error "File not found: $filepath"
    }

    if {![file readable $filepath]} {
        error "File not readable: $filepath"
    }

    set fp [open $filepath r]
    set content [read $fp]
    close $fp

    # Parse content and build AST
    set ast [::ast::build $content $filepath]

    # Convert to JSON and output
    puts [::ast::to_json $ast]
}

# Check command line arguments
if {$argc != 1} {
    puts stderr "Usage: $argv0 <tcl_file>"
    exit 1
}

set filepath [lindex $argv 0]

# Parse file and handle errors
if {[catch {parse_file $filepath} error]} {
    puts stderr "Parser error: $error"
    exit 1
}

exit 0
