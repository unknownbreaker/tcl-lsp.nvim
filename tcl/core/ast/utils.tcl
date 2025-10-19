#!/usr/bin/env tclsh
# tcl/core/ast/utils.tcl
# Utility Functions for AST Building
#
# This module provides utility functions for:
# - Position range creation
# - Line number mapping
# - Offset to line/column conversion
# - Line counting

namespace eval ::ast::utils {
    namespace export make_range build_line_map offset_to_line count_lines
    
    # Line map for current file being parsed
    variable line_map [dict create]
}

# Create a position range for AST nodes
#
# LSP uses ranges to identify code locations. This function creates
# a standardized range dict with start and end positions.
#
# Args:
#   start_line, start_col - Starting position (1-indexed)
#   end_line, end_col     - Ending position (1-indexed)
#
# Returns:
#   Dict with start and end_pos keys, each containing line and column
#
proc ::ast::utils::make_range {start_line start_col end_line end_col} {
    return [dict create \
        start [dict create line $start_line column $start_col] \
        end_pos [dict create line $end_line column $end_col]]
}

# Build a line number mapping for the source code
#
# This creates a lookup table from line numbers to byte offsets.
# Essential for converting byte positions (from tokenizer) to
# line/column positions (for LSP ranges).
#
# Args:
#   code - The source code to map
#
# Returns:
#   Nothing (stores in module variable)
#
proc ::ast::utils::build_line_map {code} {
    variable line_map
    set line_map [dict create]

    set offset 0
    set line_num 1

    foreach line [split $code "\n"] {
        dict set line_map $line_num [dict create \
            offset $offset \
            length [string length $line]]

        set offset [expr {$offset + [string length $line] + 1}]
        incr line_num
    }
}

# Convert a byte offset to line and column number
#
# Uses the line map built by build_line_map to find which line
# contains the given byte offset, then calculates the column.
#
# Args:
#   offset - Byte offset into the source code (0-indexed)
#
# Returns:
#   List of {line_num column_num} (1-indexed)
#
proc ::ast::utils::offset_to_line {offset} {
    variable line_map

    dict for {line_num info} $line_map {
        set line_offset [dict get $info offset]
        set line_length [dict get $info length]
        set line_end [expr {$line_offset + $line_length}]

        if {$offset >= $line_offset && $offset <= $line_end} {
            set col [expr {$offset - $line_offset + 1}]
            return [list $line_num $col]
        }
    }

    # Default fallback if offset not found
    return [list 1 1]
}

# Count the number of lines in a text string
#
# Simple utility for determining how many lines a code block spans.
#
# Args:
#   text - The text to count lines in
#
# Returns:
#   Number of lines (integer)
#
proc ::ast::utils::count_lines {text} {
    return [expr {[llength [split $text "\n"]] - 1}]
}

# ===========================================================================
# SELF-TEST
# ===========================================================================

if {[info script] eq $argv0} {
    puts "Running utils module self-tests...\n"
    
    set pass 0
    set fail 0
    
    proc test {name script expected} {
        global pass fail
        if {[catch {uplevel $script} result]} {
            puts "✗ FAIL: $name - Error: $result"
            incr fail
            return
        }
        if {$result eq $expected} {
            puts "✓ PASS: $name"
            incr pass
        } else {
            puts "✗ FAIL: $name"
            puts "  Expected: $expected"
            puts "  Got: $result"
            incr fail
        }
    }
    
    # Test make_range
    test "make_range creates correct structure" {
        set range [::ast::utils::make_range 1 5 3 10]
        list [dict get $range start line] [dict get $range start column] \
             [dict get $range end_pos line] [dict get $range end_pos column]
    } "1 5 3 10"
    
    # Test build_line_map and offset_to_line
    test "line map and offset conversion" {
        set code "line 1\nline 2\nline 3"
        ::ast::utils::build_line_map $code
        ::ast::utils::offset_to_line 8
    } "2 2"
    
    # Test count_lines
    test "count_lines" {
        ::ast::utils::count_lines "a\nb\nc"
    } "2"
    
    puts "\n========================================="
    puts "Pass: $pass | Fail: $fail"
    if {$fail == 0} {
        puts "✓ ALL TESTS PASSED"
        exit 0
    } else {
        exit 1
    }
}
