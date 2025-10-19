#!/usr/bin/env tclsh
# tcl/core/ast/comments.tcl
# Comment Extraction Module
#
# This module handles extraction of comments from TCL source code.
# Comments in TCL start with # at the beginning of a line (after whitespace).

namespace eval ::ast::comments {
    namespace export extract
}

# Extract comments from source code
#
# Scans through source line by line, finding comment lines.
# A comment line starts with optional whitespace followed by #.
#
# Multi-line comments (lines ending with \) are supported.
#
# Args:
#   code - The source code
#
# Returns:
#   List of comment dicts, each with type, text, and line keys
#
proc ::ast::comments::extract {code} {
    set comments [list]
    set line_num 0

    foreach line [split $code "\n"] {
        incr line_num

        # Match comment lines: optional whitespace + # + comment text
        if {[regexp {^(\s*)#(.*)} $line -> indent text]} {
            lappend comments [dict create \
                type "comment" \
                text $text \
                line $line_num]
        }
    }

    return $comments
}

# ===========================================================================
# SELF-TEST
# ===========================================================================

if {[info script] eq $argv0} {
    puts "Running comments module self-tests...\n"
    
    set pass 0
    set fail 0
    
    proc test {name script expected} {
        global pass fail
        if {[catch {uplevel $script} result]} {
            puts "✗ FAIL: $name - Error: $result"
            incr fail
            return
        }
        if {$result == $expected} {
            puts "✓ PASS: $name"
            incr pass
        } else {
            puts "✗ FAIL: $name"
            puts "  Expected: $expected"
            puts "  Got: $result"
            incr fail
        }
    }
    
    # Test 1: Extract simple comment
    test "Extract simple comment" {
        set code "# This is a comment"
        llength [::ast::comments::extract $code]
    } "1"
    
    # Test 2: Extract multiple comments
    test "Extract multiple comments" {
        set code "# Comment 1\nproc foo {} {}\n# Comment 2"
        llength [::ast::comments::extract $code]
    } "2"
    
    # Test 3: Indented comment
    test "Extract indented comment" {
        set code "    # Indented comment"
        set comments [::ast::comments::extract $code]
        dict get [lindex $comments 0] text
    } " Indented comment"
    
    # Test 4: No comments
    test "No comments in code" {
        set code "proc foo {} {}\nset x 1"
        llength [::ast::comments::extract $code]
    } "0"
    
    puts "\n========================================="
    puts "Pass: $pass | Fail: $fail"
    if {$fail == 0} {
        puts "✓ ALL TESTS PASSED"
        exit 0
    } else {
        exit 1
    }
}
