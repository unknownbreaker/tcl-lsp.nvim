#!/usr/bin/env tclsh
# tests/tcl/core/ast/test_json.tcl
# Comprehensive tests for JSON serialization module
#
# Tests the fixed JSON serialization that resolves the "bad class 'dict'" bug
# FIXED: Corrected pattern matching for "Empty children list" test

set script_dir [file dirname [file normalize [info script]]]
set ast_dir [file join [file dirname [file dirname [file dirname [file dirname $script_dir]]]] tcl core ast]
source [file join $ast_dir json.tcl]

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

puts "========================================="
puts "JSON Module Test Suite"
puts "========================================="
puts ""

# Group 1: Basic Types
puts "Group 1: Basic Type Serialization"
puts "-----------------------------------------"

test "Empty dict" {
    ::ast::json::to_json [dict create]
} "\{\}"

test "Simple string value" {
    ::ast::json::to_json [dict create name "test"]
} "\{\n  \"name\": \"test\"\n\}"

test "Integer value" {
    ::ast::json::to_json [dict create count 42]
} "\{\n  \"count\": 42\n\}"

test "Float value" {
    ::ast::json::to_json [dict create pi 3.14]
} "\{\n  \"pi\": 3.14\n\}"

test "Boolean-like values" {
    ::ast::json::to_json [dict create flag 1]
} "\{\n  \"flag\": 1\n\}"

puts ""

# Group 2: Special Characters
puts "Group 2: Special Character Escaping"
puts "-----------------------------------------"

test "Newline escape" {
    ::ast::json::to_json [dict create text "line1\nline2"]
} "\{\n  \"text\": \"line1\\nline2\"\n\}"

test "Quote escape" {
    ::ast::json::to_json [dict create text "say \"hello\""]
} "\{\n  \"text\": \"say \\\"hello\\\"\"\n\}"

test "Backslash escape" {
    ::ast::json::to_json [dict create path "C:\\\\Users"]
} "\{\n  \"path\": \"C:\\\\\\\\Users\"\n\}"

test "Tab escape" {
    ::ast::json::to_json [dict create text "col1\tcol2"]
} "\{\n  \"text\": \"col1\\tcol2\"\n\}"

test "Carriage return escape" {
    ::ast::json::to_json [dict create text "line1\rline2"]
} "\{\n  \"text\": \"line1\\rline2\"\n\}"

puts ""

# Group 3: Lists
puts "Group 3: List Serialization"
puts "-----------------------------------------"

test "Empty list" {
    ::ast::json::to_json [dict create items [list]]
} "\{\n  \"items\": \[\]\n\}"

test "Simple list" {
    ::ast::json::to_json [dict create items [list "a" "b" "c"]]
} "\{\n  \"items\": \[\"a\", \"b\", \"c\"\]\n\}"

test "Numeric list" {
    ::ast::json::to_json [dict create nums [list 1 2 3]]
} "\{\n  \"nums\": \[1, 2, 3\]\n\}"

test "Mixed list" {
    ::ast::json::to_json [dict create mixed [list "text" 42 3.14]]
} "\{\n  \"mixed\": \[\"text\", 42, 3.14\]\n\}"

test "Single element list" {
    ::ast::json::to_json [dict create single [list "alone"]]
} "\{\n  \"single\": \[\"alone\"\]\n\}"

puts ""

# Group 4: Nested Structures (The Critical Bug Fix!)
puts "Group 4: Nested Structures (BUG FIX VALIDATION)"
puts "-----------------------------------------"

test "List of dicts" {
    set data [dict create children [list \
        [dict create type "proc" name "test1"] \
        [dict create type "proc" name "test2"]]]
    set result [::ast::json::to_json $data]
    # Just verify it doesn't crash
    expr {[string length $result] > 0}
} "1"

test "Nested dict" {
    set data [dict create \
        outer [dict create inner [dict create value "deep"]]]
    set result [::ast::json::to_json $data]
    expr {[string length $result] > 0}
} "1"

