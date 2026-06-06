# Namespace name resolution: how UNQUALIFIED and QUALIFIED names resolve,
# and how command resolution differs from variable resolution.
# Verified behavior printed per section; run on 8.6 and 9.0.

proc section {name} { puts "\n=== $name ===" }
proc try1 {label script} {
    if {[catch {uplevel 1 $script} res]} {
        puts "$label -> ERROR: $res"
    } else {
        puts "$label -> $res"
    }
}

# ---------------------------------------------------------------------------
section "A. Unqualified COMMAND resolution = current ns, then global :: only"
# Does an unqualified command in ::a::b find ::a::cmd (an ancestor)?  Expect NO.
namespace eval ::a {
    proc ancestor_cmd {} { return "::a::ancestor_cmd" }
    namespace eval b {
        proc call_unqualified {} {
            # ancestor_cmd is in parent ::a, NOT in ::a::b and NOT in ::.
            try1 "unqualified ancestor_cmd from ::a::b" { ancestor_cmd }
        }
    }
}
::a::b::call_unqualified

# A global command IS found as fallback:
proc global_cmd {} { return "::global_cmd" }
namespace eval ::a::b {
    proc call_global {} {
        try1 "unqualified global_cmd from ::a::b" { global_cmd }
    }
}
::a::b::call_global

# ---------------------------------------------------------------------------
section "B. `namespace path` extends COMMAND search (ordered)"
namespace eval ::lib { proc helper {} { return "::lib::helper" } }
namespace eval ::user {
    namespace path ::lib
    proc use_helper {} {
        try1 "helper via namespace path ::lib" { helper }
    }
}
::user::use_helper

# ---------------------------------------------------------------------------
section "C. Relative vs absolute qualified COMMAND names"
namespace eval ::x {
    proc target {} { return "::x::target" }
    namespace eval y {
        proc rel {} {
            # relative name resolves against current ns ::x::y first
            try1 "relative   y2::target (needs ::x::y::y2)" { y2::target }
            try1 "absolute   ::x::target" { ::x::target }
        }
        namespace eval y2 { proc target {} { return "::x::y::y2::target" } }
    }
}
::x::y::rel

# ---------------------------------------------------------------------------
section "D. namespace export / import creates command aliases"
namespace eval ::provider {
    namespace export pub
    proc pub {} { return "::provider::pub" }
    proc priv {} { return "::provider::priv" }
}
namespace eval ::consumer {
    namespace import ::provider::pub
    proc use {} {
        try1 "imported pub" { pub }
    }
}
::consumer::use
try1 "what is imported name" { namespace eval ::consumer {namespace which -command pub} }
try1 "import of non-exported priv" { namespace eval ::consumer {namespace import ::provider::priv} }

# ---------------------------------------------------------------------------
section "E. Does `namespace path` affect VARIABLE resolution? (expect NO)"
namespace eval ::vlib { variable shared "::vlib::shared" }
namespace eval ::vuser {
    namespace path ::vlib
    proc read_shared {} {
        try1 "unqualified shared via path (proc)" { set shared }
        try1 "qualified ::vlib::shared"           { set ::vlib::shared }
    }
}
::vuser::read_shared

# ---------------------------------------------------------------------------
section "F. namespace which as the resolution oracle"
namespace eval ::oracle {
    proc cmd {} {}
    variable var 1
    proc probe {} {
        puts "which -command cmd : [namespace which -command cmd]"
        puts "which -variable var: [namespace which -variable var]"
        puts "which -command set : [namespace which -command set]"
    }
}
::oracle::probe

# ---------------------------------------------------------------------------
section "G. Commands resolve at CALL time (forward references work)"
namespace eval ::fwd {
    proc caller {} { try1 "calls not-yet-defined callee" { callee } }
    proc callee {} { return "::fwd::callee (defined after caller)" }
}
::fwd::caller
