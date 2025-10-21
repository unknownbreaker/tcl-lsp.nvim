#!/usr/bin/env tclsh
# tcl/core/ast/delimiters.tcl
# Delimiter Handling Helper Module
#
# This module provides utilities for working with tokens that include delimiters
# (quotes, braces, brackets) as returned by the fixed tokenizer.
#
# The tokenizer now preserves LITERAL text including delimiters:
#   - "hello" stays as "hello" (with quotes)
#   - {42} stays as {42} (with braces)
#   - [expr 1] stays as [expr 1] (with brackets)
#
# This module helps parsers decide:
#   1. What kind of token is this? (quoted, braced, bracketed, bare)
#   2. Should I strip the delimiters? (for simple values)
#   3. Should I recursively parse it? (for command substitutions)

namespace eval ::ast::delimiters {
    namespace export strip_outer is_quoted is_braced is_bracketed is_bare get_token_type
}

# Get the type of a token based on its delimiters
#
# Args:
#   token - The token string (may include delimiters)
#
# Returns:
#   One of: "quoted", "braced", "bracketed", "bare"
#
proc ::ast::delimiters::get_token_type {token} {
    if {$token eq ""} {
        return "bare"
    }

    set first [string index $token 0]
    set last [string index $token end]

    if {$first eq "\"" && $last eq "\""} {
        return "quoted"
    } elseif {$first eq "\{" && $last eq "\}"} {
        return "braced"
    } elseif {$first eq "\[" && $last eq "\]"} {
        return "bracketed"
    } else {
        return "bare"
    }
}

# Check if a token is quoted (starts and ends with ")
#
# Args:
#   token - The token string
#
# Returns:
#   1 if quoted, 0 otherwise
#
proc ::ast::delimiters::is_quoted {token} {
    if {[string length $token] < 2} {
        return 0
    }
    return [expr {[string index $token 0] eq "\"" && [string index $token end] eq "\""}]
}

# Check if a token is braced (starts and ends with {})
#
# Args:
#   token - The token string
#
# Returns:
#   1 if braced, 0 otherwise
#
proc ::ast::delimiters::is_braced {token} {
    if {[string length $token] < 2} {
        return 0
    }
    return [expr {[string index $token 0] eq "\{" && [string index $token end] eq "\}"}]
}

# Check if a token is bracketed (starts and ends with [])
#
# Args:
#   token - The token string
#
# Returns:
#   1 if bracketed (command substitution), 0 otherwise
#
proc ::ast::delimiters::is_bracketed {token} {
    if {[string length $token] < 2} {
        return 0
    }
    return [expr {[string index $token 0] eq "\[" && [string index $token end] eq "\]"}]
}

# Check if a token is bare (no delimiters)
#
# Args:
#   token - The token string
#
# Returns:
#   1 if bare word, 0 otherwise
#
proc ::ast::delimiters::is_bare {token} {
    if {$token eq ""} {
        return 1
    }
    set first [string index $token 0]
    return [expr {$first ne "\"" && $first ne "\{" && $first ne "\["}]
}

# Strip outer delimiters from a token
#
# This is for SIMPLE values where we want the content, not the delimiters.
# For command substitutions ([...]), DON'T use this - use parse_command_sub instead.
#
# Examples:
#   strip_outer "hello"  → hello (quotes removed)
#   strip_outer {42}     → 42 (braces removed)
#   strip_outer [expr 1] → [expr 1] (UNCHANGED - use parse_command_sub instead!)
#   strip_outer hello    → hello (unchanged, no delimiters)
#
# Args:
#   token - The token string
#
# Returns:
#   The token with outer delimiters removed (if quoted or braced)
#
proc ::ast::delimiters::strip_outer {token} {
    if {$token eq ""} {
        return ""
    }

    set len [string length $token]
    if {$len < 2} {
        return $token
    }

    set first [string index $token 0]
    set last [string index $token end]

    # Strip quotes
    if {$first eq "\"" && $last eq "\""} {
        return [string range $token 1 end-1]
    }

    # Strip braces
    if {$first eq "\{" && $last eq "\}"} {
        return [string range $token 1 end-1]
    }

    # DON'T strip brackets - those need recursive parsing
    # Return as-is for bare words and bracketed commands
    return $token
}