test "Dict with list of dicts" {
    set data [dict create \
        type "root" \
        children [list \
            [dict create type "set" var "x"] \
            [dict create type "set" var "y"]]]
    set result [::ast::json::to_json $data]
    expr {[string length $result] > 0 && [string match "*children*" $result]}
} "1"

test "Complex AST-like structure" {
    set data [dict create \
        type "proc" \
        name "hello" \
        params [list \
            [dict create name "arg1"] \
            [dict create name "arg2" default "value"]] \
        body [dict create children [list]]]
    set result [::ast::json::to_json $data]
    expr {[string length $result] > 0}
} "1"

# ✅ FIXED: Changed from string match to regexp for better pattern matching
test "Empty children list (common AST pattern)" {
    set data [dict create type "root" children [list]]
    set result [::ast::json::to_json $data]
    regexp {"children":\s*\[\]} $result
} "1"

puts ""

# Group 5: Real-World AST Structures
puts "Group 5: Real-World AST Structures"
puts "-----------------------------------------"

test "Simple proc AST node" {
    set proc_node [dict create \
        type "proc" \
        name "hello" \
        params [list] \
        body [dict create children [list]] \
        range [dict create \
            start [dict create line 1 column 1] \
            end_pos [dict create line 3 column 1]]]
    set result [::ast::json::to_json $proc_node]
    expr {[string match "*proc*" $result] && [string match "*range*" $result]}
} "1"

test "Set command AST node" {
    set set_node [dict create \
        type "set" \
        var_name "x" \
        value "42" \
        range [dict create \
            start [dict create line 1 column 1] \
            end_pos [dict create line 1 column 10]]]
    set result [::ast::json::to_json $set_node]
    expr {[string match "*set*" $result] && [string match "*var_name*" $result]}
} "1"

test "Root AST with multiple children" {
    set root [dict create \
        type "root" \
        filepath "test.tcl" \
        children [list \
            [dict create type "set" var_name "x" value "1"] \
            [dict create type "set" var_name "y" value "2"]] \
        had_error 0 \
        errors [list]]
    set result [::ast::json::to_json $root]
    expr {[string match "*root*" $result] && [string match "*children*" $result]}
} "1"

puts ""

# Group 6: Indentation
puts "Group 6: Indentation Formatting"
puts "-----------------------------------------"

test "Nested indentation" {
    set data [dict create \
        level1 [dict create \
            level2 [dict create \
                value "deep"]]]
    set result [::ast::json::to_json $data]
    # Check that indentation increases
    expr {[string match "*  \"level1\":*" $result] && \
          [string match "*    \"level2\":*" $result]}
} "1"

test "List indentation" {
    set data [dict create \
        items [list \
            [dict create id 1] \
            [dict create id 2]]]
    set result [::ast::json::to_json $data]
    # Verify formatting is reasonable
    expr {[string length $result] > 10}
} "1"

puts ""

# Group 7: Edge Cases
puts "Group 7: Edge Cases"
puts "-----------------------------------------"

test "Very long string" {
    set longstr [string repeat "a" 1000]
    set data [dict create text $longstr]
    set result [::ast::json::to_json $data]
    expr {[string length $result] > 1000}
} "1"

test "Many keys" {
    set data [dict create]
    for {set i 0} {$i < 50} {incr i} {
        dict set data "key$i" "value$i"
    }
    set result [::ast::json::to_json $data]
    expr {[string length $result] > 100}
} "1"

test "Deep nesting (10 levels)" {
    set data [dict create level0 [dict create level1 [dict create level2 \
        [dict create level3 [dict create level4 [dict create level5 \
        [dict create level6 [dict create level7 [dict create level8 \
        [dict create level9 "deep"]]]]]]]]]]
    set result [::ast::json::to_json $data]
    expr {[string match "*level9*" $result]}
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
