#!/usr/bin/env tclsh
# tests/tcl/core/test_tokenizer.tcl
# Test Suite for Literal Tokenizer
#
# This test suite verifies that the tokenizer correctly extracts tokens
# from TCL source code without evaluation, preserving the exact text
# representation as it appears in the source.

# Load the tokenizer
set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname $script_dir]]]
source [file join $project_root tcl core tokenizer.tcl]

# ===========================================================================
# TEST FRAMEWORK
# ===========================================================================

namespace eval ::test {
    variable total_tests 0
    variable passed_tests 0
    variable failed_tests 0
    variable current_suite ""
}

# Start a new test suite
proc ::test::suite {name} {
    variable current_suite
    set current_suite $name
    puts "\n=========================================="
    puts "Test Suite: $name"
    puts "=========================================="
}

# Run a single test
proc ::test::run {test_name code expected_result} {
    variable total_tests
    variable passed_tests
    variable failed_tests
    variable current_suite

    incr total_tests

    puts -nonewline "\nTest: $test_name"
    puts "\n  Input: $code"

    set actual_result [::tokenizer::tokenize $code]
    puts "  Expected: $expected_result"
    puts "  Actual:   $actual_result"

    if {$actual_result eq $expected_result} {
        puts "  ✓ PASS"
        incr passed_tests
        return 1
    } else {
        puts "  ✗ FAIL"
        puts "  Difference:"

        # Show detailed differences
        set exp_len [llength $expected_result]
        set act_len [llength $actual_result]
        set max_len [expr {$exp_len > $act_len ? $exp_len : $act_len}]

        for {set i 0} {$i < $max_len} {incr i} {
            set exp_token [lindex $expected_result $i]
            set act_token [lindex $actual_result $i]

            if {$exp_token ne $act_token} {
                puts "    Token \[$i\]:"
                puts "      Expected: '$exp_token'"
                puts "      Actual:   '$act_token'"
            }
        }

        incr failed_tests
        return 0
    }
}

# Print test summary
proc ::test::summary {} {
    variable total_tests
    variable passed_tests
    variable failed_tests

    puts "\n=========================================="
    puts "TEST SUMMARY"
    puts "=========================================="
    puts "Total:  $total_tests"
    puts "Passed: $passed_tests"
    puts "Failed: $failed_tests"

    if {$failed_tests == 0} {
        puts "\n✓ All tests passed!"
        return 0
    } else {
        puts "\n✗ Some tests failed"
        return 1
    }
}

# ===========================================================================
# BASIC TOKEN EXTRACTION TESTS
# ===========================================================================

::test::suite "Basic Token Extraction"

::test::run "Simple command with bare words" \
    {puts hello} \
    {puts hello}

::test::run "Command with multiple arguments" \
    {set x 42} \
    {set x 42}

::test::run "Command with spaces" \
    {set  x   42} \
    {set x 42}

# ===========================================================================
# QUOTED STRING TESTS
# ===========================================================================

::test::suite "Quoted String Extraction"

::test::run "Simple quoted string (CRITICAL TEST)" \
    {set x "hello"} \
    {set x {"hello"}}

::test::run "Quoted string with spaces" \
    {set msg "hello world"} \
    {set msg {"hello world"}}

::test::run "Empty quoted string" \
    {set empty ""} \
    {set empty {""}}

::test::run "Quoted string with escaped quotes" \
    {set text "say \"hello\""} \
    {set text {"say \"hello\""}}

