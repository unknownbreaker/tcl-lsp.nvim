#!/usr/bin/env tclsh
# Quick test of JSON serialization

# Load the ast_builder
set script_dir [file dirname [file normalize [info script]]]
# Go up 3 levels to project root: tests/tcl/core -> tests/tcl -> tests -> root
set project_root [file dirname [file dirname [file dirname $script_dir]]]
source [file join $project_root tcl core ast_builder.tcl]

# Test 1: Simple scalar values
puts "Test 1: Scalar values"
set test1 [dict create \
    type "proc" \
    name "hello" \
    value "10"]

puts [::ast::to_json $test1]
puts "\n---\n"

# Test 2: Array fields
puts "Test 2: Array with 0 elements"
set test2 [dict create \
    type "root" \
    children [list]]

puts [::ast::to_json $test2]
puts "\n---\n"

# Test 3: Array with 1 element
puts "Test 3: Array with 1 element"
set test3 [dict create \
    type "root" \
    children [list [dict create type "proc" name "test"]]]

puts [::ast::to_json $test3]
puts "\n---\n"

# Test 4: Array with 2 elements
puts "Test 4: Array with 2 elements"
set test4 [dict create \
    type "root" \
    children [list \
        [dict create type "proc" name "test1"] \
        [dict create type "proc" name "test2"]]]

puts [::ast::to_json $test4]
