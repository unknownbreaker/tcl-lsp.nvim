# Driver: run with `tclsh main.tcl`. Demonstrates source / multi-file behavior.
proc section {name} { puts "\n=== $name ===" }
proc try1 {label script} {
    if {[catch {uplevel 1 $script} res]} {
        puts "$label -> ERROR: $res"
    } else { puts "$label -> $res" }
}

set here [file dirname [file normalize [info script]]]
puts "info script    : [info script]"
puts "computed \$here : $here"

# ---------------------------------------------------------------------------
section "F. Call-time: using a symbol BEFORE its file is sourced fails"
try1 "::math::square 5 before source" { ::math::square 5 }

# ---------------------------------------------------------------------------
section "A. source makes a file's definitions available"
source [file join $here lib_math.tcl]
try1 "::math::square 5 after source" { ::math::square 5 }
try1 "::math::pi value" { set ::math::pi }

# ---------------------------------------------------------------------------
section "B. A namespace SPANS files (not file-scoped)"
source [file join $here app_a.tcl]
source [file join $here app_b.tcl]
try1 "::app::hello (from app_a)" { ::app::hello }
try1 "::app::world (from app_b, reads app_a's var)" { ::app::world }
try1 "info procs ::app::* (both files contribute)" { lsort [info procs ::app::*] }
try1 "::app::version (defined in app_a)" { set ::app::version }

# ---------------------------------------------------------------------------
section "C. source path resolution"
# `source` takes a path; relative paths are relative to the process CWD,
# NOT the sourcing file. The robust idiom is [file dirname [info script]].
puts "pwd (process cwd): [pwd]"
puts "note: this driver used \[file dirname \[info script\]\] to locate siblings"
