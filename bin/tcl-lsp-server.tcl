#!/usr/bin/env tclsh
# tcl-lsp-server.tcl - A proper LSP server implemented in TCL
# This leverages TCL's introspection capabilities for real language server features

package require json

# Global state
array set g_symbols {}
array set g_files {}
set g_workspace_root ""
set g_client_capabilities {}

# LSP protocol utilities
proc read_lsp_message {} {
    set headers {}

    # Read headers
    while {[gets stdin line] >= 0} {
        if {$line eq ""} break
        if {[regexp {^([^:]+):\s*(.+)$} $line -> key value]} {
            set headers([string tolower $key]) $value
        }
    }

    if {![info exists headers(content-length)]} {
        error "No Content-Length header found"
    }

    set content_length $headers(content-length)

    # Read content
    set content [read stdin $content_length]

    return [json::json2dict $content]
}

proc send_lsp_response {id result} {
    set response [json::dict2json [dict create \
        jsonrpc "2.0" \
        id $id \
        result $result]]

    set content_length [string length $response]
    puts "Content-Length: $content_length\r"
    puts "\r"
    puts -nonewline $response
    flush stdout
}

proc send_lsp_notification {method params} {
    set notification [json::dict2json [dict create \
        jsonrpc "2.0" \
        method $method \
        params $params]]

    set content_length [string length $notification]
    puts "Content-Length: $content_length\r"
    puts "\r"
    puts -nonewline $notification
    flush stdout
}

proc send_lsp_error {id code message} {
    set error_response [json::dict2json [dict create \
        jsonrpc "2.0" \
        id $id \
        error [dict create code $code message $message]]]

    set content_length [string length $error_response]
    puts "Content-Length: $content_length\r"
    puts "\r"
    puts -nonewline $error_response
    flush stdout
}

# TCL introspection utilities
proc parse_tcl_file {filepath} {
    global g_symbols

    set symbols [dict create procedures {} variables {} namespaces {}]

    if {![file exists $filepath]} {
        return $symbols
    }

    # Create a safe interpreter for parsing
    set interp [interp create -safe]

    # Override commands in safe interpreter to capture definitions
    $interp eval {
        set ::parsed_symbols [dict create procedures {} variables {} namespaces {}]

        # Capture procedure definitions
        rename proc _original_proc
        proc proc {name args body} {
            set line_info [dict create name $name args $args line [info frame]]
            dict lappend ::parsed_symbols procedures $line_info
            # Don't actually define the procedure in safe interpreter
        }

        # Capture variable assignments
        rename set _original_set
        proc set {varname args} {
            if {[llength $args] > 0} {
                # This is an assignment
                set var_info [dict create name $varname line [info frame]]
                dict lappend ::parsed_symbols variables $var_info
            }
            # Return empty for safety
            return ""
        }

        # Capture namespace definitions
        rename namespace _original_namespace
        proc namespace {subcommand args} {
            if {$subcommand eq "eval"} {
                set ns_name [lindex $args 0]
                set ns_info [dict create name $ns_name line [info frame]]
                dict lappend ::parsed_symbols namespaces $ns_info
            }
        }

        # Override other commands that might cause issues
        proc source {args} { return "" }
        proc package {args} { return "" }
        proc load {args} { return "" }
        proc exit {args} { return "" }
        proc puts {args} { return "" }
    }

    # Try to source the file in the safe interpreter
    if {[catch {
        $interp eval [list source $filepath]
    } error]} {
        # If sourcing fails, try line-by-line parsing
        if {[catch {open $filepath r} fp]} {
            interp delete $interp
            return $symbols
        }

        set line_num 0
        while {[gets $fp line] >= 0} {
            incr line_num
            set trimmed [string trim $line]

            # Skip comments and empty lines
            if {$trimmed eq "" || [string index $trimmed 0] eq "#"} continue

            # Simple regex-based parsing as fallback
            if {[regexp {^proc\s+(\w+)} $trimmed -> proc_name]} {
                set proc_info [dict create name $proc_name line $line_num]
                dict lappend symbols procedures $proc_info
            } elseif {[regexp {^set\s+(\w+)} $trimmed -> var_name]} {
                set var_info [dict create name $var_name line $line_num]
                dict lappend symbols variables $var_info
            } elseif {[regexp {^namespace\s+eval\s+(\w+)} $trimmed -> ns_name]} {
                set ns_info [dict create name $ns_name line $line_num]
                dict lappend symbols namespaces $ns_info
            }
        }
        close $fp
    } else {
        # Get parsed symbols from safe interpreter
        set symbols [$interp eval {set ::parsed_symbols}]
    }

    interp delete $interp

    # Cache symbols for this file
    set g_symbols($filepath) $symbols

    return $symbols
}

