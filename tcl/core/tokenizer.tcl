#!/usr/bin/env tclsh
# tcl/core/tokenizer.tcl
# Literal Tokenizer - Splits TCL code into tokens WITHOUT evaluation or interpretation
#
# CRITICAL FIX: This tokenizer preserves EXACT literal text:
#   - "hello" stays as "hello" (with quotes)
#   - {42} stays as {42} (with braces)
#   - 42 stays as "42" (string, not number)
#
# This is essential for AST building - we need the SOURCE TEXT, not interpreted values!

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
                if {$char eq "\\"} {
                    # Skip escaped character
                    incr pos 2
                    continue
                }
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
        } elseif {$char eq "\["} {
            # Command substitution - find matching bracket
            set bracket_depth 1
            incr pos
            while {$pos < $len && $bracket_depth > 0} {
                set char [string index $text $pos]
                if {$char eq "\\"} {
                    # Skip escaped character
                    incr pos 2
                    continue
                }
                if {$char eq "\["} {
                    incr bracket_depth
                } elseif {$char eq "\]"} {
                    incr bracket_depth -1
                }
                incr pos
            }
        } else {
            # Bare word - read until whitespace or special char
            while {$pos < $len} {
                set char [string index $text $pos]
                if {[string is space $char]} {
                    break
                }
                # Stop at special characters that start new tokens
                if {$char eq "\{" || $char eq "\"" || $char eq "\[" || $char eq ";"} {
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
# ⭐ CRITICAL FIX: This function returns the LITERAL text of the token
# INCLUDING quotes, braces, and brackets!
#
# Examples:
#   get_token {set x "hello"} 2  → "hello" (with quotes!)
#   get_token {set x {42}} 2     → {42} (with braces!)
#   get_token {set x 42} 2       → 42 (bare word, as-is)
#
# Args:
#   text  - TCL command text to tokenize
#   index - Token index to retrieve (0-based)
#
# Returns:
#   The token at the specified index INCLUDING its delimiters, or empty string if out of range
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

        # Mark start of token (INCLUDING delimiters!)
        set token_start $pos

        # Determine how to parse this token
        if {$char eq "\{"} {
            # Braced token - ⭐ INCLUDE THE BRACES
            set brace_depth 1
            incr pos
            while {$pos < $len && $brace_depth > 0} {
                set char [string index $text $pos]
                if {$char eq "\\"} {
                    # Skip escaped character
                    incr pos 2
                    continue
                }
                if {$char eq "\{"} {
                    incr brace_depth
                } elseif {$char eq "\}"} {
                    incr brace_depth -1
                }
                incr pos
            }
            # pos is now AFTER the closing brace
            if {$current == $index} {
                # Return token WITH braces: {content}
                return [string range $text $token_start [expr {$pos - 1}]]
            }
        } elseif {$char eq "\""} {
            # Quoted token - ⭐ INCLUDE THE QUOTES
            incr pos
            while {$pos < $len} {
                set char [string index $text $pos]
                if {$char eq "\\"} {
                    incr pos 2
                } elseif {$char eq "\""} {
                    incr pos
                    break
                } else {
                    incr pos
                }
            }
            # pos is now AFTER the closing quote
            if {$current == $index} {
                # Return token WITH quotes: "content"
                return [string range $text $token_start [expr {$pos - 1}]]
            }
        } elseif {$char eq "\["} {
            # Command substitution - ⭐ INCLUDE THE BRACKETS
            set bracket_depth 1
            incr pos
            while {$pos < $len && $bracket_depth > 0} {
                set char [string index $text $pos]
                if {$char eq "\\"} {
                    # Skip escaped character
                    incr pos 2
                    continue
                }
                if {$char eq "\["} {
                    incr bracket_depth
                } elseif {$char eq "\]"} {
                    incr bracket_depth -1
                }
                incr pos
            }
            # pos is now AFTER the closing bracket
            if {$current == $index} {
                # Return token WITH brackets: [command]
                return [string range $text $token_start [expr {$pos - 1}]]
            }
        } else {
            # Bare word - no delimiters to preserve
            while {$pos < $len} {
                set char [string index $text $pos]
                if {[string is space $char]} {
                    break
                }
                # Stop at special characters
                if {$char eq "\{" || $char eq "\"" || $char eq "\[" || $char eq ";"} {
                    break
                }
                if {$char eq "\\"} {
                    incr pos 2
                } else {
                    incr pos
                }
            }
            if {$current == $index} {
                # Return bare word as-is
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
# SELF-TEST - Verify tokenizer preserves literal text
# ===========================================================================

if {[info exists argv0] && $argv0 eq [info script]} {
    puts "Testing Fixed Tokenizer - Literal Text Preservation"
    puts "====================================================\n"

    set total 0
    set passed 0

    proc test {name cmd_text token_index expected_value} {
        global total passed
        incr total

        set actual_value [::tokenizer::get_token $cmd_text $token_index]

        if {$actual_value eq $expected_value} {
            puts "✓ PASS: $name"
            incr passed
        } else {
            puts "✗ FAIL: $name"
            puts "  Command: $cmd_text"
            puts "  Token $token_index:"
            puts "    Expected: \[$expected_value\]"
            puts "    Got:      \[$actual_value\]"
        }
    }

    # Test 1: Quoted strings MUST preserve quotes
    puts "Test Group 1: Quoted Strings (preserve quotes)"
    test "Simple quoted string" {set x "hello"} 2 {"hello"}
    test "Quoted with spaces" {set msg "Hello World"} 2 {"Hello World"}
    test "Empty quoted string" {set empty ""} 2 {""}

    puts ""

    # Test 2: Braced strings MUST preserve braces
    puts "Test Group 2: Braced Strings (preserve braces)"
    test "Simple braced value" {set x {42}} 2 {{42}}
    test "Braced with spaces" {set body {puts hello}} 2 {{puts hello}}
    test "Nested braces" {set code {{a b}}} 2 {{{a b}}}

    puts ""

    # Test 3: Numbers MUST remain as strings
    puts "Test Group 3: Numbers (keep as bare words)"
    test "Integer" {set x 42} 2 {42}
    test "Float" {set ver 8.6} 2 {8.6}
    test "Negative" {set n -10} 2 {-10}

    puts ""

    # Test 4: Command substitution MUST preserve brackets
    puts "Test Group 4: Command Substitution (preserve brackets)"
    test "Simple command sub" {set result [expr 1]} 2 {[expr 1]}
    test "Command sub with braces" {set x [expr {1 + 2}]} 2 {[expr {1 + 2}]}

    puts ""

    # Test 5: Bare words stay as-is
    puts "Test Group 5: Bare Words (as-is)"
    test "Variable name" {set myvar 1} 1 {myvar}
    test "Command name" {puts hello} 0 {puts}

    puts ""
    puts "Results: $passed/$total tests passed"
    puts ""

    if {$passed == $total} {
        puts "✓ ALL TESTS PASSED - Tokenizer correctly preserves literal text!"
        puts ""
        puts "Key Verifications:"
        puts "  ✓ Quoted strings keep quotes: \"hello\""
        puts "  ✓ Braced values keep braces: {42}"
        puts "  ✓ Numbers stay as bare words: 42, 8.6"
        puts "  ✓ Command subs keep brackets: \[expr {...}\]"
        exit 0
    } else {
        puts "✗ SOME TESTS FAILED"
        exit 1
    }
}
