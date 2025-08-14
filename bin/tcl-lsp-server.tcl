#!/usr/bin/env tclsh
# tcl-lsp-server.tcl - Portable TCL Language Server

# Portable tcllib detection that works across different systems
proc find_and_load_json {} {
    # First, try the standard package require
    if {![catch {package require json}]} {
        return 1
    }

    # If that fails, try to locate tcllib in common locations
    set tcllib_paths {}

    # Get TCL installation paths
    foreach path $::auto_path {
        lappend tcllib_paths $path
        # Also check for tcllib subdirectories
        foreach subdir [glob -nocomplain -type d "$path/tcllib*"] {
            lappend tcllib_paths $subdir
        }
    }

    # Common system locations for tcllib
    set common_paths {
        /usr/lib/tcllib*
        /usr/local/lib/tcllib*
        /opt/local/lib/tcllib*
        /usr/share/tcllib*
        /usr/local/share/tcllib*
    }

    # Try to find tcllib in common locations
    foreach pattern $common_paths {
        foreach path [glob -nocomplain $pattern] {
            if {[file isdirectory $path]} {
                lappend tcllib_paths $path
            }
        }
    }

    # On macOS, also check common Homebrew/MacPorts locations
    if {$::tcl_platform(os) eq "Darwin"} {
        set macos_paths {
            /opt/homebrew/lib/tcllib*
            /usr/local/lib/tcllib*
            /opt/local/lib/tcllib*
        }

        foreach pattern $macos_paths {
            foreach path [glob -nocomplain $pattern] {
                if {[file isdirectory $path]} {
                    lappend tcllib_paths $path
                }
            }
        }
    }

    # Try each potential tcllib path
    foreach path $tcllib_paths {
        if {[file isdirectory $path]} {
            lappend ::auto_path $path

            # Try to load json package
            if {![catch {package require json}]} {
                return 1
            }
        }
    }

    # Last resort: try to find json.tcl directly
    set json_patterns {
        /usr/*/tcllib*/json/json.tcl
        /opt/*/tcllib*/json/json.tcl
        /usr/local/*/tcllib*/json/json.tcl
    }

    foreach pattern $json_patterns {
        foreach json_file [glob -nocomplain $pattern] {
            if {[file readable $json_file]} {
                # Get the parent directory and add to auto_path
                set json_dir [file dirname [file dirname $json_file]]
                lappend ::auto_path $json_dir

                if {![catch {package require json}]} {
                    return 1
                }
            }
        }
    }

    return 0
}

# Try to load the JSON package
if {![find_and_load_json]} {
    puts stderr "Error: TCL JSON package not found."
    puts stderr ""
    puts stderr "Please install tcllib for your system:"
    puts stderr "  Ubuntu/Debian: sudo apt-get install tcllib"
    puts stderr "  CentOS/RHEL:   sudo yum install tcllib"
    puts stderr "  Fedora:        sudo dnf install tcllib"
    puts stderr "  macOS:         port install tcllib (MacPorts)"
    puts stderr "  Manual:        Download from https://core.tcl-lang.org/tcllib/"
    puts stderr ""
    puts stderr "Or set TCLLIBPATH environment variable to tcllib location."
    exit 1
}

# If we get here, JSON package is loaded successfully
# Rest of the LSP server code goes here...

puts stderr "TCL LSP Server starting..."
puts stderr "JSON package loaded successfully"

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

# Initialize the server
proc handle_initialize {params} {
    global g_workspace_root g_client_capabilities

    if {[dict exists $params rootUri]} {
        set g_workspace_root [dict get $params rootUri]
        # Convert file:// URI to local path
        regsub {^file://} $g_workspace_root {} g_workspace_root
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
            documentSymbolProvider true \
        ] \
        serverInfo [dict create \
            name "tcl-lsp-server" \
            version "1.0.0" \
        ] \
    ]
}

# Basic hover handler
proc handle_hover {params} {
    # Simple hover response for testing
    return [dict create \
        contents [dict create \
            kind "markdown" \
            value "**TCL LSP Server**\n\nServer is running and responding to requests." \
        ] \
    ]
}

# Main message loop
proc main {} {
    puts stderr "Entering main message loop..."

    while {1} {
        if {[catch {read_lsp_message} request]} {
            puts stderr "Connection closed or error reading message"
            break
        }

        set method [dict get $request method]
        set params [dict exists $request params] ? [dict get $request params] : [dict create]
        set id [dict exists $request id] ? [dict get $request id] : ""

        puts stderr "Received method: $method"

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
                "initialized" {
                    # Initialization complete notification
                    puts stderr "Server initialized"
                }
                "shutdown" {
                    send_lsp_response $id null
                }
                "exit" {
                    puts stderr "Server shutting down"
                    exit 0
                }
                default {
                    if {$id ne ""} {
                        send_lsp_error $id -32601 "Method not found: $method"
                    }
                }
            }
        } error]} {
            puts stderr "Error handling $method: $error"
            if {$id ne ""} {
                send_lsp_error $id -32603 "Internal error: $error"
            }
        }
    }
}

# Start the server
main
