#!/usr/bin/env tclsh
# tests/tcl/core/ast/test_utils.tcl
# Tests for utilities module (position tracking, ranges)

set script_dir [file dirname [file normalize [info script]]]
set ast_dir [file join [file dirname [file dirname [file dirname [file dirname $script_dir]]]] tcl core ast]
source [file join $ast_dir utils.tcl]

set total_tests 0
set passed_tests 0
set failed_tests 0

proc test {name script expected} {
    global total_tests passed_tests failed_tests
    incr total_tests
    
    if {[catch {uplevel 1 $script} result]} {
        puts "✗ FAIL: $name"
        puts "  Error: $result"
        incr failed_tests
        return 0
    }
    
    if {$result eq $expected || $result == $expected} {
        puts "✓ PASS: $name"
        incr passed_tests
        return 1
    } else {
        puts "✗ FAIL: $name"
        puts "  Expected: $expected"
        puts "  Got: $result"
        incr failed_tests
        return 0
    }
}

puts "========================================="
puts "Utils Module Test Suite"
puts "========================================="
puts ""

# Group 1: Range Creation
puts "Group 1: Range Creation"
puts "-----------------------------------------"

test "Simple range" {
    set range [::ast::utils::make_range 1 5 3 10]
    list [dict get $range start line] [dict get $range start column] \
         [dict get $range end_pos line] [dict get $range end_pos column]
} "1 5 3 10"

test "Single line range" {
    set range [::ast::utils::make_range 5 1 5 20]
    list [dict get $range start line] [dict get $range end_pos line]
} "5 5"

test "Column-only range" {
    set range [::ast::utils::make_range 1 10 1 15]
    list [dict get $range start column] [dict get $range end_pos column]
} "10 15"

test "Large line numbers" {
    set range [::ast::utils::make_range 1000 1 2000 50]
    list [dict get $range start line] [dict get $range end_pos line]
} "1000 2000"

test "Range structure completeness" {
    set range [::ast::utils::make_range 1 1 1 1]
    expr {[dict exists $range start] && [dict exists $range end_pos] && \
          [dict exists $range start line] && [dict exists $range start column]}
} "1"

puts ""

# Group 2: Line Mapping
puts "Group 2: Line Mapping"
puts "-----------------------------------------"

test "Build line map - single line" {
    ::ast::utils::build_line_map "hello world"
    # Just verify it doesn't crash
    expr 1
} "1"

test "Build line map - multiple lines" {
    ::ast::utils::build_line_map "line1\nline2\nline3"
    # Verify it completes
    expr 1
} "1"

test "Build line map - empty string" {
    ::ast::utils::build_line_map ""
    expr 1
} "1"

test "Build line map - very long line" {
    ::ast::utils::build_line_map [string repeat "x" 10000]
    expr 1
} "1"

puts ""

# Group 3: Offset to Line Conversion
puts "Group 3: Offset to Line Conversion"
puts "-----------------------------------------"

test "Offset at start of line 1" {
    ::ast::utils::build_line_map "hello\nworld\ntest"
    ::ast::utils::offset_to_line 0
} "1 1"

test "Offset in middle of line 1" {
    ::ast::utils::build_line_map "hello\nworld\ntest"
    ::ast::utils::offset_to_line 2
} "1 3"

test "Offset at start of line 2" {
    ::ast::utils::build_line_map "hello\nworld\ntest"
    ::ast::utils::offset_to_line 6
} "2 1"

test "Offset in middle of line 2" {
    ::ast::utils::build_line_map "hello\nworld\ntest"
    ::ast::utils::offset_to_line 8
} "2 3"

test "Offset at start of line 3" {
    ::ast::utils::build_line_map "hello\nworld\ntest"
    ::ast::utils::offset_to_line 12
} "3 1"

test "Offset beyond end (should default)" {
    ::ast::utils::build_line_map "hello"
    ::ast::utils::offset_to_line 100
} "1 1"

puts ""

# Group 4: Line Counting
puts "Group 4: Line Counting"
puts "-----------------------------------------"

test "Count lines - single line" {
    ::ast::utils::count_lines "hello"
} "0"

test "Count lines - two lines" {
    ::ast::utils::count_lines "hello\nworld"
} "1"

test "Count lines - three lines" {
    ::ast::utils::count_lines "line1\nline2\nline3"
} "2"

test "Count lines - empty string" {
    ::ast::utils::count_lines ""
} "0"

test "Count lines - only newline" {
    ::ast::utils::count_lines "\n"
} "1"

test "Count lines - multiple newlines" {
    ::ast::utils::count_lines "\n\n\n"
} "3"

puts ""

# Group 5: Complex Scenarios
puts "Group 5: Complex Scenarios"
puts "-----------------------------------------"

test "TCL code with proc" {
    set code "proc test \{\} \{\n    puts hello\n\}"
    ::ast::utils::build_line_map $code
    ::ast::utils::count_lines $code
} "2"

test "Offset in multiline code" {
    set code "set x 1\nset y 2\nproc test \{\} \{\}"
    ::ast::utils::build_line_map $code
    # Offset 8 should be line 2 (after "set x 1\n")
    ::ast::utils::offset_to_line 8
} "2 1"

test "Offset with tabs" {
    set code "hello\t\tworld\ntest"
    ::ast::utils::build_line_map $code
    # Count should still work
    ::ast::utils::count_lines $code
} "1"

test "Long file simulation" {
    set code ""
    for {set i 1} {$i <= 100} {incr i} {
        append code "line $i\n"
    }
    ::ast::utils::build_line_map $code
    ::ast::utils::count_lines $code
} "100"

puts ""

# Group 6: Edge Cases
puts "Group 6: Edge Cases"
puts "-----------------------------------------"

test "Unicode characters in code" {
    set code "set x \"Hello 世界\"\nset y 42"
    ::ast::utils::build_line_map $code
    ::ast::utils::count_lines $code
} "1"

test "Windows line endings (CRLF)" {
    set code "line1\r\nline2\r\nline3"
    ::ast::utils::count_lines $code
} "2"

test "Mixed line endings" {
    set code "line1\nline2\r\nline3"
    ::ast::utils::count_lines $code
} "2"

test "Range with same start and end" {
    set range [::ast::utils::make_range 5 10 5 10]
    expr {[dict get $range start line] == [dict get $range end_pos line] && \
          [dict get $range start column] == [dict get $range end_pos column]}
} "1"

puts ""
puts "========================================="
puts "Test Results"
puts "========================================="
puts "Total:  $total_tests"
puts "Passed: $passed_tests"
puts "Failed: $failed_tests"
puts ""

if {$failed_tests == 0} {
    puts "✓ ALL TESTS PASSED"
    exit 0
} else {
    puts "✗ SOME TESTS FAILED"
    exit 1
}
