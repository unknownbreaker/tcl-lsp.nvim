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

# Main AST namespace
namespace eval ::ast {
    variable current_file "<string>"
    variable debug 0
}

# ===========================================================================
# MAIN PARSING LOGIC
# ===========================================================================

# Find all AST nodes in a code block
#
# Args:
#   code       - The code block to parse
#   start_line - Starting line number
#   depth      - Nesting depth
#
# Returns:
#   List of AST nodes
#
proc ::ast::find_all_nodes {code start_line depth} {
    variable debug

    # Extract individual commands from the code
    set cmds [::ast::commands::extract $code $start_line]
    set nodes [list]

    # Parse each command into an AST node
    foreach cmd_dict $cmds {
        set node [parse_command $cmd_dict $depth]
        if {$node ne ""} {
            lappend nodes $node
        }
    }

    return $nodes
}

# Parse a single command into an AST node
#
# This is the main dispatch function that determines the command type
# and calls the appropriate specialized parser.
#
# Args:
#   cmd_dict - Dict with text, start_line, end_line keys
#   depth    - Nesting depth (for recursive parsing)
#
# Returns:
#   AST node dict, or empty string if not a recognized command
#
proc ::ast::parse_command {cmd_dict depth} {
    variable debug

    set cmd_text [dict get $cmd_dict text]
    set start_line [dict get $cmd_dict start_line]
    set end_line [dict get $cmd_dict end_line]

    # Use tokenizer to count words (not llength which evaluates!)
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count == 0} {
        return ""
    }

    # Get command name using tokenizer (not lindex which evaluates!)
    set cmd_name [::tokenizer::get_token $cmd_text 0]

    # Dispatch to appropriate parser based on command name
    switch -exact -- $cmd_name {
        "proc" {
            return [::ast::parsers::procedures::parse_proc $cmd_text $start_line $end_line $depth]
        }
        "set" {
            return [::ast::parsers::variables::parse_set $cmd_text $start_line $end_line $depth]
        }
        "global" {
            return [::ast::parsers::variables::parse_global $cmd_text $start_line $end_line $depth]
        }
        "upvar" {
            return [::ast::parsers::variables::parse_upvar $cmd_text $start_line $end_line $depth]
        }
        "variable" {
            return [::ast::parsers::variables::parse_variable $cmd_text $start_line $end_line $depth]
        }
        "array" {
            return [::ast::parsers::variables::parse_array $cmd_text $start_line $end_line $depth]
        }
        "if" {
            return [::ast::parsers::control_flow::parse_if $cmd_text $start_line $end_line $depth]
        }
        "while" {
            return [::ast::parsers::control_flow::parse_while $cmd_text $start_line $end_line $depth]
        }
        "for" {
            return [::ast::parsers::control_flow::parse_for $cmd_text $start_line $end_line $depth]
        }
        "foreach" {
            return [::ast::parsers::control_flow::parse_foreach $cmd_text $start_line $end_line $depth]
        }
        "switch" {
            return [::ast::parsers::control_flow::parse_switch $cmd_text $start_line $end_line $depth]
        }
        "namespace" {
            return [::ast::parsers::namespaces::parse_namespace $cmd_text $start_line $end_line $depth]
        }
        "package" {
            return [::ast::parsers::packages::parse_package $cmd_text $start_line $end_line $depth]
        }
        "source" {
            return [::ast::parsers::packages::parse_source $cmd_text $start_line $end_line $depth]
        }
        "expr" {
            return [::ast::parsers::expressions::parse_expr $cmd_text $start_line $end_line $depth]
        }
        "list" {
            return [::ast::parsers::lists::parse_list $cmd_text $start_line $end_line $depth]
        }
        "lappend" {
            return [::ast::parsers::lists::parse_lappend $cmd_text $start_line $end_line $depth]
        }
        default {
            # Unknown command - create generic node
            return [dict create \
                type "command" \
                name $cmd_name \
                text $cmd_text \
                range [::ast::utils::make_range $start_line 1 $end_line 1] \
                depth $depth]
        }
    }
}

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

    # Parse all top-level nodes
    set nodes [find_all_nodes $code 1 0]

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
