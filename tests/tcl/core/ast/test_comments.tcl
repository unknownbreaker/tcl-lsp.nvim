#!/usr/bin/env tclsh
# tests/tcl/core/ast/test_comments.tcl
# Tests for comment extraction module

set script_dir [file dirname [file normalize [info script]]]
set ast_dir [file join [file dirname [file dirname [file dirname [file dirname $script_dir]]]] tcl core ast]
source [file join $ast_dir comments.tcl]

set total 0
set passed 0

proc test {name code expected_count} {
    global total passed
    incr total
    
    set result [::ast::comments::extract $code]
    set count [llength $result]
    
    if {$count == $expected_count} {
        puts "✓ PASS: $name"
        incr passed
    } else {
        puts "✗ FAIL: $name - Expected $expected_count, got $count"
    }
}

puts "Comment Extraction Tests"
puts "========================\n"

test "No comments" "set x 1\nset y 2" 0
test "Single comment" "# This is a comment" 1
test "Multiple comments" "# Comment 1\nset x 1\n# Comment 2" 2
test "Indented comment" "    # Indented" 1
test "Comment with special chars" "# Test: $var {}" 1
test "Empty file" "" 0
test "Only whitespace" "   \n  \t\n" 0
test "Comment at end" "set x 1\n# End comment" 1
test "Comment in middle" "set x 1\n# Middle\nset y 2" 1
test "Multiple consecutive" "# Line 1\n# Line 2\n# Line 3" 3

puts "\nResults: $passed/$total passed"
exit [expr {$passed == $total ? 0 : 1}]
