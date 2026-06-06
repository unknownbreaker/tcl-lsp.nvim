# 04 — `source`, `package`, and Multi-File Resolution

**Evidence:** `experiments/04_multifile/` (run `main.tcl`) and
`experiments/04_package/` (run `use_pkg.tcl`). Verified **identical on 8.6.18 and
9.0.3**.

This topic determines how cross-file goto-definition must work — the entire point
of an LSP. The headline: **TCL naming is workspace-global, but TCL *availability*
is runtime/load-order dependent. The LSP must index on naming and deliberately
ignore load order.**

## Findings

### F-1 — Symbols only exist at runtime after their file is sourced
```
::math::square 5  (before source) -> ERROR: invalid command name
::math::square 5  (after  source) -> 25
```
TCL knows nothing about a definition until the defining script runs. Resolution
is load-order dependent (a consequence of 02-F-G call-time resolution + dynamic
`source`).
**Resolver implication:** a static LSP **cannot and must not** replicate runtime
load order. It should index **all** workspace files and treat every definition as
available. This is an intentional, standard LSP divergence from runtime semantics
(the LSP is *more permissive* than the interpreter).

### F-2 — `source` evaluates a file in the current context; its path is a runtime value
`source [file join $here lib_math.tcl]` made `::math::*` available. The path is
usually **computed** (`[file join $dir ...]`, `[file dirname [info script]]`).
**Resolver implication:** `source` statements hint at file relationships, but
their target paths are frequently **not statically resolvable**. The index must
**not** depend on following `source` edges for correctness.

### F-3 — A namespace SPANS files; it is global, not file-scoped (KEY)
```
app_a.tcl: namespace eval ::app { variable version 1.0; proc hello ... }
app_b.tcl: namespace eval ::app { proc world {...reads version...} }
info procs ::app::*  -> ::app::hello ::app::world      (both files)
::app::world         -> sees version=1.0 from app_a.tcl
```
The same namespace is opened and extended across multiple files; all contributions
share one storage.
**Resolver implication:** the symbol table must be keyed by **fully-qualified
name across the entire workspace**, never per-file. A namespace is **not** a
module or a file. goto-definition routinely crosses file boundaries within one
namespace. This is the core data-model requirement for the indexer.

### F-4 — Relative `source` paths are CWD-relative; `info script` is the file-locating idiom
```
pwd (process cwd): .../2tcl-lsp.nvim     # NOT the sourcing file's dir
robust idiom: [file dirname [info script]]
```
**Resolver implication:** if we ever do try to statically resolve a `source`
target, we must emulate cwd-vs-`info script` semantics — but since paths are often
dynamic, **workspace globbing (index every `*.tcl`/`*.rvt`) is the reliable
strategy**, not chasing `source` targets.

### F-5 — `package require` resolves via `pkgIndex.tcl` → `package ifneeded` → `source`
```
lappend ::auto_path $here
package require greeter   -> 1.0   (pkgIndex's `package ifneeded` sourced greeter.tcl)
::greeter::hi             -> ::greeter::hi v1.0
```
`package provide NAME VER` marks a file as a package; `package require` is a
dependency edge resolved through `auto_path` + `pkgIndex.tcl`.
**Resolver implication:** packages do **not** change naming — symbols are still
fully-qualified namespaced names. Workspace indexing already covers them.
`pkgIndex.tcl` is machine-generated glue (a place to *find* files, not where users
*define* symbols); the indexer can treat `pkgIndex.tcl` as low-value. `package
provide`/`require` are useful later for project-structure/diagnostics, not for
core name resolution.

### OQ5 (closed) — Unqualified variable at `namespace eval` top level = the namespace's variable
```
namespace eval ::app { variable version 1.0; ... ; puts $version }  -> 1.0
```
Outside a proc, the "frame" is the namespace itself, so an unqualified variable
binds the namespace's own variable (contrast with inside a proc, where it is
local-only — 01-F5).
**Resolver implication:** variable resolution depends on **frame kind**:
- inside a `proc` body → local-only (needs `global`/`variable`/`upvar`/FQN);
- at `namespace eval` top level → the current namespace's variable.

## The architectural conclusion (drives the whole design)

> **Static model:** Enumerate every `*.tcl`/`*.rvt` in the workspace. Build ONE
> symbol table keyed by fully-qualified name (procs and namespace variables).
> Resolve a reference by computing its FQ name (using the 02 command/variable
> algorithms + current namespace) and looking it up in that table. **Do not model
> `source`/`package` load order for naming purposes.**

Consequences / accepted limitations (to state plainly in the plan and to users):
- **More permissive than runtime:** the LSP assumes all workspace definitions are
  "loaded." It will resolve names that a given runtime entry point might not
  actually have sourced. This is the normal LSP trade-off.
- **External packages** (installed outside the workspace, e.g. Tcllib, Rivet's own
  commands) won't be in the index → their symbols resolve to "no definition."
  Future option: index `auto_path`/installed packages; out of scope for v2.
- **Same FQ name in multiple files** (conditional `source`, environment variants)
  → multiple definition sites; return all (consistent with 03-F-C).

## Open questions

- **OQ11:** Should the indexer parse `source`/`package require` at all in v2? (Lean
  no for naming; maybe later for "which files form a project" and unresolved-import
  diagnostics.)
- **OQ12:** Workspace file discovery — glob `**/*.tcl` + `**/*.rvt`; how to handle
  large trees, vendored dirs, and `.gitignore`? (Indexer-perf design, not
  semantics.)
- **OQ13 → topic 05:** how do `.rvt` (Rivet) files fit — are they sourced, and what
  is their namespace/scope context? This is the last semantic gap before planning.
