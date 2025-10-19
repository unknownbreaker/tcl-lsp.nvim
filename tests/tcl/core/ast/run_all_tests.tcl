#!/usr/bin/env tclsh
# tests/tcl/core/ast/run_all_tests.tcl
# Master test runner - runs all AST module tests

puts "========================================="
puts "TCL AST Module Test Suite"
puts "========================================="
puts ""

set test_dir [file dirname [file normalize [info script]]]
set total_suites 0
set passed_suites 0
set failed_suites 0

# Test results summary
set results [list]

proc run_test_suite {name filepath} {
    global total_suites passed_suites failed_suites results
    incr total_suites
    
    puts "Running: $name"
    puts [string repeat "-" 60]
    
    if {[catch {exec tclsh $filepath} output]} {
        set exit_code 1
    } else {
        set exit_code 0
    }
    
    puts $output
    puts ""
    
    if {$exit_code == 0} {
        incr passed_suites
        lappend results [list $name "PASS"]
    } else {
        incr failed_suites
        lappend results [list $name "FAIL"]
    }
}

# Run all test suites
puts "UNIT TESTS"
puts "========================================="
puts ""

run_test_suite "JSON Serialization" \
    [file join $test_dir test_json.tcl]

run_test_suite "Utilities" \
    [file join $test_dir test_utils.tcl]

run_test_suite "Comment Extraction" \
    [file join $test_dir test_comments.tcl]

run_test_suite "Command Extraction" \
    [file join $test_dir test_commands.tcl]

puts ""
puts "PARSER TESTS"
puts "========================================="
puts ""

run_test_suite "Procedure Parser" \
    [file join $test_dir parsers test_procedures.tcl]

run_test_suite "Variable Parser" \
    [file join $test_dir parsers test_variables.tcl]

run_test_suite "Control Flow Parser" \
    [file join $test_dir parsers test_control_flow.tcl]

run_test_suite "Namespace Parser" \
    [file join $test_dir parsers test_namespaces.tcl]

run_test_suite "Package Parser" \
    [file join $test_dir parsers test_packages.tcl]

run_test_suite "Expression Parser" \
    [file join $test_dir parsers test_expressions.tcl]

run_test_suite "List Parser" \
    [file join $test_dir parsers test_lists.tcl]

puts ""
puts "INTEGRATION TESTS"
puts "========================================="
puts ""

run_test_suite "Full AST Integration" \
    [file join $test_dir integration test_full_ast.tcl]

# Print summary
puts ""
puts "========================================="
puts "TEST SUITE SUMMARY"
puts "========================================="
puts ""

# Print table header
puts [format "%-40s %s" "Test Suite" "Status"]
puts [string repeat "=" 60]

# Print each result
foreach result $results {
    lassign $result name status
    if {$status eq "PASS"} {
        puts [format "%-40s ✓ %s" $name $status]
    } else {
        puts [format "%-40s ✗ %s" $name $status]
    }
}

puts [string repeat "=" 60]
puts ""
puts "Total Suites:  $total_suites"
puts "Passed:        $passed_suites"
puts "Failed:        $failed_suites"
puts ""

if {$failed_suites == 0} {
    puts "✓ ALL TEST SUITES PASSED"
    puts ""
    puts "Ready for deployment!"
    exit 0
} else {
    puts "✗ SOME TEST SUITES FAILED"
    puts ""
    puts "Please review failures above."
    exit 1
}
