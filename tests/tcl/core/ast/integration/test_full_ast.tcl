#!/usr/bin/env tclsh
# tests/tcl/core/ast/integration/test_full_ast.tcl
# Integration tests for complete AST building

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname [file dirname [file dirname $script_dir]]]]]
source [file join $project_root tcl core ast builder.tcl]

set total_tests 0
set passed_tests 0
set failed_tests 0

proc test {name code checks} {
    global total_tests passed_tests failed_tests
    incr total_tests
    
    if {[catch {
        set ast [::ast::build $code "test.tcl"]
        set all_passed 1
        
        foreach {check_name check_script expected} $checks {
            set result [uplevel 1 "set ast [list $ast]; $check_script"]
            if {$result != $expected} {
                puts "✗ FAIL: $name"
                puts "  Subcheck '$check_name' failed"
                puts "  Expected: $expected, Got: $result"
                set all_passed 0
                break
            }
        }
        
        if {$all_passed} {
            puts "✓ PASS: $name"
            incr passed_tests
        } else {
            incr failed_tests
        }
    } err]} {
        puts "✗ FAIL: $name - Error: $err"
        incr failed_tests
    }
}

puts "========================================="
puts "Full AST Integration Tests"
puts "========================================="
puts ""

# Test 1: Empty code
test "Empty code produces empty AST" "" {
    "has root type" {dict get $ast type} "root"
    "has no children" {llength [dict get $ast children]} 0
    "has no errors" {dict get $ast had_error} 0
}

# Test 2: Simple set command
test "Single set command" "set x 1" {
    "has root type" {dict get $ast type} "root"
    "has 1 child" {llength [dict get $ast children]} 1
    "child is set" {dict get [lindex [dict get $ast children] 0] type} "set"
    "set has var_name" {dict exists [lindex [dict get $ast children] 0] var_name} 1
}

# Test 3: Simple proc
test "Simple procedure" "proc hello \{\} \{ puts \"Hi\" \}" {
    "has root type" {dict get $ast type} "root"
    "has 1 child" {llength [dict get $ast children]} 1
    "child is proc" {dict get [lindex [dict get $ast children] 0] type} "proc"
    "proc has name" {dict get [lindex [dict get $ast children] 0] name} "hello"
}

# Test 4: Multiple commands
test "Multiple commands" "set x 1\nset y 2\nset z 3" {
    "has root type" {dict get $ast type} "root"
    "has 3 children" {llength [dict get $ast children]} 3
    "all are sets" {
        set children [dict get $ast children]
        expr {[dict get [lindex $children 0] type] eq "set" && \
              [dict get [lindex $children 1] type] eq "set" && \
              [dict get [lindex $children 2] type] eq "set"}
    } 1
}

# Test 5: Control flow
test "If statement" "if \{$x\} \{ puts yes \}" {
    "has root type" {dict get $ast type} "root"
    "has 1 child" {llength [dict get $ast children]} 1
    "child is if" {dict get [lindex [dict get $ast children] 0] type} "if"
}

# Test 6: Namespace
test "Namespace eval" "namespace eval MyNS \{ variable x 10 \}" {
    "has root type" {dict get $ast type} "root"
    "has 1 child" {llength [dict get $ast children]} 1
    "child is namespace" {dict get [lindex [dict get $ast children] 0] type} "namespace"
}

# Test 7: Comments are extracted
test "Comments are tracked" "# Comment\nset x 1" {
    "has root type" {dict get $ast type} "root"
    "has comments" {llength [dict get $ast comments]} 1
    "has 1 child" {llength [dict get $ast children]} 1
}

# Test 8: Syntax error detection
test "Detects incomplete code" "proc test \{" {
    "detects error" {dict get $ast had_error} 1
    "has errors list" {llength [dict get $ast errors]} 1
}

# Test 9: Complex realistic code
test "Complex realistic TCL" {proc calculate {x y} {
    global debug
    set result [expr {$x + $y}]
    if {$result > 100} {
        puts "Large"
    }
    return $result
}} {
    "has root type" {dict get $ast type} "root"
    "has 1 child" {llength [dict get $ast children]} 1
    "child is proc" {dict get [lindex [dict get $ast children] 0] type} "proc"
    "proc name is calculate" {dict get [lindex [dict get $ast children] 0] name} "calculate"
}

# Test 10: JSON conversion works
test "AST converts to JSON without errors" "set x 1\nset y 2" {
    "JSON is not empty" {expr {[string length [::ast::to_json $ast]] > 0}} 1
    "JSON contains root" {string match "*root*" [::ast::to_json $ast]} 1
}

puts ""
puts "========================================="
puts "Test Results"
puts "========================================="
puts "Total:  $total_tests"
puts "Passed: $passed_tests"
puts "Failed: $failed_tests"
puts ""

if {$failed_tests == 0} {
    puts "✓ ALL INTEGRATION TESTS PASSED"
    exit 0
} else {
    puts "✗ SOME TESTS FAILED"
    exit 1
}
