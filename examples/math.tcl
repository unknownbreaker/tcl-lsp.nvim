namespace eval ::math {
    variable pi 3.14159

    proc square {x} {
        return [expr {$x * $x}]
    }
}
