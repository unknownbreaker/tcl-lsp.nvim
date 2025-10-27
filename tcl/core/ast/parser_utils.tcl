#!/usr/bin/env tclsh
# tcl/core/ast/parser_utils.tcl
# Shared Parser Utilities
#
# This module contains shared parsing functions that are used by both
# the main builder.tcl orchestrator and individual parser test files.
#
# Extracted from builder.tcl to break circular dependencies.

namespace eval ::ast {}

# ===========================================================================
# SHARED PARSING FUNCTIONS
# ===========================================================================

# Find all AST nodes in a code block
#
# This function extracts commands from a code block and parses each one
# into an AST node. It's used for recursive parsing of body blocks.
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
        set node [::ast::parse_command $cmd_dict $depth]
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