# Enhanced TCL introspection using info commands
proc get_tcl_command_info {command} {
    # Use TCL's built-in info commands for comprehensive help
    set info_dict [dict create]

    # Check if it's a built-in command
    if {[info commands $command] ne ""} {
        dict set info_dict exists true
        dict set info_dict type "command"

        # Get command signature if available
        if {![catch {info args $command} args]} {
            dict set info_dict args $args
        }

        # Try to get help text (this would be enhanced with a help database)
        dict set info_dict help [get_command_help $command]
    } else {
        dict set info_dict exists false
    }

    return $info_dict
}

proc get_command_help {command} {
    # Built-in TCL command help database
    set help_db [dict create \
        puts "puts ?-nonewline? ?channelId? string\nWrite string to output channel" \
        set "set varName ?value?\nRead or write variable" \
        proc "proc name args body\nDefine a new procedure" \
        if "if expr1 ?then? body1 ?elseif expr2 ?then? body2 ...? ?else? ?bodyN?\nConditional execution" \
        for "for start test next body\nLoop with initialization, test, and increment" \
        while "while test body\nLoop while test condition is true" \
        foreach "foreach varname list body\nIterate over list elements" \
        string "string option arg ?arg ...?\nString manipulation commands" \
        list "list ?arg arg ...?\nCreate a list from arguments" \
        dict "dict option ?arg arg ...?\nDictionary manipulation commands" \
        array "array option arrayName ?arg ...?\nArray manipulation commands" \
        file "file option name ?arg ...?\nFile system operations" \
        glob "glob ?switches? pattern ?pattern ...?\nReturn files matching patterns" \
        regexp "regexp ?switches? exp string ?matchVar? ?subMatchVar ...?\nMatch regular expression" \
        regsub "regsub ?switches? exp string subSpec ?varName?\nReplace using regular expression" \
    ]

    if {[dict exists $help_db $command]} {
        return [dict get $help_db $command]
    } else {
        return "No help available for '$command'"
    }
}

