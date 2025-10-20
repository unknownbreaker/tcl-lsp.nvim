#!/usr/bin/env tclsh
# tcl/core/ast/comments.tcl
# Comment Extraction Module
#
# Extracts comments from TCL source code for inclusion in the AST.
# Comments are important for LSP features like hover documentation.

namespace eval ::ast::comments {
    namespace export extract
}

# Extract all comments from TCL source code
#
# Args:
#   code - The source code to scan
#
# Returns:
#   List of comment dicts, each with: type, text, range keys
#
proc ::ast::comments::extract {code} {
    set comments [list]
    set lines [split $code "\n"]
    set line_num 1

    foreach line $lines {
        # Find comments (# at start of line or after whitespace)
        set trimmed [string trimleft $line]
        if {[string index $trimmed 0] eq "#"} {
            # This is a comment line
            set comment_text [string range $trimmed 1 end]

            # Create comment node
            lappend comments [dict create \
                type "comment" \
                text $comment_text \
                range [::ast::utils::make_range $line_num 1 $line_num [string length $line]]]
        }
        incr line_num
    }

    return $comments
}

# ===========================================================================
# MAIN - For testing
# ===========================================================================

if {[info script] eq $argv0} {
    # Need utils for make_range
    set script_dir [file dirname [file normalize [info script]]]
    source [file join $script_dir utils.tcl]

    puts "Testing comments module..."
    puts ""

    # Test 1: Simple comment
    set test1 "# This is a comment\nset x 1"
    puts "Test 1: Simple comment"
    set comments [extract $test1]
    puts "  Found [llength $comments] comment(s)"
    if {[llength $comments] > 0} {
        puts "  Comment text: [dict get [lindex $comments 0] text]"
    }
    puts ""

    # Test 2: Multiple comments
    set test2 "# Comment 1\nset x 1\n# Comment 2\nset y 2"
    puts "Test 2: Multiple comments"
    set comments [extract $test2]
    puts "  Found [llength $comments] comment(s)"
    puts ""

    # Test 3: No comments
    set test3 "set x 1\nset y 2"
    puts "Test 3: No comments"
    set comments [extract $test3]
    puts "  Found [llength $comments] comment(s)"
    puts ""

    # Test 4: Indented comment
    set test4 "    # Indented comment\n    set x 1"
    puts "Test 4: Indented comment"
    set comments [extract $test4]
    puts "  Found [llength $comments] comment(s)"
    if {[llength $comments] > 0} {
        puts "  Comment text: [dict get [lindex $comments 0] text]"
    }
    puts ""

    puts "✓ Comments tests complete"
}
