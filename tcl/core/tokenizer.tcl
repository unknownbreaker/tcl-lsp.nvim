#!/usr/bin/env tclsh
# tcl/core/tokenizer.tcl
# Literal Token Extractor for TCL Parser
#
# This tokenizer extracts tokens AS THEY APPEAR in source code without
# TCL evaluation. This is critical for Language Server Protocol (LSP)
# implementations where we need to preserve the exact text representation
# that the user wrote.
#
# Example:
#   Input:  set x "hello"
#   Output: ["set", "x", "\"hello\""]  <-- Quotes preserved!
#
# Why this matters:
#   - Go-to-definition needs exact text to find symbols
#   - Refactoring needs exact text to replace
#   - Hover info needs to show what's actually written
#   - Code completion needs context as-is, not evaluated
#
# Key principle: We NEVER execute or evaluate TCL code during tokenization.

namespace eval ::tokenizer {
    variable debug 0
}

# ===========================================================================
# PUBLIC API
# ===========================================================================

# Tokenize a TCL command string into a list of literal tokens
#
# Args:
#   text - The TCL command string to tokenize
#
# Returns:
#   List of tokens exactly as they appear in source
#
# Example:
#   tokenize {set x "hello"}  → [set x "hello"]
#   tokenize {set y [expr 1]} → [set y [expr 1]]
#
proc ::tokenizer::tokenize {text} {
    set tokens [list]
    set len [string length $text]
    set i 0

    while {$i < $len} {
        # Skip whitespace between tokens
        while {$i < $len && [string is space [string index $text $i]]} {
            incr i
        }

        if {$i >= $len} {
            break
        }

        # Extract one token starting at position i
        set token_info [extract_token $text $i]
        set token_text [dict get $token_info text]
        set token_end [dict get $token_info end_pos]

        if {$token_text ne ""} {
            lappend tokens $token_text
        }

        set i $token_end
    }

    return $tokens
}

# Get a specific token by index from a command string
#
# Args:
#   text  - The TCL command string
#   index - Zero-based index of token to retrieve
#
# Returns:
#   The token at the specified index, or empty string if index out of range
#
# Example:
#   get_token {set x "hello"} 0 → "set"
#   get_token {set x "hello"} 2 → "\"hello\""
#
proc ::tokenizer::get_token {text index} {
    set tokens [tokenize $text]

    if {$index >= 0 && $index < [llength $tokens]} {
        return [lindex $tokens $index]
    }

    return ""
}

# Count the number of tokens in a command string
#
# Args:
#   text - The TCL command string
#
# Returns:
#   Number of tokens
#
# Example:
#   count_tokens {set x "hello"} → 3
#
proc ::tokenizer::count_tokens {text} {
    return [llength [tokenize $text]]
}

# ===========================================================================
# INTERNAL TOKEN EXTRACTION
# ===========================================================================

# Extract a single token starting at the given position
#
# This is the main dispatch function that determines what type of token
# we're looking at and calls the appropriate extraction function.
#
# Args:
#   text      - The full command string
#   start_pos - Position to start extraction
#
# Returns:
#   Dict with keys: text (the token), end_pos (position after token)
#
proc ::tokenizer::extract_token {text start_pos} {
    set len [string length $text]
    set i $start_pos
    set char [string index $text $i]

    # Determine token type based on first character

    # Quoted string: "..."
    if {$char eq "\""} {
        return [extract_quoted_string $text $i]
    }

    # Braced string: {...}
    if {$char eq "\{"} {
        return [extract_braced_string $text $i]
    }

    # Command substitution: [...]
    if {$char eq "\["} {
        return [extract_command_substitution $text $i]
    }

    # Variable substitution: $var or ${var}
    if {$char eq "\$"} {
        return [extract_variable_substitution $text $i]
    }

    # Bare word (unquoted, non-special text)
    return [extract_bare_word $text $i]
}

# ===========================================================================
# TOKEN TYPE EXTRACTORS
# ===========================================================================

# Extract a quoted string INCLUDING the surrounding quotes
#
# Handles:
#   - Escaped characters: \"
#   - Newlines within quotes
#   - Unclosed quotes (returns what we have)
#
# Args:
#   text      - The full command string
#   start_pos - Position of opening quote
#
# Returns:
#   Dict with text (including quotes) and end_pos
#
# Example:
#   Input: "hello world" at position 0
#   Output: {text {"hello world"} end_pos 13}
#
proc ::tokenizer::extract_quoted_string {text start_pos} {
    set len [string length $text]
    set i [expr {$start_pos + 1}]  ;# Skip opening quote
    set result "\""
    set escaped 0

    while {$i < $len} {
        set char [string index $text $i]

        if {$escaped} {
            # Previous char was backslash, append this char literally
            append result $char
            set escaped 0
        } elseif {$char eq "\\"} {
            # This is an escape character
            append result $char
            set escaped 1
        } elseif {$char eq "\""} {
            # Found closing quote
            append result $char
            incr i
            return [dict create text $result end_pos $i]
        } else {
            # Normal character
            append result $char
        }

        incr i
    }

    # Reached end of string without closing quote
    # Return what we have (unclosed string)
    return [dict create text $result end_pos $i]
}

