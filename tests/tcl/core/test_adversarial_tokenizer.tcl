#!/usr/bin/env tclsh
# tests/tcl/core/test_adversarial_tokenizer.tcl
# ADVERSARIAL TESTS - Breaking the tokenizer with malformed TCL

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname $script_dir]]]
set core_dir [file join $project_root tcl core]
source [file join $core_dir tokenizer.tcl]

set total_tests 0
set passed_tests 0
set crashed_tests 0

proc test {name text expected_crash} {
    global total_tests passed_tests crashed_tests
    incr total_tests

    if {[catch {::tokenizer::count_tokens $text} result]} {
        if {$expected_crash} {
            puts "EXPECTED CRASH: $name"
            incr passed_tests
        } else {
            puts "UNEXPECTED CRASH: $name"
            puts "  Error: $result"
            incr crashed_tests
        }
        return
    }

    # Also test get_token on first token
    if {[catch {::tokenizer::get_token $text 0} token]} {
        if {$expected_crash} {
            puts "EXPECTED CRASH (get_token): $name"
            incr passed_tests
        } else {
            puts "UNEXPECTED CRASH (get_token): $name"
            puts "  Error: $token"
            incr crashed_tests
        }
        return
    }

    puts "SURVIVED: $name (count=$result, token=\[$token\])"
    incr passed_tests
}

puts "========================================="
puts "ADVERSARIAL TOKENIZER TESTS"
puts "========================================="
puts ""

# ATTACK 1: Unbalanced delimiters
puts "ATTACK 1: Unbalanced Delimiters"
puts "-----------------------------------------"

test "Unclosed brace" "\{hello" false
test "Unclosed quote" "\"hello" false
test "Unclosed bracket" "\[expr 1" false
test "Triple open brace" "\{\{\{" false
test "Mixed unclosed" "\{\"test \[expr" false
test "Only closing brace" "\}" false
test "Only closing quote" "\"" false
test "Only closing bracket" "\]" false

puts ""

# ATTACK 2: Empty and whitespace
puts "ATTACK 2: Empty and Whitespace"
puts "-----------------------------------------"

test "Empty string" "" false
test "Only spaces" "     " false
test "Only tabs" "\t\t\t" false
test "Only newlines" "\n\n\n" false
test "Mixed whitespace" " \t\n \t\n" false

puts ""

# ATTACK 3: Escape character abuse
puts "ATTACK 3: Escape Character Abuse"
puts "-----------------------------------------"

test "Trailing backslash" "set x \\" false
test "Multiple trailing backslashes" "set x \\\\\\\\" false
test "Escaped newline" "set x \\\nvalue" false
test "Escaped everything" "\\s\\e\\t \\ \\x" false
test "Backslash in braces" "\{test \\ value\}" false
test "Backslash in quotes" "\"test \\ value\"" false

puts ""

# ATTACK 4: Nested structures
puts "ATTACK 4: Deeply Nested Structures"
puts "-----------------------------------------"

test "100 levels of braces" [string repeat "\{" 100] false
test "100 levels of brackets" [string repeat "\[" 100] false
test "Alternating delimiters" "\{\"\[\{\"\[\{\"\[" false
test "Nested with escapes" "\{test \\\{inner\\\} outer\}" false

puts ""

# ATTACK 5: Special characters
puts "ATTACK 5: Special Characters"
puts "-----------------------------------------"

test "Null byte" "set x \x00" false
test "Control characters" "set x \x01\x02\x03" false
test "Unicode emoji" "set x 🔥" false
test "Right-to-left" "set x \u202E" false
test "Zero-width space" "set x test\u200Bvalue" false

puts ""

# ATTACK 6: Huge inputs
puts "ATTACK 6: Resource Exhaustion"
puts "-----------------------------------------"

test "10K character token" "set x [string repeat "A" 10000]" false
test "10K brace depth" [string repeat "\{" 10000] false
test "1000 tokens" [string repeat "word " 1000] false

puts ""

# ATTACK 7: Command separator abuse
puts "ATTACK 7: Command Separator Abuse"
puts "-----------------------------------------"

test "Multiple semicolons" ";;;;;;;" false
test "Semicolon in brace" "\{test;value\}" false
test "Semicolon in quote" "\"test;value\"" false
test "Semicolon after backslash" "test\\;value" false

puts ""

# ATTACK 8: Variable substitution chars
puts "ATTACK 8: Variable Substitution"
puts "-----------------------------------------"

test "Dollar sign alone" "\$" false
test "Multiple dollars" "\$\$\$\$" false
test "Dollar in brace" "\{test \$ value\}" false
test "Dollar in quote" "\"test \$ value\"" false
test "Unclosed dollar brace" "\$\{var" false

puts ""

# ATTACK 9: Real TCL syntax errors
puts "ATTACK 9: Real TCL Syntax Errors"
puts "-----------------------------------------"

test "Missing proc body" "proc test \{\}" false
test "Incomplete set" "set x" false
test "Invalid command" "\x00\x01\x02" false
test "Just a comment" "# comment only" false
test "Comment with unclosed brace" "# test \{" false

puts ""

# ATTACK 10: Edge case combinations
puts "ATTACK 10: Edge Case Combinations"
puts "-----------------------------------------"

test "Empty braces" "\{\}" false
test "Empty brackets" "\[\]" false
test "Empty quotes" "\"\"" false
test "Brace with only space" "\{ \}" false
test "Quote with only tab" "\"\t\"" false
test "Nested empty" "\{\[\"\"\]\}" false

puts ""

puts "========================================="
puts "ADVERSARIAL TOKENIZER RESULTS"
puts "========================================="
puts "Total Tests:      $total_tests"
puts "Survived:         $passed_tests"
puts "Crashed:          $crashed_tests"
puts ""

if {$crashed_tests > 0} {
    puts "CRITICAL: $crashed_tests tests caused unexpected crashes!"
    exit 1
} else {
    puts "EXCELLENT: Tokenizer handled all adversarial inputs!"
    exit 0
}
