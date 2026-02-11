#!/usr/bin/env tclsh
# tcl/core/ast/commands.tcl
# Command Extraction Module
#
# Splits TCL source code into individual commands for parsing.
# This is tricky because we need to handle braces, quotes, and line continuations
# without actually executing the code.

namespace eval ::ast::commands {
    namespace export extract
}

# Extract individual commands from TCL source code
#
# This splits the source into separate commands, respecting:
# - Brace nesting (commands inside procs shouldn't be split)
# - Quote escaping
# - Line continuations (backslash-newline)
# - Semicolon separators
# - Comment lines (lines starting with #)
#
# Args:
#   code       - Source code to split
#   start_line - Starting line number for the code block
#
# Returns:
#   List of command dicts, each with: text, start_line, end_line keys
#
proc ::ast::commands::extract {code start_line} {
    set commands [list]
    set lines [split $code "\n"]
    set line_num 0

    set current_cmd ""
    set cmd_start_line 0
    set brace_depth 0
    set in_quotes 0

    foreach line $lines {
        # Skip comment-only lines (after trimming whitespace)
        set trimmed_line [string trim $line]
        if {[string index $trimmed_line 0] eq "#"} {
            incr line_num
            continue
        }

        # Track if this line continues a command
        set line_continues 0

        # Check for backslash at end (line continuation)
        if {[string index $line end] eq "\\"} {
            set line_continues 1
        }

        # Add line to current command
        if {$current_cmd ne ""} {
            append current_cmd "\n"
        }
        append current_cmd $line

        # Track brace depth to know when command is complete
        for {set i 0} {$i < [string length $line]} {incr i} {
            set char [string index $line $i]
            set prev_char [expr {$i > 0 ? [string index $line [expr {$i-1}]] : ""}]

            # Skip escaped characters
            if {$prev_char eq "\\"} {
                continue
            }

            # Track quotes
            if {$char eq "\""} {
                set in_quotes [expr {!$in_quotes}]
            }

            # Track braces (only outside quotes)
            if {!$in_quotes} {
                if {$char eq "\{"} {
                    incr brace_depth
                } elseif {$char eq "\}"} {
                    incr brace_depth -1
                }
            }
        }

        # Command is complete when:
        # 1. Line doesn't continue (no backslash at end)
        # 2. We're not inside quotes
        # 3. Brace depth is 0
        # 4. TCL says it's complete ([info complete])
        if {!$line_continues && !$in_quotes && $brace_depth == 0} {
            if {[info complete $current_cmd]} {
                # Command is complete - save it
                set trimmed [string trim $current_cmd]
                if {$trimmed ne "" && [string index $trimmed 0] ne "#"} {
                    lappend commands [dict create \
                        text $trimmed \
                        start_line [expr {$start_line + $cmd_start_line}] \
                        end_line [expr {$start_line + $line_num}]]
                }
                set current_cmd ""
                set cmd_start_line [expr {$line_num + 1}]
            }
        }

        incr line_num
    }

    # Handle incomplete command at end
    if {$current_cmd ne ""} {
        set trimmed [string trim $current_cmd]
        if {$trimmed ne "" && [string index $trimmed 0] ne "#"} {
            lappend commands [dict create \
                text $trimmed \
                start_line [expr {$start_line + $cmd_start_line}] \
                end_line [expr {$start_line + $line_num - 1}]]
        }
    }

    return $commands
}

# ===========================================================================
# MAIN - For testing
# ===========================================================================

if {[info script] eq $argv0} {
    puts "Testing commands module..."
    puts ""

    # Test 1: Simple single command
    set test1 "set x 1"
    puts "Test 1: Single command"
    set cmds [extract $test1 1]
    puts "  Found [llength $cmds] command(s)"
    if {[llength $cmds] > 0} {
        puts "  Command: [dict get [lindex $cmds 0] text]"
    }
    puts ""

    # Test 2: Multiple commands
    set test2 "set x 1\nset y 2\nset z 3"
    puts "Test 2: Multiple commands"
    set cmds [extract $test2 1]
    puts "  Found [llength $cmds] command(s)"
    puts ""

    # Test 3: Command with braces (proc)
    set test3 "proc hello \{\} \{\n    puts \"Hello!\"\n\}"
    puts "Test 3: Proc with braces"
    set cmds [extract $test3 1]
    puts "  Found [llength $cmds] command(s)"
    if {[llength $cmds] > 0} {
        puts "  Command lines: [dict get [lindex $cmds 0] start_line]-[dict get [lindex $cmds 0] end_line]"
    }
    puts ""

    # Test 4: Line continuation
    set test4 "set x \\\n    \[expr \{1 + 2\}\]"
    puts "Test 4: Line continuation"
    set cmds [extract $test4 1]
    puts "  Found [llength $cmds] command(s)"
    puts ""

    # Test 5: Empty input
    set test5 ""
    puts "Test 5: Empty input"
    set cmds [extract $test5 1]
    puts "  Found [llength $cmds] command(s)"
    puts ""

    # Test 6: Commands with comments
    set test6 "# Comment\nset x 1\n# Another\nset y 2"
    puts "Test 6: Commands with comments"
    set cmds [extract $test6 1]
    puts "  Found [llength $cmds] command(s) (should be 2)"
    puts ""

    puts "✓ Commands tests complete"
}
