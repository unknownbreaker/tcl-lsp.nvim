#!/usr/bin/env tclsh
# tcl/core/tokenizer.tcl
# Literal Tokenizer - Splits TCL code into tokens without evaluation
#
# This tokenizer provides a way to count and extract tokens from TCL code
# without actually executing it, which is critical for static analysis.

namespace eval ::tokenizer {
    namespace export count_tokens get_token
}

# Count the number of tokens (words) in a TCL command
#
# This is similar to [llength] but doesn't evaluate substitutions.
# It handles quotes, braces, brackets, and backslashes correctly.
#
# Args:
#   text - TCL command text to tokenize
#
# Returns:
#   Number of tokens in the command
#
proc ::tokenizer::count_tokens {text} {
    set count 0
    set pos 0
    set len [string length $text]

    # Skip leading whitespace
    while {$pos < $len && [string is space [string index $text $pos]]} {
        incr pos
    }

    while {$pos < $len} {
        set char [string index $text $pos]

        # Skip whitespace between tokens
        if {[string is space $char]} {
            incr pos
            continue
        }

        # Found start of a token
        incr count

        # Determine how to parse this token
        if {$char eq "\{"} {
            # Braced token - find matching close brace
            set brace_depth 1
            incr pos
            while {$pos < $len && $brace_depth > 0} {
                set char [string index $text $pos]
                if {$char eq "\{"} {
                    incr brace_depth
                } elseif {$char eq "\}"} {
                    incr brace_depth -1
                }
                incr pos
            }
        } elseif {$char eq "\""} {
            # Quoted token - find matching quote
            incr pos
            while {$pos < $len} {
                set char [string index $text $pos]
                if {$char eq "\\"} {
                    # Skip escaped character
                    incr pos 2
                } elseif {$char eq "\""} {
                    incr pos
                    break
                } else {
                    incr pos
                }
            }
        } else {
            # Bare word - read until whitespace or special char
            while {$pos < $len} {
                set char [string index $text $pos]
                if {[string is space $char]} {
                    break
                }
                if {$char eq "\\"} {
                    # Skip escaped character
                    incr pos 2
                } else {
                    incr pos
                }
            }
        }

        # Skip any trailing whitespace after this token
        while {$pos < $len && [string is space [string index $text $pos]]} {
            incr pos
        }
    }

    return $count
}

# Get the Nth token from a TCL command (0-indexed)
#
# Similar to [lindex] but doesn't evaluate substitutions.
#
# Args:
#   text  - TCL command text to tokenize
#   index - Token index to retrieve (0-based)
#
# Returns:
#   The token at the specified index, or empty string if out of range
#
proc ::tokenizer::get_token {text index} {
    set current 0
    set pos 0
    set len [string length $text]

    # Skip leading whitespace
    while {$pos < $len && [string is space [string index $text $pos]]} {
        incr pos
    }

    while {$pos < $len} {
        set char [string index $text $pos]

        # Skip whitespace between tokens
        if {[string is space $char]} {
            incr pos
            continue
        }

        # Mark start of token
        set token_start $pos

        # Determine how to parse this token
        if {$char eq "\{"} {
            # Braced token
            set brace_depth 1
            incr pos
            set content_start $pos
            while {$pos < $len && $brace_depth > 0} {
                set char [string index $text $pos]
                if {$char eq "\{"} {
                    incr brace_depth
                } elseif {$char eq "\}"} {
                    incr brace_depth -1
                    if {$brace_depth == 0} {
                        # Found matching brace - extract content
                        if {$current == $index} {
                            return [string range $text $content_start [expr {$pos - 1}]]
                        }
                    }
                }
                incr pos
            }
        } elseif {$char eq "\""} {
            # Quoted token
            incr pos
            set content_start $pos
            while {$pos < $len} {
                set char [string index $text $pos]
                if {$char eq "\\"} {
                    incr pos 2
                } elseif {$char eq "\""} {
                    # Found closing quote - extract content
                    if {$current == $index} {
                        return [string range $text $content_start [expr {$pos - 1}]]
                    }
                    incr pos
                    break
                } else {
                    incr pos
                }
            }
        } else {
            # Bare word
            while {$pos < $len} {
                set char [string index $text $pos]
                if {[string is space $char]} {
                    break
                }
                if {$char eq "\\"} {
                    incr pos 2
                } else {
                    incr pos
                }
            }
            if {$current == $index} {
                return [string range $text $token_start [expr {$pos - 1}]]
            }
        }

        incr current

        # Skip trailing whitespace
        while {$pos < $len && [string is space [string index $text $pos]]} {
            incr pos
        }
    }

    return ""
}

# ===========================================================================
# MAIN - For testing
# ===========================================================================

if {[info script] eq $argv0} {
    puts "Testing tokenizer..."
    puts ""

    # Test 1: Simple command
    set test1 "set x 1"
    puts "Test 1: \"$test1\""
    puts "  Token count: [count_tokens $test1]"
    puts "  Token 0: [get_token $test1 0]"
    puts "  Token 1: [get_token $test1 1]"
    puts "  Token 2: [get_token $test1 2]"
    puts ""

    # Test 2: Quoted string
    set test2 {set name "John Doe"}
    puts "Test 2: $test2"
    puts "  Token count: [count_tokens $test2]"
    puts "  Token 0: [get_token $test2 0]"
    puts "  Token 1: [get_token $test2 1]"
    puts "  Token 2: [get_token $test2 2]"
    puts ""

    # Test 3: Braced string
    set test3 {proc hello {} { puts "Hello!" }}
    puts "Test 3: $test3"
    puts "  Token count: [count_tokens $test3]"
    puts "  Token 0: [get_token $test3 0]"
    puts "  Token 1: [get_token $test3 1]"
    puts "  Token 2: [get_token $test3 2]"
    puts "  Token 3: [get_token $test3 3]"
    puts ""

    # Test 4: Command substitution
    set test4 {set result [expr {1 + 2}]}
    puts "Test 4: $test4"
    puts "  Token count: [count_tokens $test4]"
    puts "  Token 0: [get_token $test4 0]"
    puts "  Token 1: [get_token $test4 1]"
    puts "  Token 2: [get_token $test4 2]"
    puts ""

    puts "✓ Tokenizer tests complete"
}
