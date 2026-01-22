#!/usr/bin/env tclsh
# tests/tcl/core/ast/test_adversarial_json.tcl
# ADVERSARIAL TESTS - Breaking JSON serialization with edge cases
#
# This file contains malicious inputs designed to crash or expose bugs

set script_dir [file dirname [file normalize [info script]]]
set ast_dir [file join [file dirname [file dirname [file dirname [file dirname $script_dir]]]] tcl core ast]
source [file join $ast_dir json.tcl]

set total_tests 0
set passed_tests 0
set failed_tests 0
set crashed_tests 0

proc test {name script} {
    global total_tests passed_tests failed_tests crashed_tests
    incr total_tests

    if {[catch {uplevel 1 $script} result]} {
        puts "CRASH: $name"
        puts "  Error: $result"
        incr crashed_tests
        return 0
    }

    # Just check it didn't crash - we expect malformed output
    if {[string length $result] >= 0} {
        puts "SURVIVED: $name"
        incr passed_tests
        return 1
    } else {
        puts "FAIL: $name (returned invalid result)"
        incr failed_tests
        return 0
    }
}

puts "========================================="
puts "ADVERSARIAL JSON SERIALIZATION TESTS"
puts "Goal: Crash the serializer or expose bugs"
puts "========================================="
puts ""

# ATTACK 1: Null bytes and control characters
puts "ATTACK 1: Null Bytes and Control Characters"
puts "-----------------------------------------"

test "Null byte in string" {
    ::ast::json::to_json [dict create text "hello\x00world"]
}

test "ASCII control chars 0-31" {
    set evil ""
    for {set i 0} {$i < 32} {incr i} {
        append evil [format %c $i]
    }
    ::ast::json::to_json [dict create text $evil]
}

test "ASCII DEL character (127)" {
    ::ast::json::to_json [dict create text "test\x7ftest"]
}

test "Form feed and vertical tab" {
    ::ast::json::to_json [dict create text "line1\fline2\vline3"]
}

test "Bell character" {
    ::ast::json::to_json [dict create text "beep\x07test"]
}

puts ""

# ATTACK 2: Unicode edge cases
puts "ATTACK 2: Unicode and Encoding Attacks"
puts "-----------------------------------------"

test "Emoji in key" {
    ::ast::json::to_json [dict create "💀" "skull"]
}

test "Emoji in value" {
    ::ast::json::to_json [dict create text "Hello 🌍 World"]
}

test "Zero-width characters" {
    ::ast::json::to_json [dict create text "hello\u200Bworld"]
}

test "Right-to-left override" {
    ::ast::json::to_json [dict create text "test\u202Eevil"]
}

test "Combining characters" {
    ::ast::json::to_json [dict create text "a\u0301\u0302\u0303"]
}

test "UTF-8 BOM" {
    ::ast::json::to_json [dict create text "\uFEFFtest"]
}

puts ""

# ATTACK 3: Deeply nested structures
puts "ATTACK 3: Deep Nesting (Stack Overflow?)"
puts "-----------------------------------------"

test "100 levels of dict nesting" {
    set data [dict create value "deep"]
    for {set i 0} {$i < 100} {incr i} {
        set data [dict create "level$i" $data]
    }
    ::ast::json::to_json $data
}

test "100 levels of list nesting" {
    set data [list "deep"]
    for {set i 0} {$i < 100} {incr i} {
        set data [list $data]
    }
    ::ast::json::to_json [dict create nested $data]
}

test "1000 element list" {
    set biglist {}
    for {set i 0} {$i < 1000} {incr i} {
        lappend biglist "item$i"
    }
    ::ast::json::to_json [dict create items $biglist]
}

test "1000 key dict" {
    set bigdict [dict create]
    for {set i 0} {$i < 1000} {incr i} {
        dict set bigdict "key$i" "value$i"
    }
    ::ast::json::to_json $bigdict
}

puts ""

# ATTACK 4: TCL special characters
puts "ATTACK 4: TCL Special Characters"
puts "-----------------------------------------"

test "Dollar signs (variable expansion)" {
    ::ast::json::to_json [dict create text "\$var \${array(key)}"]
}

test "Brackets (command substitution)" {
    ::ast::json::to_json [dict create text "\[expr 1+1\]"]
}

test "Unbalanced braces in value" {
    ::ast::json::to_json [dict create text "\{\{\{"]
}

test "Unbalanced quotes in value" {
    ::ast::json::to_json [dict create text "\"\"\""]
}

test "Backslash nightmare" {
    ::ast::json::to_json [dict create text "\\\\\\\\\\"]
}

test "Semicolons (command separator)" {
    ::ast::json::to_json [dict create text "cmd1; cmd2; cmd3"]
}

puts ""

# ATTACK 5: String vs Dict ambiguity
puts "ATTACK 5: Type Confusion"
puts "-----------------------------------------"