::test::run "Quoted string with newline" \
    {set multiline "line1
line2"} \
    {set multiline {"line1
line2"}}

# ===========================================================================
# NUMERIC VALUE TESTS
# ===========================================================================

::test::suite "Numeric Value Extraction"

::test::run "Integer value (CRITICAL TEST)" \
    {set count 42} \
    {set count 42}

::test::run "Floating point value" \
    {set pi 3.14159} \
    {set pi 3.14159}

::test::run "Negative number" \
    {set temp -10} \
    {set temp -10}

::test::run "Zero" \
    {set zero 0} \
    {set zero 0}

# ===========================================================================
# VARIABLE SUBSTITUTION TESTS
# ===========================================================================

::test::suite "Variable Substitution Extraction"

::test::run "Simple variable reference" \
    {set x $y} \
    {set x {$y}}

::test::run "Variable in quotes" \
    {puts "$myvar"} \
    {puts {"$myvar"}}

::test::run "Braced variable reference" \
    {set x ${myvar}} \
    {set x {${myvar}}}

::test::run "Namespace qualified variable" \
    {set x $::namespace::var} \
    {set x {$::namespace::var}}

# ===========================================================================
# COMMAND SUBSTITUTION TESTS (CRITICAL)
# ===========================================================================

::test::suite "Command Substitution Extraction (CRITICAL)"

::test::run "Simple command substitution" \
    {set x [list a b c]} \
    {set x {[list a b c]}}

::test::run "Command substitution with braces (CRITICAL TEST)" \
    {set x [expr {1 + 2}]} \
    {set x {[expr {1 + 2}]}}

::test::run "Nested command substitution" \
    {set x [expr [expr 1]]} \
    {set x {[expr [expr 1]]}}

::test::run "Command substitution in quotes" \
    {set msg "result: [calc]"} \
    {set msg {"result: [calc]"}}

::test::run "Multiple command substitutions" \
    {set sum [expr $a + $b]} \
    {set sum {[expr $a + $b]}}

# ===========================================================================
# BRACED STRING TESTS
# ===========================================================================

::test::suite "Braced String Extraction"

::test::run "Simple braced string" \
    {set body {puts hello}} \
    {set body {{puts hello}}}

::test::run "Nested braces" \
    {set outer {inner {nested} text}} \
    {set outer {{inner {nested} text}}}

::test::run "Empty braces" \
    {set empty {}} \
    {set empty {{}}}

::test::run "Braces with special characters" \
    {set special {$var [cmd] "quoted"}} \
    {set special {{$var [cmd] "quoted"}}}

# ===========================================================================
# PROC DEFINITION TESTS
# ===========================================================================

::test::suite "Procedure Definition Extraction"

::test::run "Simple proc definition" \
    {proc test {} {puts hello}} \
    {proc test {{}} {{puts hello}}}

::test::run "Proc with arguments" \
    {proc add {a b} {expr $a + $b}} \
    {proc add {{a b}} {{expr $a + $b}}}

::test::run "Proc with default arguments" \
    {proc greet {name "World"} {puts "Hello, $name"}} \
    {proc greet {{name "World"}} {{puts "Hello, $name"}}}

# ===========================================================================
# COMPLEX MIXED SYNTAX TESTS
# ===========================================================================

::test::suite "Complex Mixed Syntax"

::test::run "Multiple commands on one line" \
    {set x 10; set y 20} \
    {set x 10}

::test::run "Command with all token types" \
    {set result [expr {$x + 10}]} \
    {set result {[expr {$x + 10}]}}

::test::run "Nested braces and brackets" \
    {if {$x > 0} {puts [format "x=%d" $x]}} \
    {if {{$x > 0}} {{puts [format "x=%d" $x]}}}

::test::run "Variable and command substitution" \
    {set msg "User: $name, ID: [get_id]"} \
    {set msg {"User: $name, ID: [get_id]"}}

# ===========================================================================
# EDGE CASES AND ERROR HANDLING
# ===========================================================================

::test::suite "Edge Cases and Error Handling"

::test::run "Empty string" \
    {} \
    {}

::test::run "Only whitespace" \
    {   } \
    {}

::test::run "Unclosed quote (error recovery)" \
    {set x "unclosed} \
    {set x {"unclosed}}

