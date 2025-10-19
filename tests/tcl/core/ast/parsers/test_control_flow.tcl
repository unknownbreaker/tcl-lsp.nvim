#!/usr/bin/env tclsh
# tests/tcl/core/ast/parsers/test_control_flow.tcl
# Tests for control flow parser

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname [file dirname [file dirname $script_dir]]]]]

source [file join $project_root tcl core tokenizer.tcl]
source [file join $project_root tcl core ast utils.tcl]
source [file join $project_root tcl core ast parsers control_flow.tcl]

set total 0
set passed 0

proc test {name code expected_type} {
    global total passed
    incr total
    
    if {[catch {
        set result [::ast::parsers::parse_control_flow $code 1 1 0]
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

puts "Control Flow Parser Tests"
puts "=========================\n"

# if statements
test "Simple if" "if \{\$x\} \{ puts yes \}" "if"
test "If-else" "if \{\$x\} \{ puts yes \} else \{ puts no \}" "if"
test "If-elseif-else" "if \{\$x > 0\} \{ puts pos \} elseif \{\$x < 0\} \{ puts neg \} else \{ puts zero \}" "if"

# while loops
test "Simple while" "while \{\$i < 10\} \{ incr i \}" "while"
test "While with complex condition" "while \{\$running && \$count > 0\} \{ process \}" "while"

# for loops
test "Simple for" "for \{set i 0\} \{\$i < 10\} \{incr i\} \{ puts \$i \}" "for"
test "For with step" "for \{set i 0\} \{\$i < 100\} \{incr i 10\} \{ puts \$i \}" "for"

# foreach loops
test "Simple foreach" "foreach item \$list \{ puts \$item \}" "foreach"
test "Foreach with multiple vars" "foreach \{key value\} \$pairs \{ puts \"\$key: \$value\" \}" "foreach"
test "Foreach multiple lists" "foreach x \$list1 y \$list2 \{ process \$x \$y \}" "foreach"

# switch statements
test "Simple switch" "switch \$value \{ a \{ puts A \} b \{ puts B \} \}" "switch"
test "Switch with default" "switch \$value \{ a \{ puts A \} default \{ puts other \} \}" "switch"
test "Switch with -exact" "switch -exact \$value \{ \"test\" \{ puts matched \} \}" "switch"

puts "\nResults: $passed/$total passed"
exit [expr {$passed == $total ? 0 : 1}]