# LSP method handlers
proc handle_initialize {params} {
    global g_workspace_root g_client_capabilities

    if {[dict exists $params rootUri]} {
        set g_workspace_root [dict get $params rootUri]
        # Convert file:// URI to local path
        regsub {^file://} $g_workspace_root {} g_workspace_root
    } elseif {[dict exists $params rootPath]} {
        set g_workspace_root [dict get $params rootPath]
    }

    if {[dict exists $params capabilities]} {
        set g_client_capabilities [dict get $params capabilities]
    }

    # Return server capabilities
    return [dict create \
        capabilities [dict create \
            textDocumentSync 1 \
            hoverProvider true \
            definitionProvider true \
            referencesProvider true \
            documentSymbolProvider true \
            workspaceSymbolProvider true \
            completionProvider [dict create triggerCharacters {$ \[ \{} \
        ] \
        serverInfo [dict create \
            name "tcl-lsp-server" \
            version "1.0.0" \
        ] \
    ]
}

proc handle_hover {params} {
    set doc_uri [dict get $params textDocument uri]
    set position [dict get $params position]
    set line [dict get $position line]
    set character [dict get $position character]

    # Convert URI to file path
    regsub {^file://} $doc_uri {} filepath

    # Get the word at cursor position
    set word [get_word_at_position $filepath $line $character]
    if {$word eq ""} {
        return null
    }

    # Get command information using TCL introspection
    set cmd_info [get_tcl_command_info $word]

    if {[dict get $cmd_info exists]} {
        set help_text [dict get $cmd_info help]
        return [dict create \
            contents [dict create \
                kind "markdown" \
                value "**TCL Command:** `$word`\n\n$help_text" \
            ] \
        ]
    }

    # Check if it's a user-defined symbol
    if {[info exists ::g_symbols($filepath)]} {
        set symbols $::g_symbols($filepath)
        foreach proc_info [dict get $symbols procedures] {
            if {[dict get $proc_info name] eq $word} {
                return [dict create \
                    contents [dict create \
                        kind "markdown" \
                        value "**Procedure:** `$word`\n\nDefined at line [dict get $proc_info line]" \
                    ] \
                ]
            }
        }
    }

    return null
}

proc handle_definition {params} {
    set doc_uri [dict get $params textDocument uri]
    set position [dict get $params position]
    set line [dict get $position line]
    set character [dict get $position character]

    # Convert URI to file path
    regsub {^file://} $doc_uri {} filepath

    # Get the word at cursor position
    set word [get_word_at_position $filepath $line $character]
    if {$word eq ""} {
        return null
    }

    # Search for definition in parsed symbols
    if {[info exists ::g_symbols($filepath)]} {
        set symbols $::g_symbols($filepath)

        # Check procedures first
        foreach proc_info [dict get $symbols procedures] {
            if {[dict get $proc_info name] eq $word} {
                set def_line [dict get $proc_info line]
                return [dict create \
                    uri $doc_uri \
                    range [dict create \
                        start [dict create line [expr {$def_line - 1}] character 0] \
                        end [dict create line [expr {$def_line - 1}] character 0] \
                    ] \
                ]
            }
        }

        # Check variables
        foreach var_info [dict get $symbols variables] {
            if {[dict get $var_info name] eq $word} {
                set def_line [dict get $var_info line]
                return [dict create \
                    uri $doc_uri \
                    range [dict create \
                        start [dict create line [expr {$def_line - 1}] character 0] \
                        end [dict create line [expr {$def_line - 1}] character 0] \
                    ] \
                ]
            }
        }
    }

    return null
}

proc handle_document_symbols {params} {
    set doc_uri [dict get $params textDocument uri]
    regsub {^file://} $doc_uri {} filepath

    # Parse file and get symbols
    set symbols [parse_tcl_file $filepath]
    set result {}

    # Convert procedures to LSP symbols
    foreach proc_info [dict get $symbols procedures] {
        set name [dict get $proc_info name]
        set line [dict get $proc_info line]
        lappend result [dict create \
            name $name \
            kind 12 \
            range [dict create \
                start [dict create line [expr {$line - 1}] character 0] \
                end [dict create line [expr {$line - 1}] character [string length $name]] \
            ] \
            selectionRange [dict create \
                start [dict create line [expr {$line - 1}] character 0] \
                end [dict create line [expr {$line - 1}] character [string length $name]] \
            ] \
        ]
    }

    # Convert variables to LSP symbols
    foreach var_info [dict get $symbols variables] {
        set name [dict get $var_info name]
        set line [dict get $var_info line]
        lappend result [dict create \
            name $name \
            kind 13 \
            range [dict create \
                start [dict create line [expr {$line - 1}] character 0] \
                end [dict create line [expr {$line - 1}] character [string length $name]] \
            ] \
            selectionRange [dict create \
                start [dict create line [expr {$line - 1}] character 0] \
                end [dict create line [expr {$line - 1}] character [string length $name]] \
            ] \
        ]
    }

    return $result
}

proc handle_did_open {params} {
    set doc [dict get $params textDocument]
    set uri [dict get $doc uri]
    regsub {^file://} $uri {} filepath

    # Parse the file when it's opened
    parse_tcl_file $filepath

    # No response needed for notifications
}

proc handle_did_change {params} {
    set doc [dict get $params textDocument]
    set uri [dict get $doc uri]
    regsub {^file://} $uri {} filepath

    # Re-parse the file when it changes
    parse_tcl_file $filepath

    # No response needed for notifications
}

# Utility functions
proc get_word_at_position {filepath line character} {
    if {![file exists $filepath]} {
        return ""
    }

    set fp [open $filepath r]
    set lines [split [read $fp] \n]
    close $fp

    if {$line >= [llength $lines]} {
        return ""
    }

    set line_content [lindex $lines $line]
    if {$character >= [string length $line_content]} {
        return ""
    }

    # Find word boundaries
    set start $character
    set end $character

    # Go backwards to find start
    while {$start > 0} {
        set char [string index $line_content [expr {$start - 1}]]
        if {![string match {[a-zA-Z0-9_:]} $char]} {
            break
        }
        incr start -1
    }

    # Go forwards to find end
    while {$end < [string length $line_content]} {
        set char [string index $line_content $end]
        if {![string match {[a-zA-Z0-9_:]} $char]} {
            break
        }
        incr end
    }

    if {$start < $end} {
        return [string range $line_content $start [expr {$end - 1}]]
    }

    return ""
}

# Main LSP message loop
proc main {} {
    while {1} {
        if {[catch {read_lsp_message} request]} {
            # Connection closed or error
            break
        }

        set method [dict get $request method]
        set params [dict exists $request params] ? [dict get $request params] : [dict create]
        set id [dict exists $request id] ? [dict get $request id] : ""

        if {[catch {
            switch $method {
                "initialize" {
                    set result [handle_initialize $params]
                    send_lsp_response $id $result
                }
                "textDocument/hover" {
                    set result [handle_hover $params]
                    send_lsp_response $id $result
                }
                "textDocument/definition" {
                    set result [handle_definition $params]
                    send_lsp_response $id $result
                }
                "textDocument/documentSymbol" {
                    set result [handle_document_symbols $params]
                    send_lsp_response $id $result
                }
                "textDocument/didOpen" {
                    handle_did_open $params
                }
                "textDocument/didChange" {
                    handle_did_change $params
                }
                "initialized" {
                    # Initialization complete notification
                }
                "shutdown" {
                    send_lsp_response $id null
                }
                "exit" {
                    exit 0
                }
                default {
                    if {$id ne ""} {
                        send_lsp_error $id -32601 "Method not found: $method"
                    }
                }
            }
        } error]} {
            if {$id ne ""} {
                send_lsp_error $id -32603 "Internal error: $error"
            }
        }
    }
}

# Start the server
main
