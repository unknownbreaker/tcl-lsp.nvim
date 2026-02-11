#!/usr/bin/env tclsh
# tests/tcl/core/ast/parsers/test_namespaces.tcl
# Tests for namespace operations parser

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname [file dirname [file dirname $script_dir]]]]]

# Load full builder since parse_namespace now recursively parses bodies
source [file join $project_root tcl core ast builder.tcl]

set total 0
set passed 0

proc test {name code expected_type} {
    global total passed
    incr total

    if {[catch {
        set result [::ast::parsers::namespaces::parse_namespace $code 1 1 0]
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

proc test_body {name code expected_child_count} {
    global total passed
    incr total

    if {[catch {
        set result [::ast::parsers::namespaces::parse_namespace $code 1 5 0]
        set body [dict get $result body]
        set children [dict get $body children]
        set count [llength $children]

        if {$count == $expected_child_count} {
            puts "✓ PASS: $name"
            incr passed
        } else {
            puts "✗ FAIL: $name - Expected $expected_child_count children, got $count"
        }
    } err]} {
        puts "✗ FAIL: $name - Error: $err"
    }
}

proc test_export_field {name code} {
    global total passed
    incr total

    if {[catch {
        set result [::ast::parsers::namespaces::parse_namespace $code 1 1 0]

        if {[dict exists $result exports]} {
            puts "✓ PASS: $name"
            incr passed
        } else {
            puts "✗ FAIL: $name - Missing 'exports' field"
        }
    } err]} {
        puts "✗ FAIL: $name - Error: $err"
    }
}

puts "Namespace Parser Tests"
puts "======================\n"

# namespace eval — type should be namespace_eval
test "Simple namespace" "namespace eval MyNS \{ \}" "namespace_eval"
test "Namespace with body" "namespace eval MyNS \{ variable x 10 \}" "namespace_eval"
test "Nested namespace" "namespace eval ::Parent::Child \{ \}" "namespace_eval"

# namespace eval — body parsing
test_body "Empty body has no children" "namespace eval MyNS \{ \}" 0
test_body "Body with proc" {namespace eval MyNS {
    proc hello {} {
        puts "hi"
    }
}} 1
test_body "Body with multiple procs" {namespace eval MyNS {
    proc foo {} { return 1 }
    proc bar {} { return 2 }
}} 2

# namespace import
test "Simple import" "namespace import ::Other::*" "namespace_import"
test "Import specific" "namespace import ::Other::proc1 ::Other::proc2" "namespace_import"

# namespace export — field name should be 'exports'
test "Simple export" "namespace export myproc" "namespace_export"
test "Export multiple" "namespace export proc1 proc2 proc3" "namespace_export"
test "Export with pattern" "namespace export test*" "namespace_export"
test_export_field "Export uses 'exports' field" "namespace export myproc"

puts "\nResults: $passed/$total passed"
exit [expr {$passed == $total ? 0 : 1}]
