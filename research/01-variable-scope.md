# 01 — Variable Scope & Resolution

**Evidence:** `experiments/01_variable_scope.tcl` (run with `tclsh`). All outputs
below are observed on TCL 9.0.3, not asserted.

## The core model

TCL variable resolution is **not** lexical and **not** dynamic. A variable
reference resolves by one of a small number of *explicit* mechanisms, evaluated
in the **current call frame**:

1. A **local** variable (proc parameter, or created by `set`/`foreach`/etc. in
   the same proc body).
2. A name **explicitly linked** into the frame by `global`, `variable`, or
   `upvar`.
3. A **fully-qualified** name (`$::ns::var`), which bypasses the frame entirely.

There is **no implicit fallback** from a local name to an enclosing namespace's
variable. This is the rule that makes TCL surprising.

## Findings

### F1 — Locals are frame-local; there is no dynamic scoping
A called proc cannot see its caller's locals.
```
inner does NOT see caller's x  (frame-local)
```
**Resolver implication:** a bare variable use inside a proc never binds to
anything in the caller. The search space for its definition is *this frame only*.

### F2 — `global name` links to the `::` (global) namespace variable
```
via global: g = value-in-global
```
**Resolver implication:** `global g` introduces a binding whose *definition* is
`::g` (top-level `set g ...`). goto-definition on `g` in the proc should target
the `global` declaration and/or `::g`'s assignment.

### F3 — `variable name` links to a variable in the **current namespace**
```
via variable: nsvar = value-in-myns
```
**Resolver implication:** the definition is the `variable nsvar ...` statement in
the enclosing `namespace eval`. The link is to the *current* namespace at the
point the proc was defined.

### F4 — `upvar LEVEL otherVar localName` links across frames
```
after two bumps, count = 2   ;# bump used `upvar 1 $varname c`
```
**Resolver implication (HARD CASE):** the target variable name is frequently a
*value* (`$varname`), so the binding target is **computed at runtime** and often
**statically unresolvable**. A static resolver must recognize `upvar` introduces
a local alias, but may not be able to point to the real definition. This is a
known-hard case to scope out explicitly.

### F5 — GOTCHA: inside a proc, an unqualified variable is a LOCAL only
No fallback to the enclosing namespace variable, even one defined in the same
`namespace eval`:
```
unqualified `set v` FAILS: can't read "v": no such variable
after `variable v`: a::b::v
fully-qualified $::a::b::v = a::b::v
fully-qualified $::a::v     = a::v
```
**Resolver implication:** this is the central asymmetry. For **variables**, a bare
name inside a proc does *not* resolve up the namespace tree — it is local or it is
an error. Contrast with **commands** (see 02), which *do* fall back through the
namespace path to global. The resolver must treat variable-name resolution and
command-name resolution as **different algorithms**.

### F6 — No lexical closures; nested `proc` does not capture
```
inner does NOT see outer's secret (no lexical closure)
```
A `proc` defined inside another proc body is just a command-creation statement
executed at runtime; the created command is installed in the *current namespace*
(not nested), and its body cannot see the defining proc's locals.
**Resolver implication:** proc nesting in source text carries **no** scope
meaning for variables. Do not treat textual nesting as lexical scope.

### F7 — `set ::ns::name value` writes/creates a namespace variable
```
::config::timeout = 30
read back via variable: 30
```
A qualified `set` is a definition site for a namespace variable, and later
`variable timeout` in that namespace links to the same storage.
**Resolver implication:** definition sites for a namespace variable include both
`variable name ...` **and** any qualified `set ::ns::name ...` (and qualified
writes from anywhere). goto-references must union these.

### F8 — Runtime introspection exists but is unavailable to a static LSP
```
info vars ::introspect::*    -> ::introspect::demo
info procs ::introspect::*   -> ::introspect::p
namespace which -variable demo -> ::introspect::demo
namespace which -command  p    -> ::introspect::p
```
**Resolver implication:** `namespace which` is exactly the resolution oracle we
must replicate statically. It's a useful **test fixture** (compare our resolver's
answer to `namespace which`'s answer) but cannot be used at LSP runtime (no eval
of user code).

## Definition sites for a variable (summary for the resolver)

A variable symbol's **definition** is one of:
- proc parameter,
- `set name ...` (first/any assignment) within the resolving frame,
- `global name` (→ `::name`),
- `variable name ...` (→ `currentNs::name`),
- `upvar ... name` (alias; target may be dynamic),
- qualified `set ::ns::name ...` anywhere (for namespace vars).

## Open questions raised

- **OQ1:** How should goto-definition behave for `upvar`/`uplevel` aliases where
  the target name is a runtime value? (Likely: resolve to the `upvar` site; mark
  the ultimate target as best-effort.)
- **OQ2:** `array` variables and `dict` — do element accesses (`$a(key)`) change
  anything for resolution? (Whole-array is the variable; needs an experiment.)
- **OQ3:** Does `namespace path` affect *variable* resolution at all, or only
  commands? (Strongly suspect commands-only; verify in 02.)
- **OQ4:** Behavior of `variable` with no value vs with value; multiple names.