# Get the content of a quoted or braced token
#
# Similar to strip_outer but more explicit about what it does.
#
# Args:
#   token - The token string
#
# Returns:
#   The content between delimiters, or the token unchanged if not quoted/braced
#
proc ::ast::delimiters::get_content {token} {
    return [strip_outer $token]
}

# Extract the command from a command substitution token
#
# For tokens like [expr {1 + 2}], this extracts the inner command: expr {1 + 2}
#
# Args:
#   token - The token string (should be bracketed)
#
# Returns:
#   The command text inside the brackets, or empty string if not bracketed
#
proc ::ast::delimiters::extract_command {token} {
    if {![is_bracketed $token]} {
        return ""
    }

    # Strip the outer brackets
    return [string range $token 1 end-1]
}

# Normalize a token for AST storage
#
# This decides the best representation for a token in the AST:
#   - Quoted strings → content without quotes (for display)
#   - Braced values → content without braces (for simple values)
#   - Bracketed commands → KEEP AS-IS (marker for recursive parsing)
#   - Bare words → as-is
#
# Use this in parsers when storing values in the AST.
#
# Args:
#   token - The token string
#
# Returns:
#   The normalized representation
#
proc ::ast::delimiters::normalize {token} {
    set type [get_token_type $token]

    switch -exact -- $type {
        "quoted" {
            # Strip quotes for simple string values
            return [strip_outer $token]
        }
        "braced" {
            # Strip braces for simple values
            return [strip_outer $token]
        }
        "bracketed" {
            # KEEP brackets - this signals recursive parsing needed
            return $token
        }
        "bare" {
            # Keep as-is
            return $token
        }
        default {
            return $token
        }
    }
}

# Check if a token needs recursive parsing
#
# Returns true if the token is a command substitution that needs
# to be parsed into a subtree.
#
# Args:
#   token - The token string
#
# Returns:
#   1 if needs recursive parsing (is bracketed), 0 otherwise
#
proc ::ast::delimiters::needs_parsing {token} {
    return [is_bracketed $token]
}

# Parse a value token into appropriate AST representation
#
# This is the HIGH-LEVEL function parsers should use.
# It decides whether to:
#   1. Return a simple string value (strip delimiters)
#   2. Return a marker for recursive parsing (bracketed commands)
#
# Args:
#   token      - The token string
#   start_line - Starting line (for recursive parse)
#   end_line   - Ending line (for recursive parse)
#   depth      - Nesting depth (for recursive parse)
#
# Returns:
#   Either a simple string value, or a dict with type "command_substitution"
#
proc ::ast::delimiters::parse_value {token start_line end_line depth} {
    if {[is_bracketed $token]} {
        # This is a command substitution - needs recursive parsing
        # Return a marker dict that parsers can recognize
        return [dict create \
            type "command_substitution" \
            command [extract_command $token] \
            range [::ast::utils::make_range $start_line 1 $end_line 1] \
            depth $depth]
    } else {
        # Simple value - strip delimiters and return as string
        return [normalize $token]
    }
}

# ===========================================================================
# SELF-TEST
# ===========================================================================