test "String that looks like a dict" {
    ::ast::json::to_json [dict create data "type proc name test"]
}

test "String that looks like JSON" {
    ::ast::json::to_json [dict create data "\{\"fake\": \"json\"\}"]
}

test "List that looks like a dict" {
    ::ast::json::to_json [dict create data {a b c d}]
}

test "Empty string vs empty list" {
    ::ast::json::to_json [dict create str "" list [list]]
}

test "String with embedded newline vs multiline" {
    ::ast::json::to_json [dict create text "line1\nline2\nline3"]
}

puts ""

# ATTACK 6: Large data
puts "ATTACK 6: Resource Exhaustion"
puts "-----------------------------------------"

test "10KB string" {
    ::ast::json::to_json [dict create text [string repeat "A" 10000]]
}

test "100KB string" {
    ::ast::json::to_json [dict create text [string repeat "B" 100000]]
}

test "1MB string (MEMORY BOMB!)" {
    ::ast::json::to_json [dict create text [string repeat "C" 1000000]]
}

test "10000 children nodes" {
    set nodes {}
    for {set i 0} {$i < 10000} {incr i} {
        lappend nodes [dict create type "node" id $i]
    }
    ::ast::json::to_json [dict create children $nodes]
}

puts ""

# ATTACK 7: Malformed AST structures
puts "ATTACK 7: Malformed AST Structures"
puts "-----------------------------------------"

test "Dict with no type key" {
    ::ast::json::to_json [dict create name "test" value 42]
}

test "Mixed key types (numeric keys)" {
    ::ast::json::to_json [dict create 123 "numeric" test "string"]
}

test "Whitespace-only keys" {
    ::ast::json::to_json [dict create " " "space" "\t" "tab"]
}

test "Key with newline" {
    ::ast::json::to_json [dict create "key\nwith\nnewline" "value"]
}

test "Duplicate keys (TCL allows this)" {
    # TCL dict with duplicate keys - last wins
    set d [list key1 value1 key1 value2]
    ::ast::json::to_json $d
}

puts ""

# ATTACK 8: Boolean and numeric edge cases
puts "ATTACK 8: Boolean and Numeric Confusion"
puts "-----------------------------------------"

test "Boolean field with string value" {
    ::ast::json::to_json [dict create had_error "maybe"]
}

test "Numeric field with string value" {
    ::ast::json::to_json [dict create line "not-a-number"]
}

test "Infinity and NaN" {
    ::ast::json::to_json [dict create inf Inf nan NaN]
}

test "Very large number" {
    ::ast::json::to_json [dict create big 999999999999999999999999]
}

test "Scientific notation" {
    ::ast::json::to_json [dict create sci 1.23e45]
}

test "Octal number" {
    ::ast::json::to_json [dict create oct 0777]
}

test "Hex number" {
    ::ast::json::to_json [dict create hex 0xDEADBEEF]
}

puts ""

# ATTACK 9: Circular references (TCL doesn't naturally support these, but...)
puts "ATTACK 9: Weird List Structures"
puts "-----------------------------------------"

test "List containing itself (if possible)" {
    # TCL doesn't support true circular refs, but we can fake it
    set list1 [list 1 2 3]
    set list2 [list $list1 $list1 $list1]
    ::ast::json::to_json [dict create data $list2]
}

test "Deeply nested same-structure" {
    set base [dict create type "base"]
    set nested $base
    for {set i 0} {$i < 50} {incr i} {
        set nested [dict create type "wrap" child $nested]
    }
    ::ast::json::to_json $nested
}

puts ""

# ATTACK 10: Edge cases in range fields
puts "ATTACK 10: Range Field Edge Cases"
puts "-----------------------------------------"

test "Negative line numbers" {
    ::ast::json::to_json [dict create range [dict create \
        start [dict create line -1 column -1]]]
}

test "Zero line number" {
    ::ast::json::to_json [dict create range [dict create \
        start [dict create line 0 column 0]]]
}

test "Huge line number" {
    ::ast::json::to_json [dict create range [dict create \
        start [dict create line 999999999 column 999999999]]]
}

test "Range with missing fields" {
    ::ast::json::to_json [dict create range [dict create start [dict create]]]
}

puts ""

puts "========================================="
puts "ADVERSARIAL TEST RESULTS"
puts "========================================="
puts "Total Tests:   $total_tests"
puts "Survived:      $passed_tests"
puts "Failed:        $failed_tests"
puts "CRASHED:       $crashed_tests"
puts ""

if {$crashed_tests > 0} {
    puts "CRITICAL: $crashed_tests tests caused crashes!"
    exit 1
} elseif {$failed_tests > 0} {
    puts "WARNING: $failed_tests tests failed"
    exit 1
} else {
    puts "IMPRESSIVE: All adversarial tests survived!"
    exit 0
}
