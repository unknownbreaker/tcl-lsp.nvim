#!/usr/bin/env tclsh
# tcl/core/ast/utils.tcl
# Utility Functions for AST Building
#
# This module provides helper functions for:
# - Position tracking (line/column)
# - Range creation for LSP
# - Line mapping for offset conversion

namespace eval ::ast::utils {
    variable line_map
    namespace export make_range build_line_map offset_to_line count_lines
}

# Create a position range for AST nodes
#
# This creates the range format expected by LSP (Language Server Protocol).
#
# Args:
#   start_line, start_col - Starting position (1-indexed for lines, 1-indexed for columns)
#   end_line, end_col     - Ending position
#
# Returns:
#   Dict with start and end keys, each containing line and column
#
proc ::ast::utils::make_range {start_line start_col end_line end_col} {
    return [dict create \
        start [dict create line $start_line column $start_col] \
        end [dict create line $end_line column $end_col]]
}

# Build a line number mapping for source code
#
# This creates a mapping from byte offsets to line/column positions,
# which is necessary for converting between offset-based and position-based
# addressing in LSP.
#
# Args:
#   code - The source code to map
#
# Returns:
#   Nothing (stores in ::ast::utils::line_map variable)
#
proc ::ast::utils::build_line_map {code} {
    variable line_map
    set line_map [list]

    set line_num 1
    set offset 0
    set len [string length $code]

    # Record start of first line
    lappend line_map [list $line_num $offset]

    # Scan through code finding newlines
    while {$offset < $len} {
        set char [string index $code $offset]
        if {$char eq "\n"} {
            incr line_num
            lappend line_map [list $line_num [expr {$offset + 1}]]
        }
        incr offset
    }
}

# Convert a byte offset to line/column position
#
# Args:
#   offset - Byte offset in the source code
#
# Returns:
#   Dict with line and column keys (both 1-indexed)
#
proc ::ast::utils::offset_to_line {offset} {
    variable line_map

    # Find the line containing this offset
    set line_num 1
    set line_start 0

    foreach entry $line_map {
        lassign $entry num start
        if {$start > $offset} {
            break
        }
        set line_num $num
        set line_start $start
    }

    # Calculate column (1-indexed)
    set column [expr {$offset - $line_start + 1}]

    return [dict create line $line_num column $column]
}

# Count number of lines in code
#
# Args:
#   code - Source code text
#
# Returns:
#   Number of lines
#
proc ::ast::utils::count_lines {code} {
    set count 1
    set len [string length $code]

    for {set i 0} {$i < $len} {incr i} {
        if {[string index $code $i] eq "\n"} {
            incr count
        }
    }

    return $count
}

# ===========================================================================
# MAIN - For testing
# ===========================================================================

if {[info script] eq $argv0} {
    puts "Testing utils module..."
    puts ""

    # Test 1: make_range
    puts "Test 1: make_range"
    set range [make_range 1 1 10 20]
    puts "  Range: $range"
    puts "  Start line: [dict get $range start line]"
    puts "  End column: [dict get $range end column]"
    puts ""

    # Test 2: build_line_map and offset_to_line
    puts "Test 2: Line mapping"
    set code "Line 1\nLine 2\nLine 3"
    build_line_map $code
    puts "  Code: [list $code]"
    puts "  Offset 0 -> [offset_to_line 0]"
    puts "  Offset 7 -> [offset_to_line 7]"
    puts "  Offset 14 -> [offset_to_line 14]"
    puts ""

    # Test 3: count_lines
    puts "Test 3: count_lines"
    puts "  Lines in \"hello\" -> [count_lines {hello}]"
    puts "  Lines in \"a\\nb\\nc\" -> [count_lines \"a\nb\nc\"]"
    puts ""

    puts "✓ Utils tests complete"
}
