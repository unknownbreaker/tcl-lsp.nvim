# Proc / command DEFINITION sites and how call sites bind to them.
# Focus: what a goto-definition resolver must treat as a "definition" of a
# command, and what complicates it.

proc section {name} { puts "\n=== $name ===" }
proc try1 {label script} {
    if {[catch {uplevel 1 $script} res]} {
        puts "$label -> ERROR: $res"
    } else {
        puts "$label -> $res"
    }
}

# ---------------------------------------------------------------------------
section "A. The `proc` NAME argument: where does the command get created?"
namespace eval ::defn {
    proc unqualified {} { return "::defn::unqualified" }   ;# -> current ns
}
namespace eval ::defn::sub {}
proc ::defn::sub::absolute {} { return "::defn::sub::absolute" } ;# absolute from anywhere
namespace eval ::defn {
    proc make_relative {} {
        # define a proc using a RELATIVE qualified name from inside ::defn
        proc child::rel {} { return "defined via relative name from ::defn" }
    }
}
try1 "unqualified -> " { ::defn::unqualified }
try1 "absolute    -> " { ::defn::sub::absolute }

# ---------------------------------------------------------------------------
section "B. Defining a proc into a NON-EXISTENT namespace"
try1 "proc ::nope::missing::p {} (parent ns absent)" {
    proc ::nope::missing::p {} { return "created" }
    ::nope::missing::p
}
try1 "did ::nope::missing namespace get created?" { namespace exists ::nope::missing }

# relative-name case from section A (needs ::defn::child to pre-exist?)
try1 "call relative-defined ::defn::child::rel" {
    namespace eval ::defn { make_relative }
    ::defn::child::rel
}

# ---------------------------------------------------------------------------
section "C. Redefinition: last definition wins; only ONE command exists"
proc redef {} { return "first" }
proc redef {} { return "second" }
try1 "redef result" { redef }
try1 "info procs redef count" { llength [info procs ::redef] }

# Conditional definition (runtime-dependent which body is active)
set pick 2
if {$pick == 1} {
    proc cond {} { return "branch-1" }
} else {
    proc cond {} { return "branch-2" }
}
try1 "conditionally-defined cond" { cond }

# ---------------------------------------------------------------------------
section "D. `rename` changes the command table"
proc original {} { return "original-body" }
rename original renamed
try1 "old name after rename" { original }
try1 "new name after rename" { renamed }
proc to_delete {} { return "x" }
rename to_delete ""
try1 "deleted via rename to empty" { to_delete }

# ---------------------------------------------------------------------------
section "E. `interp alias` creates an alias command"
proc real_target {args} { return "real_target($args)" }
interp alias {} aliased {} real_target preset
try1 "call alias" { aliased extra }
try1 "namespace which -command aliased" { namespace which -command aliased }
try1 "interp alias introspect" { interp alias {} aliased }

# ---------------------------------------------------------------------------
section "F. namespace ensemble: subcommand dispatch"
namespace eval ::ens {
    namespace export add sub
    proc add {a b} { return [expr {$a + $b}] }
    proc sub {a b} { return [expr {$a - $b}] }
    namespace ensemble create
}
try1 "ensemble subcommand: ens add 2 3" { ::ens add 2 3 }
try1 "what does `ens add` map to" { namespace ensemble configure ::ens -map }

# ---------------------------------------------------------------------------
section "G. Introspection of a command definition (goto-def targets)"
namespace eval ::introspect2 {
    proc documented {x {y 10}} { return [expr {$x + $y}] }
}
try1 "info procs"  { info procs ::introspect2::* }
try1 "info args"   { info args ::introspect2::documented }
try1 "info default" { set d {}; info default ::introspect2::documented y d; set d }
try1 "info body (len)" { string length [info body ::introspect2::documented] }
