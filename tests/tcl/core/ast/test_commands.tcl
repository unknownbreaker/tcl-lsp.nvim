#!/usr/bin/env tclsh
# tests/tcl/core/ast/test_commands.tcl
# Tests for command extraction module

set script_dir [file dirname [file normalize [info script]]]
set ast_dir [file join [file dirname [file dirname [file dirname [file dirname $script_dir]]]] tcl core ast]
source [file join $ast_dir commands.tcl]

set total 0
set passed 0

proc test {name code expected_count} {
    global total passed
    incr total
    
    set result [::ast::commands::extract $code 1]
    set count [llength $result]
    
    if {$count == $expected_count} {
        puts "✓ PASS: $name"
        incr passed
    } else {
        puts "✗ FAIL: $name - Expected $expected_count commands, got $count"
    }
}

puts "Command Extraction Tests"
puts "========================\n"

test "Single command" "set x 1" 1
test "Two commands" "set x 1\nset y 2" 2
test "Three commands" "set x 1\nset y 2\nset z 3" 3
test "Multiline proc" "proc test \{\} \{\n    puts hello\n\}" 1
test "Commands with comments" "# Comment\nset x 1\n# Another\nset y 2" 2
test "Empty lines" "set x 1\n\nset y 2" 2
test "Command with nested braces" "if \{$x\} \{\n    puts yes\n\}" 1
test "For loop" "for \{set i 0\} \{$i < 10\} \{incr i\} \{\n    puts $i\n\}" 1
test "Multiple procs" "proc a \{\} \{\}\nproc b \{\} \{\}" 2
test "Empty code" "" 0

puts "\nResults: $passed/$total passed"
exit [expr {$passed == $total ? 0 : 1}]
