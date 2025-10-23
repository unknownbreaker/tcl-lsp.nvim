#!/usr/bin/env tclsh
# tests/tcl/core/ast/integration/test_full_ast.tcl
# Full AST integration tests

set script_dir [file dirname [file normalize [info script]]]
set ast_dir [file join [file dirname [file dirname [file dirname [file dirname [file dirname $script_dir]]]]] tcl core ast]
source [file join $ast_dir builder.tcl]

set total 0
set passed 0

proc test {name code checks} {
    global total passed
    incr total

    if {[catch {
        set ast [::ast::build $code "<test>"]

        set all_passed 1
        foreach {check_name check_script expected} $checks {
            # Use upvar to make $ast available in check_script
            if {[catch {
                set result [eval $check_script]
            } err]} {
                puts "✗ FAIL: $name - $check_name (Error: $err)"
                set all_passed 0
                break
            }
            if {$result != $expected} {
                puts "✗ FAIL: $name - $check_name (Expected: $expected, Got: $result)"
                set all_passed 0
                break
            }
        }

        if {$all_passed} {
            puts "✓ PASS: $name"
            incr passed
        }
    } err]} {
        puts "✗ FAIL: $name - Error: $err"
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
}

# Test 5: Control flow (escaped dollar sign)
test "If statement" "if \{\$x\} \{ puts yes \}" {
    "has root type" {dict get $ast type} "root"
    "has 1 child" {llength [dict get $ast children]} 1
}

# Test 6: Namespace
test "Namespace eval" "namespace eval MyNS \{ variable x 10 \}" {
    "has root type" {dict get $ast type} "root"
    "has 1 child" {llength [dict get $ast children]} 1
}

puts ""
puts "========================================="
puts "Test Results"
puts "========================================="
puts "Total:  $total"
puts "Passed: $passed"
puts ""

if {$passed == $total} {
    puts "✓ ALL TESTS PASSED"
    exit 0
} else {
    puts "✗ SOME TESTS FAILED"
    exit 1
}
