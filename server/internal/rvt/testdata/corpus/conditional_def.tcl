# A proc defined conditionally inside an if-block (idiomatic "define if absent").
# Before the def-walker recursed control-flow bodies, this proc was never indexed,
# so goto-definition from a .rvt call landed nowhere.
if {![llength [info commands page_header]]} {
    proc page_header {title} { return "<h1>$title</h1>" }
}
