#!/usr/bin/env tclsh
# tests/tcl/core/ast/parsers/test_variables.tcl
# Tests for variable operations parser

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname [file dirname [file dirname $script_dir]]]]]

source [file join $project_root tcl core tokenizer.tcl]
source [file join $project_root tcl core ast utils.tcl]
source [file join $project_root tcl core ast parsers variables.tcl]

set total 0
set passed 0

proc test {name code expected_type} {
    global total passed
    incr total

    if {[catch {
        set result [::ast::parsers::parse_variable $code 1 1 0]
        set type [dict get $result type]

        if {$type eq $expected_type} {
            puts "✓ PASS: $name"
            incr passed
        } else {
            puts "✗ FAIL: $name - Expected $expected_type, got $type"
        }
    } err]} {
        puts "✗ FAIL: $name - Error: $err"
    }
}

puts "Variable Parser Tests"
puts "=====================\n"

# set command
test "Simple set" "set x 1" "set"
test "Set with string" "set name \"value\"" "set"
test "Set with variable reference" "set y \$x" "set"

# variable command
test "Variable declaration" "variable x 10" "variable"
test "Variable without default" "variable y" "variable"

# global command
test "Global variable" "global debug" "global"
test "Multiple globals" "global x y z" "global"

# upvar command
test "Simple upvar" "upvar 1 myvar localvar" "upvar"
test "Upvar with level" "upvar #0 globalvar localvar" "upvar"

# array command
test "Array set" "array set myarray \{a 1 b 2\}" "array"
test "Array get" "array get myarray" "array"
test "Array exists" "array exists myarray" "array"

puts "\nResults: $passed/$total passed"
exit [expr {$passed == $total ? 0 : 1}]
