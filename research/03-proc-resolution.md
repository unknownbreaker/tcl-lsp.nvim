# 03 — Proc / Command Definition & Call-Site Resolution

**Evidence:** `experiments/03_proc_resolution.tcl`. Verified **identical on
8.6.18 and 9.0.3** (including the section-B error behavior — my prior assumption
that 9.0 auto-creates namespaces was wrong; verification corrected it).

This doc enumerates what counts as a **definition** of a command (the jump
targets for goto-definition) and the mechanisms that complicate it.

## Findings

### F-A — The `proc` name argument determines where the command is created
```
proc unqualified {}        (inside ::defn)  -> ::defn::unqualified   (current ns)
proc ::defn::sub::absolute {}                -> ::defn::sub::absolute  (absolute)
```
The name passed to `proc` follows the same relative/absolute rules as any
qualified name (see 02-F-C): leading `::` is absolute; otherwise it is relative
to the **current namespace at the point `proc` executes**.
**Resolver implication:** to compute a proc's fully-qualified name (its symbol
key), the indexer must know the current namespace where the `proc` statement
appears, then apply relative/absolute qualification to the name argument.

### F-B — Defining into a non-existent namespace ERRORS (both 8.6 and 9.0)
```
proc ::nope::missing::p {}  -> ERROR: can't create procedure ...: unknown namespace
namespace exists ::nope::missing -> 0          ;# NOT auto-created
proc child::rel {} (from ::defn, ::defn::child absent) -> ERROR: unknown namespace
```
**Resolver implication:** a qualified `proc` definition presupposes its target
namespace already exists (created by some `namespace eval`). Valid code always
has a corresponding `namespace eval` (or implicit `::`). The indexer can rely on
this: every proc's namespace is declared somewhere.

### F-C — Redefinition: last wins, ONE command; conditional defs are runtime-dependent
```
proc redef {} {first}; proc redef {} {second}  -> "second"
info procs ::redef  -> count 1
if {$pick==1} {proc cond...} else {proc cond...} -> "branch-2" (runtime pick)
```
**Resolver implication:** a single command name may have **multiple textual
`proc` definition sites** (redefinition, or mutually-exclusive conditional
branches). Which is "active" is runtime/order dependent and not statically
decidable in general. **goto-definition should offer ALL definition sites** (LSP
supports multiple locations) rather than guess one.

### F-D — `rename` mutates the command table
```
rename original renamed -> `original` becomes invalid; `renamed` runs original's body
rename to_delete ""     -> deletes the command
```
**Resolver implication:** `rename` both **destroys** a name and **creates**
another whose real definition is the original `proc`. Fully modeling this
statically is hard (and `rename` targets can be computed). **Scope decision
candidate:** treat `rename` as a best-effort/known-limitation case for v2.

### F-E — `interp alias` creates an alias command
```
interp alias {} aliased {} real_target preset
aliased extra            -> real_target(preset extra)
namespace which -command aliased -> ::aliased
interp alias {} aliased  -> real_target preset      ;# introspectable target
```
**Resolver implication:** another definition/indirection mechanism. goto-def
*could* follow `aliased` → `real_target`. Lower priority; best-effort for v2.

### F-F — `namespace ensemble`: subcommand dispatch
```
namespace ensemble create  (in ::ens with exported add/sub)
::ens add 2 3            -> 5            ;# dispatches to ::ens::add
namespace ensemble configure ::ens -map -> (empty)   ;# no explicit map
```
A default ensemble with no `-map` dispatches `ens SUB` to the **exported**
command `::ens::SUB`.
**Resolver implication:** for `ens add`, goto-definition on `add` should resolve
to `::ens::add`. This requires recognizing ensemble commands and (if present)
their `-map`. Advanced; relevant only if RVT/Rivet code uses ensembles — flag for
the RVT survey (05) and likely defer.

### F-G — Introspection gives exact definition info (test oracle)
```
info procs ::introspect2::*  -> ::introspect2::documented
info args ::introspect2::documented   -> x y
info default ... y d         -> 10
info body ...                -> (body text)
```
**Resolver implication:** `info procs`/`info args`/`info body` are the oracle for
proc definitions and signatures (useful later for hover, and now as test
fixtures). Not usable at LSP runtime (no eval), but ground truth for tests.

## Definition sites of a command (for goto-definition)

| Mechanism | Creates | v2 priority |
|-----------|---------|-------------|
| `proc NAME body` | command at qualified(NAME) | **primary** |
| `namespace import ::p::x` | alias `currentns::x` → `::p::x` | secondary (jump-through) |
| `rename OLD NEW` | `NEW` (def = OLD's proc); removes `OLD` | best-effort / limitation |
| `interp alias {} A {} TGT` | `A` → `TGT` | best-effort / limitation |
| `namespace ensemble` | `ns SUB` → exported `ns::SUB` | defer (revisit in 05) |
| builtins / C commands | no source location | N/A (no target) |

## Recommended v2 scope (to confirm in the plan phase)

- **In scope:** `proc` definitions with full relative/absolute qualification;
  multiple definition sites returned together; call-site resolution via the
  command algorithm from 02.
- **Best-effort:** `namespace import` jump-through.
- **Documented limitations (initially):** `rename`, `interp alias`, dynamic/
  conditional definitions, ensembles. Surface nothing wrong; just don't resolve.

## Open questions

- **OQ5 (carried):** unqualified variable at `namespace eval` top level (outside a
  proc) — confirm it binds the namespace's own variable. (Quick experiment owed.)
- **OQ9:** `proc` defined inside another proc body at runtime (F-06 in doc 01):
  the definition only exists after the outer proc runs. How should the indexer
  treat textually-nested `proc`? (Likely: index it as a definition in its
  computed namespace, accept that activation is runtime.)
- **OQ10:** does the eventual parser need to special-case `oo::class`/`oo::define`
  method definitions? Depends on whether RVT code is OO. Defer to 05.