# Extract a braced string INCLUDING the surrounding braces
#
# Handles:
#   - Nested braces: {outer {inner} text}
#   - Multiple nesting levels
#   - Unbalanced braces (returns what we have)
#
# Args:
#   text      - The full command string
#   start_pos - Position of opening brace
#
# Returns:
#   Dict with text (including braces) and end_pos
#
# Example:
#   Input: {hello {nested} world} at position 0
#   Output: {text {{hello {nested} world}} end_pos 22}
#
proc ::tokenizer::extract_braced_string {text start_pos} {
    set len [string length $text]
    set i [expr {$start_pos + 1}]  ;# Skip opening brace
    set result "\{"
    set depth 1

    while {$i < $len && $depth > 0} {
        set char [string index $text $i]
        append result $char

        if {$char eq "\{"} {
            incr depth
        } elseif {$char eq "\}"} {
            incr depth -1
        }

        incr i
    }

    return [dict create text $result end_pos $i]
}

# Extract a command substitution INCLUDING the surrounding brackets
#
# This is the most complex extraction because we need to handle:
#   - Nested command substitutions: [expr [expr 1]]
#   - Braces inside brackets: [expr {1 + 2}]
#   - Quotes inside brackets: [puts "hello"]
#   - Multiple nesting levels
#
# The key is tracking whether we're inside quotes or braces, because
# brackets inside quotes/braces don't count as command substitution.
#
# Args:
#   text      - The full command string
#   start_pos - Position of opening bracket
#
# Returns:
#   Dict with text (including brackets) and end_pos
#
# Example:
#   Input: [expr {1 + 2}] at position 0
#   Output: {text {[expr {1 + 2}]} end_pos 14}
#
proc ::tokenizer::extract_command_substitution {text start_pos} {
    set len [string length $text]
    set i [expr {$start_pos + 1}]  ;# Skip opening bracket
    set result "\["
    set bracket_depth 1
    set brace_depth 0
    set in_quotes 0

    while {$i < $len && $bracket_depth > 0} {
        set char [string index $text $i]
        append result $char

        # Track whether we're inside braces or quotes
        # because brackets inside these don't count

        if {!$in_quotes} {
            if {$char eq "\{"} {
                incr brace_depth
            } elseif {$char eq "\}"} {
                incr brace_depth -1
            }
        }

        if {$char eq "\""} {
            set in_quotes [expr {!$in_quotes}]
        }

        # Only count brackets when we're not inside quotes or braces
        if {!$in_quotes && $brace_depth == 0} {
            if {$char eq "\["} {
                incr bracket_depth
            } elseif {$char eq "\]"} {
                incr bracket_depth -1
            }
        }

        incr i
    }

    return [dict create text $result end_pos $i]
}

# Extract a variable substitution
#
# Handles two forms:
#   - Simple: $varname
#   - Braced: ${varname}
#   - Namespace qualified: $::namespace::var
#
# Args:
#   text      - The full command string
#   start_pos - Position of dollar sign
#
# Returns:
#   Dict with text (including $) and end_pos
#
# Example:
#   Input: $myvar at position 0
#   Output: {text {$myvar} end_pos 6}
#
#   Input: ${my::var} at position 0
#   Output: {text {${my::var}} end_pos 10}
#
proc ::tokenizer::extract_variable_substitution {text start_pos} {
    set len [string length $text]
    set i [expr {$start_pos + 1}]  ;# Skip dollar sign
    set result "\$"

    # Check for braced form: ${...}
    if {$i < $len && [string index $text $i] eq "\{"} {
        append result "\{"
        incr i

        # Extract until closing brace
        while {$i < $len} {
            set char [string index $text $i]
            append result $char
            incr i

            if {$char eq "\}"} {
                break
            }
        }

        return [dict create text $result end_pos $i]
    }

    # Simple form: $varname
    # Variable names can contain: letters, digits, underscores, colons
    while {$i < $len} {
        set char [string index $text $i]

        # Check if this character is valid in a variable name
        if {[string is alnum $char] || $char eq "_" || $char eq ":"} {
            append result $char
            incr i
        } else {
            break
        }
    }

    return [dict create text $result end_pos $i]
}

# Extract a bare word (unquoted, non-special text)
#
# A bare word ends at:
#   - Whitespace
#   - Special characters: { } [ ] " $ ;
#
# Args:
#   text      - The full command string
#   start_pos - Position to start extraction
#
# Returns:
#   Dict with text and end_pos
#
# Example:
#   Input: hello at position 0
#   Output: {text {hello} end_pos 5}
#
proc ::tokenizer::extract_bare_word {text start_pos} {
    set len [string length $text]
    set i $start_pos
    set result ""

    while {$i < $len} {
        set char [string index $text $i]

        # Stop at whitespace or special characters
        if {[string is space $char] || \
            $char eq "\{" || $char eq "\}" || \
            $char eq "\[" || $char eq "\]" || \
            $char eq "\"" || $char eq "\$" || \
            $char eq ";"} {
            break
        }

        append result $char
        incr i
    }

    return [dict create text $result end_pos $i]
}

# ===========================================================================
# UTILITY FUNCTIONS
# ===========================================================================

# Enable or disable debug output
#
# Args:
#   enabled - 1 to enable, 0 to disable
#
proc ::tokenizer::set_debug {enabled} {
    variable debug
    set debug $enabled
}

# Get current debug state
#
# Returns:
#   1 if debug is enabled, 0 otherwise
#
proc ::tokenizer::get_debug {} {
    variable debug
    return $debug
}

# Print a token list in a readable format (for debugging)
#
# Args:
#   tokens - List of tokens to print
#
proc ::tokenizer::print_tokens {tokens} {
    puts "Tokens ([llength $tokens] total):"
    set i 0
    foreach token $tokens {
        puts "  \[$i\] '$token'"
        incr i
    }
}
