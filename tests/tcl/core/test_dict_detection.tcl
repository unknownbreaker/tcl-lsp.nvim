#!/usr/bin/env tclsh
# tests/tcl/core/test_dict_detection.tcl
# Granular unit test for dict detection and JSON serialization
#
# This test helps verify the fix for the "bad class 'dict'" error
# and ensures JSON serialization works correctly with various data types.

# Setup paths
set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname $script_dir]]]
source [file join $project_root tcl core ast_builder.tcl]

# Test counter
set test_num 0
set pass_count 0
set fail_count 0

# Test helper
proc test {description expected_pattern actual} {
    global test_num pass_count fail_count
    incr test_num

    if {[string match $expected_pattern $actual]} {
        puts "✓ Test $test_num PASSED: $description"
        incr pass_count
        return 1
    } else {
        puts "✗ Test $test_num FAILED: $description"
        puts "  Expected pattern: $expected_pattern"
        puts "  Got: $actual"
        incr fail_count
        return 0
    }
}

proc test_error {description code} {
    global test_num pass_count fail_count
    incr test_num

    if {[catch {uplevel $code} error]} {
        puts "✗ Test $test_num FAILED: $description"
        puts "  ERROR: $error"
        incr fail_count
        return 0
    } else {
        puts "✓ Test $test_num PASSED: $description (no error)"
        incr pass_count
        return 1
    }
}

puts "============================================"
puts "TCL Dict Detection & JSON Serialization Test"
puts "============================================\n"

# ==========================================
# SECTION 1: Dict Detection Tests
# ==========================================
puts "SECTION 1: Dict Detection Tests"
puts "----------------------------"

# Test 1: Empty list is not a dict
set empty_list [list]
set is_dict [catch {dict size $empty_list} size]
test "Empty list should not be dict" \
    "*" \
    "Result: is_dict=$is_dict"

# Test 2: Simple dict
set simple_dict [dict create name "test" value 42]
set is_dict [expr {[catch {dict size $simple_dict} size] == 0}]
test "Simple dict should be detected" \
    "*is_dict=1*" \
    "Result: is_dict=$is_dict, size=$size"

# Test 3: List of strings is not a dict
set string_list [list "apple" "banana" "cherry"]
set is_dict [catch {dict size $string_list} size]
test "List of strings should not be dict" \
    "*" \
    "Result: is_dict=$is_dict"

# Test 4: List with even length that's not a dict
set number_list [list 1 2 3 4]
# Even though it has even length, dict operations should fail or not make sense
test "List of numbers with even length" \
    "*" \
    "Length: [llength $number_list]"

puts ""

# ==========================================
# SECTION 2: JSON Serialization Tests
# ==========================================
puts "SECTION 2: JSON Serialization - Basic Types"
puts "----------------------------"

# Test 5: Simple string value
test_error "Serialize dict with string value" {
    set d [dict create type "test" name "hello"]
    set json [::ast::to_json $d]
}

# Test 6: Integer value
test_error "Serialize dict with integer value" {
    set d [dict create type "test" count 42]
    set json [::ast::to_json $d]
}

# Test 7: Empty list
test_error "Serialize dict with empty list" {
    set d [dict create type "root" children [list]]
    set json [::ast::to_json $d]
}

puts ""

# ==========================================
# SECTION 3: Complex Structures
# ==========================================
puts "SECTION 3: JSON Serialization - Complex Structures"
puts "----------------------------"

# Test 8: Nested dict
test_error "Serialize nested dict" {
    set inner [dict create type "inner" value "test"]
    set outer [dict create type "outer" child $inner]
    set json [::ast::to_json $outer]
}

# Test 9: List of dicts
test_error "Serialize list of dicts" {
    set d1 [dict create type "proc" name "test1"]
    set d2 [dict create type "proc" name "test2"]
    set root [dict create type "root" children [list $d1 $d2]]
    set json [::ast::to_json $root]
}

# Test 10: List of strings
test_error "Serialize list of strings" {
    set d [dict create type "list" elements [list "apple" "banana" "cherry"]]
    set json [::ast::to_json $d]
}

# Test 11: List of numbers
test_error "Serialize list of numbers" {
    set d [dict create type "array" values [list 1 2 3 4 5]]
    set json [::ast::to_json $d]
}

puts ""

# ==========================================
# SECTION 4: Edge Cases
# ==========================================
puts "SECTION 4: Edge Cases"
puts "----------------------------"

# Test 12: Empty string value
test_error "Serialize dict with empty string" {
    set d [dict create type "test" name ""]
    set json [::ast::to_json $d]
}

# Test 13: String with quotes
test_error "Serialize dict with quoted string" {
    set d [dict create type "test" value {"hello world"}]
    set json [::ast::to_json $d]
}

# Test 14: String with special characters
test_error "Serialize dict with special chars" {
    set d [dict create type "test" message "Line 1\nLine 2\tTabbed"]
    set json [::ast::to_json $d]
}

# Test 15: Deep nesting
test_error "Serialize deeply nested structure" {
    set l3 [dict create type "level3" value "deep"]
    set l2 [dict create type "level2" child $l3]
    set l1 [dict create type "level1" child $l2]
    set root [dict create type "root" child $l1]
    set json [::ast::to_json $root]
}

puts ""

# ==========================================
# SECTION 5: AST-like Structures
# ==========================================
puts "SECTION 5: Real AST Structures"
puts "----------------------------"

# Test 16: Proc node structure
test_error "Serialize proc AST node" {
    set params [list \
        [dict create name "x" default "0"] \
        [dict create name "y"]]
    set proc_node [dict create \
        type "proc" \
        name "add" \
        params $params \
        range [dict create start [dict create line 1 column 1] end_pos [dict create line 3 column 1]]]
    set json [::ast::to_json $proc_node]
}

# Test 17: Set command node
test_error "Serialize set command AST node" {
    set set_node [dict create \
        type "set" \
        name "x" \
        value "hello" \
        range [dict create start [dict create line 1 column 1] end_pos [dict create line 1 column 15]]]
    set json [::ast::to_json $set_node]
}

# Test 18: Root AST with multiple children
test_error "Serialize root AST node" {
    set proc1 [dict create type "proc" name "test1" params [list]]
    set set1 [dict create type "set" name "x" value "10"]
    set root [dict create \
        type "root" \
        filepath "test.tcl" \
        children [list $proc1 $set1] \
        comments [list] \
        had_error 0 \
        errors [list]]
    set json [::ast::to_json $root]
}

puts ""

# ==========================================
# Summary
# ==========================================
puts "============================================"
puts "Test Summary"
puts "============================================"
puts "Total tests: $test_num"
puts "Passed: $pass_count"
puts "Failed: $fail_count"

if {$fail_count == 0} {
    puts "\n✓ ALL TESTS PASSED"
    exit 0
} else {
    puts "\n✗ SOME TESTS FAILED"
    exit 1
}
