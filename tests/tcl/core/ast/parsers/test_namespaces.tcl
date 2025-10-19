#!/usr/bin/env tclsh
# tests/tcl/core/ast/parsers/test_namespaces.tcl
# Tests for namespace operations parser

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname [file dirname [file dirname $script_dir]]]]]

source [file join $project_root tcl core tokenizer.tcl]
source [file join $project_root tcl core ast utils.tcl]
source [file join $project_root tcl core ast parsers namespaces.tcl]

set total 0
set passed 0

proc test {name code expected_type} {
    global total passed
    incr total
    
    if {[catch {
        set result [::ast::parsers::parse_namespace $code 1 1 0]
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

puts "Namespace Parser Tests"
puts "======================\n"

# namespace eval
test "Simple namespace" "namespace eval MyNS \{ \}" "namespace"
test "Namespace with body" "namespace eval MyNS \{ variable x 10 \}" "namespace"
test "Nested namespace" "namespace eval ::Parent::Child \{ \}" "namespace"

# namespace import
test "Simple import" "namespace import ::Other::*" "namespace_import"
test "Import specific" "namespace import ::Other::proc1 ::Other::proc2" "namespace_import"

# namespace export
test "Simple export" "namespace export myproc" "namespace_export"
test "Export multiple" "namespace export proc1 proc2 proc3" "namespace_export"
test "Export with pattern" "namespace export test*" "namespace_export"

puts "\nResults: $passed/$total passed"
exit [expr {$passed == $total ? 0 : 1}]
