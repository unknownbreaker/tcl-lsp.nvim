#!/usr/bin/env tclsh
# tcl/core/ast_builder.tcl
# Production AST Builder - Recursive text-based parsing (NO safe interpreter)

namespace eval ::ast {
    variable current_file "<string>"
    variable line_map
    variable debug 0
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Create position range
proc ::ast::make_range {start_line start_col end_line end_col} {
    return [dict create \
        start [dict create line $start_line column $start_col] \
        end [dict create line $end_line column $end_col]]
}

# Build line number mapping for position tracking
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

# Get line number from code offset
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

# Count line numbers in text
proc ::ast::count_lines {text} {
    return [expr {[llength [split $text "\n"]] - 1}]
}

# Extract comments from source code
proc ::ast::extract_comments {code} {
    set comments [list]
    set line_num 0

    foreach line [split $code "\n"] {
        incr line_num

        if {[regexp {^(\s*)#(.*)$} $line -> indent comment_text]} {
            set col [expr {[string length $indent] + 1}]
            lappend comments [dict create \
                type "comment" \
                text [string trim $comment_text] \
                range [make_range $line_num $col $line_num [string length $line]]]
        }
    }

    return $comments
}

# ============================================================================
# COMMAND EXTRACTION (Character-by-character scanning)
# ============================================================================

# Extract all commands from code without executing
proc ::ast::extract_commands {code start_line} {
    variable debug

    set commands [list]
    set pos 0
    set code_len [string length $code]
    set current_line $start_line

    while {$pos < $code_len} {
        # Skip whitespace and track line numbers
        while {$pos < $code_len && [string is space [string index $code $pos]]} {
            if {[string index $code $pos] eq "\n"} {
                incr current_line
            }
            incr pos
        }

        if {$pos >= $code_len} break

        # Skip comments
        if {[string index $code $pos] eq "#"} {
            while {$pos < $code_len && [string index $code $pos] ne "\n"} {
                incr pos
            }
            if {$pos < $code_len && [string index $code $pos] eq "\n"} {
                incr current_line
                incr pos
            }
            continue
        }

        # Extract complete command
        set cmd_start_pos $pos
        set cmd_start_line $current_line
        set cmd_text ""
        set brace_depth 0
        set in_quotes 0
        set in_brackets 0

        while {$pos < $code_len} {
            set char [string index $code $pos]
            append cmd_text $char

            # Handle backslash escapes
            if {$char eq "\\"} {
                incr pos
                if {$pos < $code_len} {
                    set next_char [string index $code $pos]
                    append cmd_text $next_char
                    if {$next_char eq "\n"} {
                        incr current_line
                    }
                }
                incr pos
                continue
            }

            # Track quotes
            if {$char eq "\""} {
                set in_quotes [expr {!$in_quotes}]
            }

            # Track braces and brackets (only outside quotes)
            if {!$in_quotes} {
                if {$char eq "\{"} {
                    incr brace_depth
                } elseif {$char eq "\}"} {
                    incr brace_depth -1
                } elseif {$char eq "\["} {
                    incr in_brackets
                } elseif {$char eq "\]"} {
                    incr in_brackets -1
                }

                # Track newlines
                if {$char eq "\n"} {
                    incr current_line

                    # Check if command is complete at newline
                    if {$brace_depth == 0 && $in_brackets == 0 && [info complete $cmd_text]} {
                        incr pos
                        break
                    }
                }

                # Semicolon ends command at depth 0
                if {$char eq ";" && $brace_depth == 0 && $in_brackets == 0} {
                    incr pos
                    break
                }
            }

            incr pos

            # Check if command is complete
            if {$brace_depth == 0 && $in_brackets == 0 && !$in_quotes} {
                if {[info complete $cmd_text]} {
                    # Look ahead to see if next char starts a new command
                    if {$pos >= $code_len} {
                        break
                    }
                    set next_char [string index $code $pos]
                    if {$next_char eq "\n" || $next_char eq ";" || [string is space $next_char]} {
                        break
                    }
                }
            }
        }

        set cmd_text [string trim $cmd_text " \t\n;"]
        if {$cmd_text eq ""} continue

        # Count lines in command for end position
        set lines_in_cmd [count_lines $cmd_text]
        set cmd_end_line [expr {$cmd_start_line + $lines_in_cmd}]

        lappend commands [dict create \
            text $cmd_text \
            start_line $cmd_start_line \
            end_line $cmd_end_line]

        if {$debug} {
            puts "  Extracted command at line $cmd_start_line: [string range $cmd_text 0 50]..."
        }
    }

    return $commands
}

# ============================================================================
# COMMAND PARSING (Using TCL list commands)
# ============================================================================

# Parse a command into an AST node
proc ::ast::parse_command {cmd_dict depth} {
    variable debug

    set cmd_text [dict get $cmd_dict text]
    set start_line [dict get $cmd_dict start_line]
    set end_line [dict get $cmd_dict end_line]

    # Validate it's a valid TCL command
    if {[catch {llength $cmd_text} word_count]} {
        if {$debug} {
            puts "  Invalid command syntax, skipping"
        }
        return ""
    }

    if {$word_count == 0} {
        return ""
    }

    # Get command name
    set cmd_name [lindex $cmd_text 0]

    if {$debug} {
        puts "  Parsing command: $cmd_name at line $start_line (depth $depth)"
    }

    # Dispatch to specific parser
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
        default {
            # Generic command node
            return [dict create \
                type "command" \
                name $cmd_name \
                range [make_range $start_line 1 $end_line 80]]
        }
    }
}

# ============================================================================
# SPECIFIC COMMAND PARSERS
# ============================================================================

# Parse proc command (with recursive body scanning)
proc ::ast::parse_proc {cmd_text start_line end_line depth} {
    variable debug

    if {[catch {llength $cmd_text} word_count] || $word_count < 4} {
        return ""
    }

    set name [lindex $cmd_text 1]
    set params [lindex $cmd_text 2]
    set body [lindex $cmd_text 3]

    if {$debug} {
        puts "    Found proc '$name' at depth $depth"
    }

    # Parse parameters
    set param_list [list]
    if {[catch {llength $params} param_count]} {
        set param_count 0
    }

    for {set i 0} {$i < $param_count} {incr i} {
        set param [lindex $params $i]

        if {[catch {llength $param} param_len]} {
            continue
        }

        if {$param_len == 2} {
            # Parameter with default value
            lappend param_list [dict create \
                name [lindex $param 0] \
                default [lindex $param 1] \
                range [make_range $start_line 10 $start_line 20]]
        } elseif {$param_len == 1} {
            # Simple parameter
            set pdict [dict create \
                name $param \
                range [make_range $start_line 10 $start_line 20]]

            if {$param eq "args"} {
                dict set pdict is_varargs true
            }

            lappend param_list $pdict
        }
    }

    # Calculate actual end line based on body content
    set body_lines [count_lines $body]
    set actual_end_line [expr {$start_line + $body_lines + 2}]

    # Create proc node
    set proc_node [dict create \
        type "proc" \
        name $name \
        params $param_list \
        body [dict create type "body" text $body] \
        depth $depth \
        range [make_range $start_line 1 $actual_end_line 1]]

    # RECURSIVELY find nested procs in body
    set nested_nodes [find_all_nodes $body [expr {$start_line + 2}] [expr {$depth + 1}]]

    if {[llength $nested_nodes] > 0} {
        dict set proc_node nested_nodes $nested_nodes
    }

    return $proc_node
}

# Parse set command
proc ::ast::parse_set {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 2} {
        return ""
    }

    set var_name [lindex $cmd_text 1]
    set value ""
    if {$word_count >= 3} {
        set value [lindex $cmd_text 2]
    }

    return [dict create \
        type "set" \
        name $var_name \
        value $value \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse variable command
proc ::ast::parse_variable {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 2} {
        return ""
    }

    set var_name [lindex $cmd_text 1]
    set value ""
    if {$word_count >= 3} {
        set value [lindex $cmd_text 2]
    }

    return [dict create \
        type "variable" \
        name $var_name \
        value $value \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse global command
proc ::ast::parse_global {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 2} {
        return ""
    }

    set vars [lrange $cmd_text 1 end]

    return [dict create \
        type "global" \
        vars $vars \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse upvar command
proc ::ast::parse_upvar {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 3} {
        return ""
    }

    set args [lrange $cmd_text 1 end]
    set source ""
    set target ""

    if {[llength $args] == 2} {
        set source [lindex $args 0]
        set target [lindex $args 1]
    } elseif {[llength $args] >= 3} {
        set source [lindex $args 1]
        set target [lindex $args 2]
    }

    return [dict create \
        type "upvar" \
        source $source \
        target $target \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse namespace command
proc ::ast::parse_namespace {cmd_text start_line end_line depth} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 2} {
        return ""
    }

    set subcommand [lindex $cmd_text 1]

    if {$subcommand eq "eval"} {
        if {$word_count < 3} {
            return ""
        }

        set name [lindex $cmd_text 2]
        set body ""
        if {$word_count >= 4} {
            set body [lindex $cmd_text 3]
        }

        set body_lines [count_lines $body]
        set actual_end_line [expr {$start_line + $body_lines + 1}]

        set ns_node [dict create \
            type "namespace" \
            subtype "eval" \
            name $name \
            body $body \
            range [make_range $start_line 1 $actual_end_line 1]]

        # Recursively parse namespace body
        set nested_nodes [find_all_nodes $body [expr {$start_line + 1}] [expr {$depth + 1}]]
        if {[llength $nested_nodes] > 0} {
            dict set ns_node nested_nodes $nested_nodes
        }

        return $ns_node

    } elseif {$subcommand eq "import"} {
        set patterns [lrange $cmd_text 2 end]
        return [dict create \
            type "namespace_import" \
            patterns $patterns \
            range [make_range $start_line 1 $end_line 50]]
    }

    return [dict create \
        type "namespace" \
        subtype $subcommand \
        args [lrange $cmd_text 2 end] \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse package command
proc ::ast::parse_package {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 3} {
        return ""
    }

    set subcommand [lindex $cmd_text 1]
    set package_name [lindex $cmd_text 2]
    set version ""
    if {$word_count >= 4} {
        set version [lindex $cmd_text 3]
    }

    if {$subcommand eq "require"} {
        return [dict create \
            type "package_require" \
            package_name $package_name \
            version $version \
            range [make_range $start_line 1 $end_line 50]]
    } elseif {$subcommand eq "provide"} {
        return [dict create \
            type "package_provide" \
            package_name $package_name \
            version $version \
            range [make_range $start_line 1 $end_line 50]]
    }

    return ""
}

# Parse if command
proc ::ast::parse_if {cmd_text start_line end_line depth} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 3} {
        return ""
    }

    return [dict create \
        type "if" \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse while command
proc ::ast::parse_while {cmd_text start_line end_line depth} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 3} {
        return ""
    }

    return [dict create \
        type "while" \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse for command
proc ::ast::parse_for {cmd_text start_line end_line depth} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 5} {
        return ""
    }

    return [dict create \
        type "for" \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse foreach command
proc ::ast::parse_foreach {cmd_text start_line end_line depth} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 4} {
        return ""
    }

    return [dict create \
        type "foreach" \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse switch command
proc ::ast::parse_switch {cmd_text start_line end_line depth} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 3} {
        return ""
    }

    return [dict create \
        type "switch" \
        cases [list] \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse expr command
proc ::ast::parse_expr {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 2} {
        return ""
    }

    set expression [lindex $cmd_text 1]

    return [dict create \
        type "expr" \
        expression $expression \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse list command
proc ::ast::parse_list {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 2} {
        return ""
    }

    set elements [lrange $cmd_text 1 end]

    return [dict create \
        type "list" \
        elements $elements \
        range [make_range $start_line 1 $end_line 50]]
}

# Parse lappend command
proc ::ast::parse_lappend {cmd_text start_line end_line} {
    if {[catch {llength $cmd_text} word_count] || $word_count < 3} {
        return ""
    }

    set var_name [lindex $cmd_text 1]
    set value [lindex $cmd_text 2]

    return [dict create \
        type "lappend" \
        name $var_name \
        value $value \
        range [make_range $start_line 1 $end_line 50]]
}

# ============================================================================
# RECURSIVE NODE FINDER (Main algorithm)
# ============================================================================

# Find all nodes recursively (procs can be nested!)
proc ::ast::find_all_nodes {code start_line {depth 0}} {
    variable debug

    set all_nodes [list]

    if {$debug} {
        puts "Scanning at depth $depth, starting line $start_line"
    }

    # Extract commands from this code block
    set commands [extract_commands $code $start_line]

    if {$debug} {
        puts "  Found [llength $commands] commands"
    }

    # Parse each command
    foreach cmd_dict $commands {
        set node [parse_command $cmd_dict $depth]

        if {$node ne ""} {
            lappend all_nodes $node
        }
    }

    return $all_nodes
}

# ============================================================================
# JSON CONVERSION
# ============================================================================

proc ::ast::dict_to_json {d indent_level} {
    set indent [string repeat "  " $indent_level]
    set next_indent [string repeat "  " [expr {$indent_level + 1}]]

    set result "\{"
    set first 1

    dict for {key value} $d {
        if {!$first} {
            append result ","
        }
        set first 0

        append result "\n${next_indent}\"$key\": "

        # Check if value is a list
        if {[string is list $value] && [llength $value] > 0} {
            set first_elem [lindex $value 0]
            # Check if it's a list of dicts
            if {[catch {dict size $first_elem}] == 0 && [dict size $first_elem] > 0} {
                # List of dicts
                append result "\["
                set first_item 1
                foreach item $value {
                    if {!$first_item} {
                        append result ","
                    }
                    set first_item 0
                    append result "\n$next_indent  "
                    append result [dict_to_json $item [expr {$indent_level + 2}]]
                }
                append result "\n${next_indent}\]"
            } else {
                # Regular list
                append result "\["
                set first_item 1
                foreach item $value {
                    if {!$first_item} {
                        append result ", "
                    }
                    set first_item 0
                    append result "\"[escape_json $item]\""
                }
                append result "\]"
            }
        } elseif {[catch {dict size $value}] == 0 && [dict size $value] > 0} {
            # Nested dict
            append result [dict_to_json $value [expr {$indent_level + 1}]]
        } elseif {[string is integer -strict $value] || [string is double -strict $value]} {
            # Number
            append result $value
        } elseif {$value eq "true" || $value eq "false"} {
            # Boolean
            append result $value
        } else {
            # String
            append result "\"[escape_json $value]\""
        }
    }

    append result "\n${indent}\}"
    return $result
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

# ============================================================================
# MAIN BUILD FUNCTION
# ============================================================================

proc ::ast::build {code {filepath "<string>"}} {
    variable current_file
    variable debug

    set current_file $filepath

    if {$debug} {
        puts "\n=== Building AST for $filepath ==="
        puts "Code length: [string length $code] chars"
    }

    # Check if code is complete
    if {![info complete $code]} {
        if {$debug} {
            puts "ERROR: Incomplete TCL code"
        }
        return [dict create \
            type "root" \
            filepath $filepath \
            errors [list [dict create \
                type "error" \
                message "missing close-brace" \
                range [make_range 1 1 1 1] \
                error_type "incomplete" \
                suggestion "Check for missing closing brace \}"]] \
            had_error true \
            children [list] \
            comments [list]]
    }

    # Build line mapping
    build_line_map $code

    # Extract comments
    set comments [extract_comments $code]

    if {$debug} {
        puts "Found [llength $comments] comments"
    }

    # Find all nodes (recursively)
    set nodes [find_all_nodes $code 1 0]

    if {$debug} {
        puts "Found [llength $nodes] total nodes"
        puts "=== AST Building Complete ===\n"
    }

    # Flatten nested nodes into children list
    set all_children [list]
    foreach node $nodes {
        lappend all_children $node

        # If node has nested_nodes, add them to children too
        if {[dict exists $node nested_nodes]} {
            set nested [dict get $node nested_nodes]
            lappend all_children {*}$nested
        }
    }

    # Build root AST
    return [dict create \
        type "root" \
        filepath $filepath \
        comments $comments \
        children $nodes \
        had_error false \
        errors [list]]
}
