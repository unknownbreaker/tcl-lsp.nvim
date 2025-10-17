#!/usr/bin/env tclsh
# tcl/core/ast_builder.tcl
# Production AST Builder - Uses literal tokenizer for accurate parsing
#
# This AST builder constructs an Abstract Syntax Tree from TCL source code
# without executing or evaluating the code. It uses a literal tokenizer to
# preserve exact source text representation, which is critical for Language
# Server Protocol (LSP) features like go-to-definition and refactoring.

# Load the tokenizer module
set script_dir [file dirname [file normalize [info script]]]
if {[catch {source [file join $script_dir tokenizer.tcl]} err]} {
    puts stderr "Error loading tokenizer.tcl: $err"
    exit 1
}

namespace eval ::ast {
    variable current_file "<string>"
    variable line_map
    variable debug 0
}

# ===========================================================================
# UTILITY FUNCTIONS - Position tracking and helpers
# ===========================================================================

# Create a position range for AST nodes
#
# Args:
#   start_line, start_col - Starting position
#   end_line, end_col     - Ending position
#
# Returns:
#   Dict with start and end_pos keys
#
proc ::ast::make_range {start_line start_col end_line end_col} {
    return [dict create \
        start [dict create line $start_line column $start_col] \
        end_pos [dict create line $end_line column $end_col]]
}

