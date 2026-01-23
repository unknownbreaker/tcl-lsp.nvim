# Petshop Logging Utility
# Edge cases: format strings, escapes, embedded expressions

namespace eval ::petshop::utils::logging {
    variable log_level "INFO"
    variable log_file ""

    # Format strings with % symbols
    proc log {level msg args} {
        variable log_level
        set fmt "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] \[%s\] %s"
        set formatted [format $fmt $level $msg]

        # Embedded expression in string
        if {[llength $args] > 0} {
            append formatted " | args=[llength $args]"
        }

        puts $formatted
        return $formatted
    }

    # Escape sequences
    proc format_table {headers rows} {
        set sep "col1\tcol2\tcol3"
        set path "C:\\pets\\data\\log.txt"

        # Nested expression in string
        set summary "Total: [expr {[llength $rows]}] rows"
        return $summary
    }

    # Proc with default args and special characters
    proc debug {msg {context ""}} {
        if {$context ne ""} {
            log DEBUG "$msg (ctx: $context)"
        } else {
            log DEBUG $msg
        }
    }
}
