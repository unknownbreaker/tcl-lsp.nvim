#!/usr/bin/env tclsh
# tests/tcl/core/ast/parsers/test_procedures.tcl
# Tests for procedure parser module

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname [file dirname [file dirname $script_dir]]]]]

# Load dependencies
source [file join $project_root tcl core tokenizer.tcl]
source [file join $project_root tcl core ast utils.tcl]
source [file join $project_root tcl core ast parsers procedures.tcl]

set total 0
set passed 0

proc test {name code expected_type} {
    global total passed
    incr total

    if {[catch {
        # UPDATED: Use modular namespace structure
        set result [::ast::parsers::procedures::parse_proc $code 1 1 0]
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

puts "Procedure Parser Tests"
puts "======================\n"

test "Simple proc no args" "proc hello \{\} \{\}" "proc"
test "Proc with args" "proc add \{a b\} \{\}" "proc"
test "Proc with defaults" "proc test \{x \{y 10\}\} \{\}" "proc"
test "Proc with varargs" "proc test \{args\} \{\}" "proc"
test "Complex proc" "proc complex \{a \{b 1\} args\} \{puts hello\}" "proc"

puts "\nResults: $passed/$total passed"
exit [expr {$passed == $total ? 0 : 1}]
