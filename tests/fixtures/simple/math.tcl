# tests/fixtures/simple/math.tcl
# Simple math procedures for testing

proc add {a b} {
    return [expr {$a + $b}]
}

proc subtract {a b} {
    return [expr {$a - $b}]
}