::test::run "Unclosed brace (error recovery)" \
    {set x {unclosed} \
    {set x {{unclosed}}

::test::run "Unclosed bracket (error recovery)" \
    {set x [unclosed} \
    {set x {[unclosed}}

# ===========================================================================
# SPECIFIC TOKEN ACCESS TESTS
# ===========================================================================

::test::suite "get_token Function Tests"

# Test getting specific tokens by index
proc test_get_token {test_name code index expected} {
    puts -nonewline "\nTest: $test_name"
    puts "\n  Input: $code"
    puts "  Getting index: $index"

    set actual [::tokenizer::get_token $code $index]
    puts "  Expected: '$expected'"
    puts "  Actual:   '$actual'"

    if {$actual eq $expected} {
        puts "  ✓ PASS"
        return 1
    } else {
        puts "  ✗ FAIL"
        return 0
    }
}

test_get_token "Get command name" \
    {set x "hello"} \
    0 \
    "set"

test_get_token "Get variable name" \
    {set x "hello"} \
    1 \
    "x"

test_get_token "Get quoted value" \
    {set x "hello"} \
    2 \
    {"hello"}

test_get_token "Get numeric value" \
    {set count 42} \
    2 \
    "42"

test_get_token "Get command substitution" \
    {set x [expr {1 + 2}]} \
    2 \
    {[expr {1 + 2}]}

test_get_token "Get out of range index" \
    {set x 42} \
    10 \
    ""

# ===========================================================================
# COUNT TOKENS TESTS
# ===========================================================================

::test::suite "count_tokens Function Tests"

proc test_count {test_name code expected_count} {
    puts -nonewline "\nTest: $test_name"
    puts "\n  Input: $code"

    set actual_count [::tokenizer::count_tokens $code]
    puts "  Expected count: $expected_count"
    puts "  Actual count:   $actual_count"

    if {$actual_count == $expected_count} {
        puts "  ✓ PASS"
        return 1
    } else {
        puts "  ✗ FAIL"
        return 0
    }
}

test_count "Count simple command" {set x 42} 3
test_count "Count empty string" {} 0
test_count "Count command with substitution" {set x [expr 1]} 3
test_count "Count proc definition" {proc test {} {puts hello}} 4

# ===========================================================================
# REAL-WORLD TCL CODE TESTS
# ===========================================================================

::test::suite "Real-World TCL Code Examples"

::test::run "Namespace definition" \
    {namespace eval ::myapp {}} \
    {namespace eval ::myapp {{}}}

::test::run "Package require" \
    {package require Tcl 8.6} \
    {package require Tcl 8.6}

::test::run "If statement" \
    {if {$x > 0} {puts positive}} \
    {if {{$x > 0}} {{puts positive}}}

::test::run "While loop" \
    {while {$i < 10} {incr i}} \
    {while {{$i < 10}} {{incr i}}}

::test::run "Foreach loop" \
    {foreach item $list {process $item}} \
    {foreach item {$list} {{process $item}}}

::test::run "Array set" \
    {array set config {host localhost port 8080}} \
    {array set config {{host localhost port 8080}}}

::test::run "String with variable and command" \
    {set msg "Count: $count, Max: [get_max]"} \
    {set msg {"Count: $count, Max: [get_max]"}}

# ===========================================================================
# PERFORMANCE TEST (Optional)
# ===========================================================================

::test::suite "Performance Test"

puts "\nPerformance test: Tokenizing 1000 commands"
set start_time [clock milliseconds]

for {set i 0} {$i < 1000} {incr i} {
    ::tokenizer::tokenize {set x [expr {$a + $b}]}
}

set end_time [clock milliseconds]
set elapsed [expr {$end_time - $start_time}]
puts "  Elapsed time: ${elapsed}ms"
puts "  Average: [expr {$elapsed / 1000.0}]ms per tokenization"

if {$elapsed < 1000} {
    puts "  ✓ PASS (Performance acceptable)"
} else {
    puts "  ✗ FAIL (Performance too slow)"
}

# ===========================================================================
# FINAL SUMMARY
# ===========================================================================

exit [::test::summary]
