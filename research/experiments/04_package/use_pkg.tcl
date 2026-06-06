# Driver: run with `tclsh use_pkg.tcl`. Demonstrates package require resolution.
proc try1 {label script} {
    if {[catch {uplevel 1 $script} res]} {
        puts "$label -> ERROR: $res"
    } else { puts "$label -> $res" }
}

set here [file dirname [file normalize [info script]]]
# auto_path tells the package machinery where to find pkgIndex.tcl files.
lappend ::auto_path $here

try1 "package require greeter" { package require greeter }
try1 "call ::greeter::hi"      { ::greeter::hi }
try1 "package versions greeter" { package versions greeter }
try1 "package present greeter"  { package present greeter }
