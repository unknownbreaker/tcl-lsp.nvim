# Part B of namespace ::app, in a DIFFERENT file. Re-opens the same namespace.
# Demonstrates that a namespace is shared across files, not file-scoped.
namespace eval ::app {
    proc world {} {
        variable version          ;# the variable defined in app_a.tcl
        return "::app::world (sees version=$version from app_a.tcl)"
    }
}
