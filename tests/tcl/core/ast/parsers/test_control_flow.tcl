#!/usr/bin/env tclsh
# tests/tcl/core/ast/parsers/test_control_flow.tcl
# Tests for control flow parser

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname [file dirname [file dirname $script_dir]]]]]

# Load dependencies (FIXED: Added delimiters.tcl)
source [file join $project_root tcl core tokenizer.tcl]
source [file join $project_root tcl core ast utils.tcl]
source [file join $project_root tcl core ast delimiters.tcl]
source [file join $project_root tcl core ast parsers control_flow.tcl]

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

puts "Control Flow Parser Tests"
puts "=========================\n"

# if statements - use parse_if
test "Simple if" "if \{\$x\} \{ puts yes \}" ::ast::parsers::control_flow::parse_if "if"
test "If-else" "if \{\$x\} \{ puts yes \} else \{ puts no \}" ::ast::parsers::control_flow::parse_if "if"
test "If-elseif-else" "if \{\$x > 0\} \{ puts pos \} elseif \{\$x < 0\} \{ puts neg \} else \{ puts zero \}" ::ast::parsers::control_flow::parse_if "if"

# while loops - use parse_while
test "Simple while" "while \{\$i < 10\} \{ incr i \}" ::ast::parsers::control_flow::parse_while "while"
test "While with complex condition" "while \{\$running && \$count > 0\} \{ process \}" ::ast::parsers::control_flow::parse_while "while"

# for loops - use parse_for
test "Simple for" "for \{set i 0\} \{\$i < 10\} \{incr i\} \{ puts \$i \}" ::ast::parsers::control_flow::parse_for "for"
test "For with step" "for \{set i 0\} \{\$i < 100\} \{incr i 10\} \{ puts \$i \}" ::ast::parsers::control_flow::parse_for "for"

# foreach loops - use parse_foreach
test "Simple foreach" "foreach item \$list \{ puts \$item \}" ::ast::parsers::control_flow::parse_foreach "foreach"
test "Foreach with multiple vars" "foreach \{key value\} \$pairs \{ puts \"\$key: \$value\" \}" ::ast::parsers::control_flow::parse_foreach "foreach"
test "Foreach multiple lists" "foreach x \$list1 y \$list2 \{ process \$x \$y \}" ::ast::parsers::control_flow::parse_foreach "foreach"

# switch statements - use parse_switch
test "Simple switch" "switch \$value \{ a \{ puts A \} b \{ puts B \} \}" ::ast::parsers::control_flow::parse_switch "switch"
test "Switch with default" "switch \$value \{ a \{ puts A \} default \{ puts other \} \}" ::ast::parsers::control_flow::parse_switch "switch"
test "Switch with -exact" "switch -exact \$value \{ \"test\" \{ puts matched \} \}" ::ast::parsers::control_flow::parse_switch "switch"

puts "\nResults: $passed/$total passed"
exit [expr {$passed == $total ? 0 : 1}]
