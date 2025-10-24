#!/usr/bin/env tclsh
# tests/tcl/core/ast/parsers/test_variables.tcl
# Tests for variable operations parser

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname [file dirname [file dirname $script_dir]]]]]

# Load dependencies (FIXED: Added delimiters.tcl)
source [file join $project_root tcl core tokenizer.tcl]
source [file join $project_root tcl core ast utils.tcl]
source [file join $project_root tcl core ast delimiters.tcl]
source [file join $project_root tcl core ast parsers variables.tcl]

set total 0
set passed 0

proc test {name code parser_func expected_type} {
    global total passed
    incr total

    if {[catch {
        # FIXED: Call specific parser function for each command type
        set result [$parser_func $code 1 1 0]
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

# set command - use parse_set
test "Simple set" "set x 1" ::ast::parsers::variables::parse_set "set"
test "Set with string" "set name \"value\"" ::ast::parsers::variables::parse_set "set"
test "Set with variable reference" "set y \$x" ::ast::parsers::variables::parse_set "set"

# variable command - use parse_variable
test "Variable declaration" "variable x 10" ::ast::parsers::variables::parse_variable "variable"
test "Variable without default" "variable y" ::ast::parsers::variables::parse_variable "variable"

# global command - use parse_global
test "Global variable" "global debug" ::ast::parsers::variables::parse_global "global"
test "Multiple globals" "global x y z" ::ast::parsers::variables::parse_global "global"

# upvar command - use parse_upvar
test "Simple upvar" "upvar 1 myvar localvar" ::ast::parsers::variables::parse_upvar "upvar"
test "Upvar with level" "upvar #0 globalvar localvar" ::ast::parsers::variables::parse_upvar "upvar"

# array command - use parse_array
test "Array set" "array set myarray \{a 1 b 2\}" ::ast::parsers::variables::parse_array "array"
test "Array get" "array get myarray" ::ast::parsers::variables::parse_array "array"
test "Array exists" "array exists myarray" ::ast::parsers::variables::parse_array "array"

puts "\nResults: $passed/$total passed"
exit [expr {$passed == $total ? 0 : 1}]
