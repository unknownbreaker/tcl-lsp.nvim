#!/usr/bin/env tclsh
# tests/tcl/core/ast/parsers/test_lists.tcl
# Tests for list operations parser

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname [file dirname [file dirname $script_dir]]]]]

source [file join $project_root tcl core tokenizer.tcl]
source [file join $project_root tcl core ast utils.tcl]
source [file join $project_root tcl core ast parsers lists.tcl]

set total 0
set passed 0

proc test {name code expected_type} {
    global total passed
    incr total
    
    if {[catch {
        set result [::ast::parsers::parse_list $code 1 1]
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

puts "List Parser Tests"
puts "=================\n"

# list command
test "Simple list" "list a b c" "list"
test "Empty list" "list" "list"
test "List with spaces" "list \"hello world\" test" "list"

# lappend command
test "Simple lappend" "lappend mylist element" "lappend"
test "Lappend multiple" "lappend mylist a b c" "lappend"

# puts command
test "Simple puts" "puts \"hello\"" "puts"
test "Puts to channel" "puts \$channel \"data\"" "puts"
test "Puts with -nonewline" "puts -nonewline \"text\"" "puts"

puts "\nResults: $passed/$total passed"
exit [expr {$passed == $total ? 0 : 1}]
