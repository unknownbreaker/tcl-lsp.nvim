# A library file. Defines a namespace with a variable and a proc.
namespace eval ::math {
    variable pi 3.14159
    proc square {x} { return [expr {$x * $x}] }
}
