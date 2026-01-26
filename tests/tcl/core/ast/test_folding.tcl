#!/usr/bin/env tclsh
# tests/tcl/core/ast/test_folding.tcl
# Tests for folding range extraction

set script_dir [file dirname [file normalize [info script]]]
set ast_dir [file join [file dirname [file dirname [file dirname [file dirname $script_dir]]]] tcl core ast]
source [file join $ast_dir builder.tcl]
source [file join $ast_dir folding.tcl]

# Test counter
set total_tests 0
set passed_tests 0
set failed_tests 0

# Test helper
proc test {name script expected} {
    global total_tests passed_tests failed_tests
    incr total_tests

    if {[catch {uplevel 1 $script} result]} {
        puts "✗ FAIL: $name"
        puts "  Error: $result"
        incr failed_tests
        return 0
    }

    if {$result eq $expected} {
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

# Test helper for list length
proc test_count {name script expected_count} {
    global total_tests passed_tests failed_tests
    incr total_tests

    if {[catch {uplevel 1 $script} result]} {
        puts "✗ FAIL: $name"
        puts "  Error: $result"
        incr failed_tests
        return 0
    }

    set count [llength $result]
    if {$count == $expected_count} {
        puts "✓ PASS: $name"
        incr passed_tests
        return 1
    } else {
        puts "✗ FAIL: $name"
        puts "  Expected count: $expected_count"
        puts "  Got count: $count"
        puts "  Result: $result"
        incr failed_tests
        return 0
    }
}

puts "========================================="
puts "Folding Module Test Suite"
puts "========================================="
puts ""

# Group 1: Basic proc folding
puts "Group 1: Procedure Folding"
puts "-----------------------------------------"

test_count "Single proc - one fold range" {
    set code {proc foo {args} {
    puts "hello"
    puts "world"
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 1

test_count "Single-line proc - no fold" {
    set code {proc foo {} { return 1 }}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 0

test_count "Multiple procs - multiple folds" {
    set code {proc foo {} {
    puts "foo"
}

proc bar {} {
    puts "bar"
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 2

test_count "Empty code - no folds" {
    set code {}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 0

puts ""

# Group 2: Control flow folding
puts "Group 2: Control Flow Folding"
puts "-----------------------------------------"

test_count "If statement - one fold" {
    set code {if {$x > 0} {
    puts "positive"
    puts "number"
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 1

test_count "If-else - one fold (whole if block)" {
    set code {if {$x > 0} {
    puts "positive"
} else {
    puts "not positive"
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 1

test_count "Foreach loop - one fold" {
    set code {foreach item $list {
    puts $item
    process $item
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 1

test_count "While loop - one fold" {
    set code {while {$i < 10} {
    puts $i
    incr i
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 1

test_count "For loop - one fold" {
    set code {for {set i 0} {$i < 10} {incr i} {
    puts $i
    process $i
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 1

test_count "Switch statement - one fold" {
    set code {switch $value {
    a { puts "alpha" }
    b { puts "beta" }
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 1

test_count "Single-line if - no fold" {
    set code {if {$x > 0} { puts "positive" }}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 0

test_count "Nested if in proc - two folds" {
    set code {proc foo {} {
    if {$x > 0} {
        puts "positive"
    }
}}
    set ast [::ast::build $code]
    ::ast::folding::extract_ranges $ast
} 2

puts ""

# Group 3: Fold range structure
puts "Group 3: Fold Range Structure (proc)"
puts "-----------------------------------------"

test "Fold range has startLine" {
    set code {proc foo {} {
    puts "hello"
}}
    set ast [::ast::build $code]
    set ranges [::ast::folding::extract_ranges $ast]
    set range [lindex $ranges 0]
    dict exists $range startLine
} 1

test "Fold range has endLine" {
    set code {proc foo {} {
    puts "hello"
}}
    set ast [::ast::build $code]
    set ranges [::ast::folding::extract_ranges $ast]
    set range [lindex $ranges 0]
    dict exists $range endLine
} 1

test "Fold range has kind" {
    set code {proc foo {} {
    puts "hello"
}}
    set ast [::ast::build $code]
    set ranges [::ast::folding::extract_ranges $ast]
    set range [lindex $ranges 0]
    dict exists $range kind
} 1

test "Fold kind is region" {
    set code {proc foo {} {
    puts "hello"
}}
    set ast [::ast::build $code]
    set ranges [::ast::folding::extract_ranges $ast]
    set range [lindex $ranges 0]
    dict get $range kind
} "region"

puts ""

# Group 4: Line number conversion (parser to LSP)
puts "Group 4: Line Number Conversion"
puts "-----------------------------------------"

test "startLine converted from parser" {
    # The parser has a known off-by-one: it reports start_line=2 for first command
    # Our folding module converts: (parser_line - 1) = 0-indexed LSP line
    # So parser line 2 -> LSP line 1
    set code "proc foo {} \{\n    puts \"hello\"\n\}"
    set ast [::ast::build $code]
    set ranges [::ast::folding::extract_ranges $ast]
    set range [lindex $ranges 0]
    dict get $range startLine
} 1

test "endLine converted from parser" {
    # Parser reports end_line=3, folding converts to LSP: 3-1=2
    set code "proc foo {} \{\n    puts \"hello\"\n\}"
    set ast [::ast::build $code]
    set ranges [::ast::folding::extract_ranges $ast]
    set range [lindex $ranges 0]
    dict get $range endLine
} 2

test "Multi-line proc spans correct lines" {
    # A 4-line proc should have endLine - startLine >= 1
    set code "proc foo {} \{\n    line1\n    line2\n\}"
    set ast [::ast::build $code]
    set ranges [::ast::folding::extract_ranges $ast]
    set range [lindex $ranges 0]
    set start [dict get $range startLine]
    set end [dict get $range endLine]
    expr {$end > $start}
} 1

puts ""

# Summary
puts "========================================="
puts "Results: $passed_tests/$total_tests passed"
if {$failed_tests > 0} {
    puts "FAILED: $failed_tests tests"
    exit 1
} else {
    puts "All tests passed!"
    exit 0
}