# Build a line number mapping for the source code
#
# This enables us to convert byte offsets to line/column positions,
# which is necessary for LSP range information.
#
# Args:
#   code - The source code to map
#
proc ::ast::build_line_map {code} {
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
# Args:
#   offset - Byte offset into the source code
#
# Returns:
#   List of {line_num column_num}
#
proc ::ast::offset_to_line {offset} {
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

    return [list 1 1]
}

# Count the number of lines in a text string
#
# Args:
#   text - The text to count lines in
#
# Returns:
#   Number of lines
#
proc ::ast::count_lines {text} {
    return [expr {[llength [split $text "\n"]] - 1}]
}

# Extract comments from source code
#
# Comments in TCL start with # at the beginning of a line (after whitespace)
#
# Args:
#   code - The source code
#
# Returns:
#   List of comment dicts with type, text, and line keys
#
proc ::ast::extract_comments {code} {
    set comments [list]
    set line_num 0

    foreach line [split $code "\n"] {
        incr line_num

        # Match comment lines: optional whitespace + # + comment text
        if {[regexp {^(\s*)#(.*)} $line -> indent text]} {
            lappend comments [dict create \
                type "comment" \
                text $text \
                line $line_num]
        }
    }

    return $comments
}

# ===========================================================================
# COMMAND EXTRACTION - Breaking source into individual commands
# ===========================================================================

# Extract individual TCL commands from source code
#
# This function splits the source into separate commands, handling:
#   - Multi-line commands (incomplete until braces balanced)
#   - Comments (single and multi-line)
#   - Empty lines
#
# Args:
#   code       - The source code
#   start_line - Line number to start from (for nested parsing)
#
# Returns:
#   List of command dicts with text, start_line, end_line keys
#
proc ::ast::extract_commands {code start_line} {
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

    return $commands
}

# ===========================================================================
# COMMAND PARSING - Converting command text to AST nodes
# ===========================================================================

# Parse a single command into an AST node
#
# This is the main dispatch function that determines the command type
# and calls the appropriate specialized parser.
#
# Args:
#   cmd_dict - Dict with text, start_line, end_line keys
#   depth    - Nesting depth (for recursive parsing)
#
# Returns:
#   AST node dict, or empty string if not a recognized command
#
proc ::ast::parse_command {cmd_dict depth} {
    variable debug

    set cmd_text [dict get $cmd_dict text]
    set start_line [dict get $cmd_dict start_line]
    set end_line [dict get $cmd_dict end_line]

    # Use tokenizer to count words (not llength which evaluates!)
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count == 0} {
        return ""
    }

    # Get command name using tokenizer (not lindex which evaluates!)
    set cmd_name [::tokenizer::get_token $cmd_text 0]

    if {$debug} {
        puts "  Parsing command: $cmd_name at line $start_line (depth $depth)"
    }

    # Dispatch to specialized parser based on command name
    switch -exact -- $cmd_name {
        "proc" {
            return [parse_proc $cmd_text $start_line $end_line $depth]
        }
        "set" {
            return [parse_set $cmd_text $start_line $end_line]
        }
        "variable" {
            return [parse_variable $cmd_text $start_line $end_line]
        }
        "global" {
            return [parse_global $cmd_text $start_line $end_line]
        }
        "upvar" {
            return [parse_upvar $cmd_text $start_line $end_line]
        }
        "array" {
            return [parse_array $cmd_text $start_line $end_line]
        }
        "namespace" {
            return [parse_namespace $cmd_text $start_line $end_line $depth]
        }
        "package" {
            return [parse_package $cmd_text $start_line $end_line]
        }
        "if" {
            return [parse_if $cmd_text $start_line $end_line $depth]
        }
        "while" {
            return [parse_while $cmd_text $start_line $end_line $depth]
        }
        "for" {
            return [parse_for $cmd_text $start_line $end_line $depth]
        }
        "foreach" {
            return [parse_foreach $cmd_text $start_line $end_line $depth]
        }
        "switch" {
            return [parse_switch $cmd_text $start_line $end_line $depth]
        }
        "expr" {
            return [parse_expr $cmd_text $start_line $end_line]
        }
        "list" {
            return [parse_list $cmd_text $start_line $end_line]
        }
        "lappend" {
            return [parse_lappend $cmd_text $start_line $end_line]
        }
        "puts" {
            return [parse_puts $cmd_text $start_line $end_line]
        }
        default {
            # Unknown command - skip it
            return ""
        }
    }
}

# ===========================================================================
# SPECIALIZED COMMAND PARSERS
# ===========================================================================
# Each parser extracts the structure of a specific TCL command type
# and returns an AST node with the appropriate fields.

# Parse a proc (procedure) definition
#
# Syntax: proc name {args} {body}
#
proc ::ast::parse_proc {cmd_text start_line end_line depth} {
    variable debug

    set word_count [::tokenizer::count_tokens $cmd_text]
    if {$word_count < 4} {
        return [dict create \
            type "error" \
            message "Invalid proc syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set proc_name [::tokenizer::get_token $cmd_text 1]
    set args_list_raw [::tokenizer::get_token $cmd_text 2]
    set body_raw [::tokenizer::get_token $cmd_text 3]

    # Remove surrounding braces from args and body
    # (they're part of the literal token)
    if {[string index $args_list_raw 0] eq "\{" && [string index $args_list_raw end] eq "\}"} {
        set args_list [string range $args_list_raw 1 end-1]
    } else {
        set args_list $args_list_raw
    }

    if {[string index $body_raw 0] eq "\{" && [string index $body_raw end] eq "\}"} {
        set body [string range $body_raw 1 end-1]
    } else {
        set body $body_raw
    }

    # Parse parameters - can be simple names or {name default} pairs
    set params [list]
    foreach arg $args_list {
        if {[llength $arg] == 2} {
            # Parameter with default value
            set param_name [lindex $arg 0]
            set param_default [lindex $arg 1]

            # Strip quotes from default if present
            if {[string index $param_default 0] eq "\"" && [string index $param_default end] eq "\""} {
                set param_default [string range $param_default 1 end-1]
            }

            lappend params [dict create \
                name $param_name \
                default $param_default]
        } elseif {[llength $arg] == 1} {
            # Simple parameter
            set param_dict [dict create name $arg]

            # Special handling for 'args' (varargs parameter)
            if {$arg eq "args"} {
                dict set param_dict is_varargs 1
            }

            lappend params $param_dict
        }
    }

    if {$debug} {
        puts "    Proc: $proc_name with [llength $params] parameters"
    }

    # Recursively parse the procedure body
    set body_start_line [expr {$start_line + 1}]
    set nested_nodes [find_all_nodes $body $body_start_line [expr {$depth + 1}]]

    set body_node [dict create children $nested_nodes]

    set proc_node [dict create \
        type "proc" \
        name $proc_name \
        params $params \
        body $body_node \
        range [make_range $start_line 1 $end_line 50]]

    return $proc_node
}

# Parse a set command (variable assignment)
#
# Syntax: set varname [value]
#
# This is a CRITICAL parser - it must preserve exact text representation!
#
proc ::ast::parse_set {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid set syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    # Extract tokens literally (no evaluation!)
    set var_name [::tokenizer::get_token $cmd_text 1]
    set value ""
    if {$word_count >= 3} {
        set value [::tokenizer::get_token $cmd_text 2]
    }

    return [dict create \
        type "set" \
        var_name $var_name \
        value $value \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse a variable declaration
#
# Syntax: variable name [value]
#
proc ::ast::parse_variable {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid variable syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set var_name [::tokenizer::get_token $cmd_text 1]
    set value ""
    if {$word_count >= 3} {
        set value [::tokenizer::get_token $cmd_text 2]
    }

    return [dict create \
        type "variable" \
        name $var_name \
        value $value \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse a global variable declaration
#
# Syntax: global var1 [var2 ...]
#
proc ::ast::parse_global {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid global syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    # Get all variable names after 'global'
    set var_names [list]
    for {set i 1} {$i < $word_count} {incr i} {
        lappend var_names [::tokenizer::get_token $cmd_text $i]
    }

    return [dict create \
        type "global" \
        vars $var_names \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse an upvar declaration
#
# Syntax: upvar level otherVar myVar
#
proc ::ast::parse_upvar {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid upvar syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set level [::tokenizer::get_token $cmd_text 1]
    set other_var [::tokenizer::get_token $cmd_text 2]
    set local_var ""
    if {$word_count >= 4} {
        set local_var [::tokenizer::get_token $cmd_text 3]
    }

    return [dict create \
        type "upvar" \
        level $level \
        other_var $other_var \
        local_var $local_var \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse an array command
#
# Syntax: array subcommand arrayName [...]
#
proc ::ast::parse_array {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid array syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set subcommand [::tokenizer::get_token $cmd_text 1]
    set array_name [::tokenizer::get_token $cmd_text 2]

    return [dict create \
        type "array" \
        subcommand $subcommand \
        array_name $array_name \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse a namespace command
#
# Syntax: namespace eval name {body}
#         namespace import pattern
#         namespace export pattern
#
proc ::ast::parse_namespace {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid namespace syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set subcommand [::tokenizer::get_token $cmd_text 1]

    switch -exact -- $subcommand {
        "eval" {
            if {$word_count < 4} {
                return [dict create \
                    type "error" \
                    message "Invalid namespace eval syntax" \
                    range [make_range $start_line 1 $end_line 50]]
            }

            set ns_name [::tokenizer::get_token $cmd_text 2]
            set body_raw [::tokenizer::get_token $cmd_text 3]

            # Remove braces from body
            if {[string index $body_raw 0] eq "\{" && [string index $body_raw end] eq "\}"} {
                set body_text [string range $body_raw 1 end-1]
            } else {
                set body_text $body_raw
            }

            # Recursively parse namespace body
            set body_start_line [expr {$start_line + 1}]
            set body_nodes [find_all_nodes $body_text $body_start_line [expr {$depth + 1}]]

            return [dict create \
                type "namespace" \
                subcommand "eval" \
                name $ns_name \
                body $body_nodes \
                range [make_range $start_line 1 $end_line 50]]
        }
        "import" - "export" {
            # Collect all patterns
            set patterns [list]
            for {set i 2} {$i < $word_count} {incr i} {
                lappend patterns [::tokenizer::get_token $cmd_text $i]
            }

            set type_name "namespace_${subcommand}"
            return [dict create \
                type $type_name \
                patterns $patterns \
                range [make_range $start_line 1 $end_line 50]]
        }
        default {
            return [dict create \
                type "namespace" \
                subcommand $subcommand \
                range [make_range $start_line 1 $end_line 50]]
        }
    }
}

# Parse a package command
#
# Syntax: package require pkgName [version]
#         package provide pkgName version
#
proc ::ast::parse_package {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid package syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set subcommand [::tokenizer::get_token $cmd_text 1]

    switch -exact -- $subcommand {
        "require" {
            if {$word_count < 3} {
                return [dict create \
                    type "error" \
                    message "Invalid package require syntax" \
                    range [make_range $start_line 1 $end_line 50]]
            }

            set pkg_name [::tokenizer::get_token $cmd_text 2]
            set version ""
            if {$word_count >= 4} {
                set version [::tokenizer::get_token $cmd_text 3]
            }

            return [dict create \
                type "package_require" \
                package_name $pkg_name \
                version $version \
                range [make_range $start_line 1 $end_line 50]]
        }
        "provide" {
            if {$word_count < 4} {
                return [dict create \
                    type "error" \
                    message "Invalid package provide syntax" \
                    range [make_range $start_line 1 $end_line 50]]
            }

            set pkg_name [::tokenizer::get_token $cmd_text 2]
            set version [::tokenizer::get_token $cmd_text 3]

            return [dict create \
                type "package_provide" \
                package $pkg_name \
                version $version \
                range [make_range $start_line 1 $end_line 50]]
        }
        default {
            return [dict create \
                type "package" \
                subcommand $subcommand \
                range [make_range $start_line 1 $end_line 50]]
        }
    }
}

# Parse an if statement
#
# Syntax: if {condition} {then_body} [elseif {condition} {body}]* [else {body}]
#
proc ::ast::parse_if {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid if syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set condition [::tokenizer::get_token $cmd_text 1]
    set then_body [::tokenizer::get_token $cmd_text 2]

    set if_node [dict create \
        type "if" \
        condition $condition \
        then_body $then_body \
        range [make_range $start_line 1 $end_line 50]]

    # Parse optional elseif and else clauses
    set elseif_branches [list]
    set else_body ""
    set has_else 0

    set idx 3
    while {$idx < $word_count} {
        set keyword [::tokenizer::get_token $cmd_text $idx]

        if {$keyword eq "elseif"} {
            if {$idx + 2 >= $word_count} {
                break
            }
            set elseif_cond [::tokenizer::get_token $cmd_text [expr {$idx + 1}]]
            set elseif_body [::tokenizer::get_token $cmd_text [expr {$idx + 2}]]
            lappend elseif_branches [dict create \
                condition $elseif_cond \
                body $elseif_body]
            set idx [expr {$idx + 3}]
        } elseif {$keyword eq "else"} {
            if {$idx + 1 >= $word_count} {
                break
            }
            set else_body [::tokenizer::get_token $cmd_text [expr {$idx + 1}]]
            set has_else 1
            break
        } else {
            break
        }
    }

    if {[llength $elseif_branches] > 0} {
        dict set if_node elseif_branches $elseif_branches
    }

    if {$has_else} {
        dict set if_node else_body $else_body
    }

    return $if_node
}

# Parse a while loop
#
# Syntax: while {condition} {body}
#
proc ::ast::parse_while {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid while syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set condition [::tokenizer::get_token $cmd_text 1]
    set body [::tokenizer::get_token $cmd_text 2]

    return [dict create \
        type "while" \
        condition $condition \
        body $body \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse a for loop
#
# Syntax: for {init} {condition} {increment} {body}
#
proc ::ast::parse_for {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 5} {
        return [dict create \
            type "error" \
            message "Invalid for syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set init [::tokenizer::get_token $cmd_text 1]
    set condition [::tokenizer::get_token $cmd_text 2]
    set increment [::tokenizer::get_token $cmd_text 3]
    set body [::tokenizer::get_token $cmd_text 4]

    return [dict create \
        type "for" \
        init $init \
        condition $condition \
        increment $increment \
        body $body \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse a foreach loop
#
# Syntax: foreach varname list {body}
#
proc ::ast::parse_foreach {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 4} {
        return [dict create \
            type "error" \
            message "Invalid foreach syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set var_name [::tokenizer::get_token $cmd_text 1]
    set list_var [::tokenizer::get_token $cmd_text 2]
    set body [::tokenizer::get_token $cmd_text 3]

    return [dict create \
        type "foreach" \
        var_name $var_name \
        list $list_var \
        body $body \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse a switch statement
#
# Syntax: switch value {pattern1 body1 pattern2 body2 ...}
#
proc ::ast::parse_switch {cmd_text start_line end_line depth} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid switch syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set value [::tokenizer::get_token $cmd_text 1]
    set switch_body_raw [::tokenizer::get_token $cmd_text end]

    # Remove braces from switch body
    if {[string index $switch_body_raw 0] eq "\{" && [string index $switch_body_raw end] eq "\}"} {
        set switch_body [string range $switch_body_raw 1 end-1]
    } else {
        set switch_body $switch_body_raw
    }

    # Parse case patterns and bodies
    set cases [list]
    set case_count [llength $switch_body]

    for {set i 0} {$i < $case_count} {incr i 2} {
        set pattern [lindex $switch_body $i]
        set body ""
        if {$i + 1 < $case_count} {
            set body [lindex $switch_body [expr {$i + 1}]]
        }

        lappend cases [dict create \
            pattern $pattern \
            body $body]
    }

    return [dict create \
        type "switch" \
        value $value \
        cases $cases \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse an expr command
#
# Syntax: expr {expression}
#
proc ::ast::parse_expr {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid expr syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set expression [::tokenizer::get_token $cmd_text 1]

    return [dict create \
        type "expr" \
        expression $expression \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse a list command
#
# Syntax: list element1 [element2 ...]
#
proc ::ast::parse_list {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid list syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set elements [list]
    for {set i 1} {$i < $word_count} {incr i} {
        lappend elements [::tokenizer::get_token $cmd_text $i]
    }

    return [dict create \
        type "list" \
        elements $elements \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse an lappend command
#
# Syntax: lappend varname value
#
proc ::ast::parse_lappend {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 3} {
        return [dict create \
            type "error" \
            message "Invalid lappend syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    set var_name [::tokenizer::get_token $cmd_text 1]
    set value [::tokenizer::get_token $cmd_text 2]

    return [dict create \
        type "lappend" \
        name $var_name \
        value $value \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse a puts command
#
# Syntax: puts [options] string
#
proc ::ast::parse_puts {cmd_text start_line end_line} {
    set word_count [::tokenizer::count_tokens $cmd_text]

    if {$word_count < 2} {
        return [dict create \
            type "error" \
            message "Invalid puts syntax" \
            range [make_range $start_line 1 $end_line 50]]
    }

    # Collect all arguments
    set args [list]
    for {set i 1} {$i < $word_count} {incr i} {
        lappend args [::tokenizer::get_token $cmd_text $i]
    }

    return [dict create \
        type "puts" \
        args $args \
        range [make_range $start_line 1 $end_line 50]]
}

# ===========================================================================
# RECURSIVE PARSING
# ===========================================================================

# Find all AST nodes in a code block recursively
#
# This function handles nested structures like procs inside namespaces.
#
# Args:
#   code       - The code block to parse
#   start_line - Starting line number
#   depth      - Nesting depth
#
# Returns:
#   List of AST nodes
#
proc ::ast::find_all_nodes {code start_line depth} {
    variable debug

    # Extract individual commands from the code
    set commands [extract_commands $code $start_line]
    set nodes [list]

    # Parse each command into an AST node
    foreach cmd_dict $commands {
        set node [parse_command $cmd_dict $depth]
        if {$node ne ""} {
            lappend nodes $node
        }
    }

    return $nodes
}

# ===========================================================================
# JSON SERIALIZATION
# ===========================================================================
# Convert AST to JSON format for communication with the Lua layer

proc ::ast::dict_to_json {dict_data {indent_level 0}} {
    set indent [string repeat "  " $indent_level]
    set next_indent [string repeat "  " [expr {$indent_level + 1}]]

    set result "\{\n"
    set first_key 1

    dict for {key value} $dict_data {
        if {!$first_key} {
            append result ",\n"
        }
        set first_key 0

        append result "${next_indent}\"$key\": "

        if {[string is list $value] && [llength $value] > 0} {
            append result [list_to_json $value [expr {$indent_level + 1}]]
        } elseif {[string is dict $value]} {
            append result [dict_to_json $value [expr {$indent_level + 1}]]
        } elseif {[string is integer -strict $value] || [string is double -strict $value]} {
            append result $value
        } else {
            append result "\"[escape_json $value]\""
        }
    }

    append result "\n${indent}\}"
    return $result
}

proc ::ast::list_to_json {value {indent_level 0}} {
    set next_indent [string repeat "  " $indent_level]

    if {[llength $value] == 0} {
        return "\[\]"
    }

    set first_elem [lindex $value 0]
    if {[string is dict $first_elem] && [dict size $first_elem] > 0} {
        # List of dicts
        set result "\[\n"
        set first_item 1
        foreach item $value {
            if {!$first_item} {
                append result ",\n"
            }
            set first_item 0
            append result "${next_indent}  "
            append result [dict_to_json $item [expr {$indent_level + 2}]]
        }
        append result "\n${next_indent}\]"
        return $result
    } else {
        # List of primitives
        set result "\["
        set first_item 1
        foreach item $value {
            if {!$first_item} {
                append result ", "
            }
            set first_item 0
            if {[string is integer -strict $item] || [string is double -strict $item]} {
                append result $item
            } else {
                append result "\"[escape_json $item]\""
            }
        }
        append result "\]"
        return $result
    }
}

proc ::ast::escape_json {str} {
    set str [string map {
        \\ \\\\
        \" \\\"
        \n \\n
        \r \\r
        \t \\t
    } $str]
    return $str
}

proc ::ast::to_json {ast} {
    return [dict_to_json $ast 0]
}

# ===========================================================================
# MAIN BUILD FUNCTION
# ===========================================================================

# Build an Abstract Syntax Tree from TCL source code
#
# This is the main entry point that coordinates the entire parsing process.
#
# Args:
#   code     - The TCL source code to parse
#   filepath - Path to the source file (for error reporting)
#
# Returns:
#   AST dict with type, filepath, comments, children, had_error, errors keys
#
proc ::ast::build {code {filepath "<string>"}} {
    variable current_file
    variable debug

    set current_file $filepath

    if {$debug} {
        puts "\n=== Building AST for $filepath ==="
        puts "Code length: [string length $code] chars"
    }

    # Check if the code is syntactically complete
    if {![info complete $code]} {
        if {$debug} {
            puts "ERROR: Incomplete TCL code"
        }
        return [dict create \
            type "root" \
            filepath $filepath \
            errors [list [dict create \
                type "error" \
                message "Syntax error: missing close-brace" \
                range [make_range 1 1 1 1] \
                error_type "incomplete" \
                suggestion "Check for missing closing brace \}"]] \
            had_error 1 \
            children [list] \
            comments [list]]
    }

    # Build position tracking map
    build_line_map $code

    # Extract comments
    set comments [extract_comments $code]

    if {$debug} {
        puts "Found [llength $comments] comments"
    }

    # Parse all top-level nodes
    set nodes [find_all_nodes $code 1 0]

    if {$debug} {
        puts "Found [llength $nodes] total nodes"
    }

    # Collect any error nodes
    set error_nodes [list]
    foreach node $nodes {
        if {[dict exists $node type] && [dict get $node type] eq "error"} {
            lappend error_nodes $node
        }
    }

    set had_error 0
    if {[llength $error_nodes] > 0} {
        set had_error 1
    }

    if {$debug} {
        puts "Found [llength $error_nodes] errors"
        puts "=== AST Building Complete ===\n"
    }

    # Return the complete AST
    return [dict create \
        type "root" \
        filepath $filepath \
        comments $comments \
        children $nodes \
        had_error $had_error \
        errors $error_nodes]
}