if {[info exists argv0] && $argv0 eq [info script]} {
    puts "Testing Delimiter Helper Module"
    puts "================================\n"

    set total 0
    set passed 0

    proc test {name result expected} {
        global total passed
        incr total

        if {$result eq $expected} {
            puts "✓ PASS: $name"
            incr passed
        } else {
            puts "✗ FAIL: $name"
            puts "  Expected: \[$expected\]"
            puts "  Got:      \[$result\]"
        }
    }

    # Load dependencies for parse_value test
    set script_dir [file dirname [file normalize [info script]]]
    if {[catch {source [file join $script_dir utils.tcl]} err]} {
        puts "Note: Could not load utils.tcl for full testing: $err"
        puts "Running basic tests only...\n"
    }

    puts "Test Group 1: Token Type Detection"
    test "Quoted string type" [::ast::delimiters::get_token_type {"hello"}] "quoted"
    test "Braced value type" [::ast::delimiters::get_token_type {{42}}] "braced"
    test "Bracketed cmd type" [::ast::delimiters::get_token_type {[expr 1]}] "bracketed"
    test "Bare word type" [::ast::delimiters::get_token_type {hello}] "bare"

    puts ""
    puts "Test Group 2: Type Checking"
    test "is_quoted on quoted" [::ast::delimiters::is_quoted {"hello"}] 1
    test "is_quoted on bare" [::ast::delimiters::is_quoted {hello}] 0
    test "is_braced on braced" [::ast::delimiters::is_braced {{42}}] 1
    test "is_braced on bare" [::ast::delimiters::is_braced {42}] 0
    test "is_bracketed on cmd" [::ast::delimiters::is_bracketed {[expr 1]}] 1
    test "is_bracketed on bare" [::ast::delimiters::is_bracketed {expr}] 0
    test "is_bare on bare" [::ast::delimiters::is_bare {hello}] 1
    test "is_bare on quoted" [::ast::delimiters::is_bare {"hello"}] 0

    puts ""
    puts "Test Group 3: Delimiter Stripping"
    test "strip_outer quotes" [::ast::delimiters::strip_outer {"hello"}] "hello"
    test "strip_outer braces" [::ast::delimiters::strip_outer {{42}}] "42"
    test "strip_outer brackets UNCHANGED" [::ast::delimiters::strip_outer {[expr 1]}] {[expr 1]}
    test "strip_outer bare" [::ast::delimiters::strip_outer {hello}] "hello"
    test "strip_outer empty" [::ast::delimiters::strip_outer {}] ""

    puts ""
    puts "Test Group 4: Command Extraction"
    test "extract_command simple" [::ast::delimiters::extract_command {[expr 1]}] "expr 1"
    test "extract_command complex" [::ast::delimiters::extract_command {[expr {1 + 2}]}] "expr {1 + 2}"
    test "extract_command bare" [::ast::delimiters::extract_command {expr}] ""

    puts ""
    puts "Test Group 5: Normalization"
    test "normalize quoted" [::ast::delimiters::normalize {"hello"}] "hello"
    test "normalize braced" [::ast::delimiters::normalize {{42}}] "42"
    test "normalize bracketed" [::ast::delimiters::normalize {[expr 1]}] {[expr 1]}
    test "normalize bare" [::ast::delimiters::normalize {hello}] "hello"

    puts ""
    puts "Test Group 6: Parsing Decision"
    test "needs_parsing cmd" [::ast::delimiters::needs_parsing {[expr 1]}] 1
    test "needs_parsing quoted" [::ast::delimiters::needs_parsing {"hello"}] 0
    test "needs_parsing bare" [::ast::delimiters::needs_parsing {42}] 0

    puts ""
    puts "Results: $passed/$total tests passed"
    puts ""

    if {$passed == $total} {
        puts "✓ ALL TESTS PASSED"
        puts ""
        puts "Key Features Verified:"
        puts "  ✓ Token type detection (quoted/braced/bracketed/bare)"
        puts "  ✓ Delimiter stripping for simple values"
        puts "  ✓ Command extraction from [...]"
        puts "  ✓ Smart normalization decisions"
        puts "  ✓ Parsing decision support"
        exit 0
    } else {
        puts "✗ SOME TESTS FAILED"
        exit 1
    }
}
