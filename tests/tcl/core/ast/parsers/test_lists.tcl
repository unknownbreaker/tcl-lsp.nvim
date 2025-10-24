#!/usr/bin/env tclsh
# tests/tcl/core/ast/parsers/test_lists.tcl
# Tests for list operations parser

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname [file dirname [file dirname $script_dir]]]]]

# Load dependencies (FIXED: Added delimiters.tcl)
source [file join $project_root tcl core tokenizer.tcl]
source [file join $project_root tcl core ast utils.tcl]
source [file join $project_root tcl core ast delimiters.tcl]
source [file join $project_root tcl core ast parsers lists.tcl]

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

puts "List Parser Tests"
puts "=================\n"

# list command - use parse_list
test "Simple list" "list a b c" ::ast::parsers::lists::parse_list "list"
test "Empty list" "list" ::ast::parsers::lists::parse_list "list"
test "List with spaces" "list \"hello world\" test" ::ast::parsers::lists::parse_list "list"

# lappend command - use parse_lappend
test "Simple lappend" "lappend mylist element" ::ast::parsers::lists::parse_lappend "lappend"
test "Lappend multiple" "lappend mylist a b c" ::ast::parsers::lists::parse_lappend "lappend"

# puts command - use parse_puts
test "Simple puts" "puts \"hello\"" ::ast::parsers::lists::parse_puts "puts"
test "Puts to channel" "puts \$channel \"data\"" ::ast::parsers::lists::parse_puts "puts"
test "Puts with -nonewline" "puts -nonewline \"text\"" ::ast::parsers::lists::parse_puts "puts"

puts "\nResults: $passed/$total passed"
exit [expr {$passed == $total ? 0 : 1}]
