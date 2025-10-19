#!/usr/bin/env tclsh
# tcl/core/ast/commands.tcl
# Command Extraction Module
#
# This module splits TCL source code into individual command blocks.
# It handles multi-line commands, brace balancing, and comments.

namespace eval ::ast::commands {
    namespace export extract
    variable debug 0
}

# Extract individual TCL commands from source code
#
# This function intelligently splits source into separate commands by:
# - Tracking brace depth to handle multi-line commands
# - Using [info complete] to verify command completeness
# - Skipping comment lines
# - Handling multi-line comments (ending with \)
#
# Args:
#   code       - The source code
#   start_line - Line number to start from (for nested parsing)
#
# Returns:
#   List of command dicts with text, start_line, end_line keys
#
proc ::ast::commands::extract {code start_line} {
    variable debug

    set commands [list]
    set lines [split $code "\n"]
    set line_num $start_line
    set current_cmd ""
    set cmd_start_line $start_line
    set brace_depth 0
    set in_comment 0

    foreach line $lines {
        # Handle multi-line comments (lines ending with \)
        if {$in_comment} {
            if {[string index [string trimright $line] end] ne "\\"} {
                set in_comment 0
            }
            incr line_num
            continue
        }

        # Skip comment lines
        if {[regexp {^\s*#} $line]} {
            # Check if this comment continues on next line
            if {[string index [string trimright $line] end] eq "\\"} {
                set in_comment 1
            }
            incr line_num
            continue
        }

        # Skip empty lines
        set trimmed [string trim $line]
        if {$trimmed eq ""} {
            incr line_num
            continue
        }

        # Start new command if we're not in the middle of one
        if {$current_cmd eq ""} {
            set cmd_start_line $line_num
        }

        append current_cmd $line "\n"

        # Track brace depth to know when command is complete
        foreach char [split $line ""] {
            if {$char eq "\{"} {
                incr brace_depth
            } elseif {$char eq "\}"} {
                incr brace_depth -1
            }
        }

        # Command is complete when:
        # 1. TCL says it's complete ([info complete])
        # 2. We're at brace depth 0 (not inside any blocks)
        if {[info complete $current_cmd] && $brace_depth == 0} {
            lappend commands [dict create \
                text $current_cmd \
                start_line $cmd_start_line \
                end_line $line_num]
            set current_cmd ""
        }

        incr line_num
    }

    # Handle incomplete command at end of file
    if {$current_cmd ne ""} {
        lappend commands [dict create \
            text $current_cmd \
            start_line $cmd_start_line \
            end_line [expr {$line_num - 1}]]
    }

    if {$debug} {
        puts "Extracted [llength $commands] commands"
    }

    return $commands
}

# ===========================================================================
# SELF-TEST
# ===========================================================================

if {[info script] eq $argv0} {
    puts "Running commands module self-tests...\n"
    
    set pass 0
    set fail 0
    
    proc test {name script expected} {
        global pass fail
        if {[catch {uplevel $script} result]} {
            puts "✗ FAIL: $name - Error: $result"
            incr fail
            return
        }
        if {$result == $expected} {
            puts "✓ PASS: $name"
            incr pass
        } else {
            puts "✗ FAIL: $name"
            puts "  Expected: $expected"
            puts "  Got: $result"
            incr fail
        }
    }
    
    # Test 1: Single line command
    test "Single line command" {
        set code "set x 1"
        llength [::ast::commands::extract $code 1]
    } "1"
    
    # Test 2: Multi-line command
    test "Multi-line proc" {
        set code "proc foo \{\} \{\n    puts hello\n\}"
        llength [::ast::commands::extract $code 1]
    } "1"
    
    # Test 3: Multiple commands
    test "Multiple commands" {
        set code "set x 1\nset y 2\nset z 3"
        llength [::ast::commands::extract $code 1]
    } "3"
    
    # Test 4: Commands with comments
    test "Commands with comments" {
        set code "# Comment\nset x 1\n# Another comment\nset y 2"
        llength [::ast::commands::extract $code 1]
    } "2"
    
    # Test 5: Empty lines
    test "Commands with empty lines" {
        set code "set x 1\n\nset y 2"
        llength [::ast::commands::extract $code 1]
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
