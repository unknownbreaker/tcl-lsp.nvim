#!/usr/bin/env tclsh
# tests/tcl/core/ast/parsers/test_expressions.tcl
# Tests for expression parser

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname [file dirname [file dirname $script_dir]]]]]

source [file join $project_root tcl core tokenizer.tcl]
source [file join $project_root tcl core ast utils.tcl]
source [file join $project_root tcl core ast parsers expressions.tcl]

set total 0
set passed 0

proc test {name code expected_type} {
    global total passed
    incr total
    
    if {[catch {
        set result [::ast::parsers::parse_expr $code 1 1]
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

puts "Expression Parser Tests"
puts "=======================\n"

# expr command
test "Simple arithmetic" "expr \{1 + 2\}" "expr"
test "Expression with variables" "expr \{\$x + \$y\}" "expr"
test "Complex expression" "expr \{(\$a + \$b) * (\$c - \$d)\}" "expr"
test "Comparison" "expr \{\$x > 10\}" "expr"
test "Logical expression" "expr \{\$x > 0 && \$y < 100\}" "expr"
test "Function call" "expr \{sqrt(\$x)\}" "expr"
test "String comparison" "expr \{\$name eq \"test\"\}" "expr"

puts "\nResults: $passed/$total passed"
exit [expr {$passed == $total ? 0 : 1}]
