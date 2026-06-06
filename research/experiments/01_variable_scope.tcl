# Variable scope & resolution experiments.
# Each section prints a labeled result so we can verify TCL's actual behavior
# rather than asserting it from memory.

proc section {name} { puts "\n=== $name ===" }

# ---------------------------------------------------------------------------
section "1. Locals are frame-local; NOT dynamically scoped"
# If TCL were dynamically scoped, callee would see caller's `x`. It does not.
proc outer {} {
    set x "outer-local"
    inner
}
proc inner {} {
    if {[info exists x]} {
        puts "inner sees x = $x  (DYNAMIC scope)"
    } else {
        puts "inner does NOT see caller's x  (frame-local)"
    }
}
outer

# ---------------------------------------------------------------------------
section "2. `global` links to the :: (global) namespace"
set g "value-in-global"
proc reads_global {} {
    global g
    puts "via global: g = $g"
}
reads_global

# ---------------------------------------------------------------------------
section "3. `variable` links to a NAMESPACE variable"
namespace eval ::myns {
    variable nsvar "value-in-myns"
    proc reader {} {
        variable nsvar
        puts "via variable: nsvar = $nsvar"
    }
}
::myns::reader

# ---------------------------------------------------------------------------
section "4. `upvar` links a local name to a variable in another frame"
proc make_counter {} {
    set count 0
    bump count
    bump count
    puts "after two bumps, count = $count"
}
proc bump {varname} {
    upvar 1 $varname c
    incr c
}
make_counter

# ---------------------------------------------------------------------------
section "5. GOTCHA: inside a proc, unqualified var = LOCAL only (no ns fallback)"
namespace eval ::a {
    variable v "a::v"
    namespace eval b {
        variable v "a::b::v"
        proc show_broken {} {
            # `v` is NOT auto-linked to the enclosing namespace variable.
            if {[catch {set v} err]} {
                puts "unqualified `set v` FAILS: $err"
            } else {
                puts "unqualified `set v` = $v"
            }
        }
        proc show_declared {} {
            variable v   ;# explicit link to ::a::b::v
            puts "after `variable v`: $v"
        }
        proc show_qualified {} {
            puts "fully-qualified \$::a::b::v = $::a::b::v"
            puts "fully-qualified \$::a::v     = $::a::v"
        }
    }
}
::a::b::show_broken
::a::b::show_declared
::a::b::show_qualified

# ---------------------------------------------------------------------------
section "6. Nested proc definitions do NOT create lexical nesting"
# Defining a proc inside a proc just defines a global/ns-level command when
# it runs; the inner proc canNOT see the outer proc's locals.
proc defines_inner {} {
    set secret "outer-secret"
    proc dynamically_defined {} {
        if {[info exists secret]} {
            puts "inner sees secret"
        } else {
            puts "inner does NOT see outer's secret (no lexical closure)"
        }
    }
    dynamically_defined
}
defines_inner

# ---------------------------------------------------------------------------
section "7. `set` with a qualified name targets that namespace"
namespace eval ::config {}
set ::config::timeout 30
puts "::config::timeout = $::config::timeout"
namespace eval ::config {
    proc get_timeout {} {
        variable timeout
        return $timeout
    }
}
puts "read back via variable: [::config::get_timeout]"

# ---------------------------------------------------------------------------
section "8. info commands for introspection (resolver-relevant)"
namespace eval ::introspect {
    variable demo 1
    proc p {} { return }
}
puts "namespace exists ::introspect : [namespace exists ::introspect]"
puts "vars in ::introspect       : [info vars ::introspect::*]"
puts "procs in ::introspect      : [info procs ::introspect::*]"
puts "namespace which -variable  : [namespace eval ::introspect {namespace which -variable demo}]"
puts "namespace which -command   : [namespace eval ::introspect {namespace which -command p}]"
