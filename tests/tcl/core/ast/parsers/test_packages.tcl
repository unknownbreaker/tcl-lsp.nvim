#!/usr/bin/env tclsh
# tests/tcl/core/ast/parsers/test_packages.tcl
# Tests for package operations parser

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname [file dirname [file dirname [file dirname [file dirname $script_dir]]]]]

source [file join $project_root tcl core tokenizer.tcl]
source [file join $project_root tcl core ast utils.tcl]
source [file join $project_root tcl core ast parsers packages.tcl]

set total 0
set passed 0

proc test {name code expected_type} {
    global total passed
    incr total

    if {[catch {
        # UPDATED: Use modular namespace structure
        set result [::ast::parsers::packages::parse_package $code 1 1 0]
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

puts "Package Parser Tests"
puts "====================\n"

# package require
test "Simple require" "package require Tcl" "package_require"
test "Require with version" "package require Tcl 8.6" "package_require"
test "Require with exact version" "package require -exact Tcl 8.6.10" "package_require"

# package provide
test "Simple provide" "package provide MyPackage 1.0" "package_provide"
test "Provide with version" "package provide MyLib 2.5.3" "package_provide"

puts "\nResults: $passed/$total passed"
exit [expr {$passed == $total ? 0 : 1}]
