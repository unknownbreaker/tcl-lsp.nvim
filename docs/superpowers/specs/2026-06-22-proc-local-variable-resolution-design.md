# Proc-local variable resolution — design

**Date:** 2026-06-22
**Status:** Approved (pre-implementation)
**Scope:** goto-definition and goto-references for proc-local variables in `.tcl`
and `.rvt`. No new LSP features beyond the two already supported.

## Problem

goto-definition and goto-references work for commands (procs) and namespace
variables, but **not for proc-local variables**. `variableCandidates`
(`internal/resolve/resolve.go`) returns `nil` for the `FrameProc` case, and
`TestReferencesProcLocalDeferred` pins this as a deliberate deferral
("frame-local resolution is a later plan"). A user navigating a typical proc —

```tcl
proc render {items} {
    set total 0
    foreach it $items {
        incr total
    }
    return $total
}
```

gets nothing from goto-def on `$total`/`$it` or find-references on `total`.

## Why proc-locals are different

Proc-locals are **not workspace-unique**: local `x` in proc `f` is a different
variable from local `x` in proc `g`. So they cannot be keyed by name in the
workspace index the way commands and namespace variables are. In fact the index
deliberately drops them (`internal/index/index.go` filters definitions to
`DefProc`/`DefNamespaceVar` at index time). Resolution must therefore happen at
**query time, on the current file only** — locals never resolve across files.

Tcl semantics that the design relies on:

- A proc body is **one flat local scope** (the call frame). There is no block
  scoping: a `set`/`foreach`/`lassign` inside an `if`/`while`/`foreach` body
  binds in the *same* proc frame.
- `set` is **assignment, not declaration**. A parameter and every later
  `set x`/`incr x` are the **same** variable. There is no shadowing within a
  body. The de-facto "definition" is the first binding (often the parameter).
- A nested `proc` starts a **new** frame; its locals are distinct.

## Scope model

A proc-local symbol is identified by the triple **`(file, scopeID, name)`**.

- `scopeID` = the absolute byte offset of the enclosing proc body's interior
  (`bodyScope.Base`). It is unique per proc definition within a file.
- `scopeID = 0` means "no proc scope" (namespace/global frame).

**Invariant — `scopeID` is an opaque equality key.** It is only ever compared
def-to-ref for equality (`def.Scope == ref.Scope`); it is never compared against
a cursor position. This keeps `.rvt` correct: occurrence offsets
(`Start`/`End`/`NameStart`/`NameEnd`) get mapped to document coordinates by the
source seam, but `scopeID` stays in the stitched-parse coordinate space. Because
defs and refs from the same parse share that space, equality still holds, and
the only position comparisons (`NameStart ≤ offset` for nearest-preceding) use
mapped offsets on both sides.

### Why scope "falls out" of the existing traversal

`childBodies` (`internal/tcl/bodies.go`) already classifies every braced body and
assigns the frame it runs in. The scope rule rides on that single decision:

| `childBodies` case                         | Frame today        | scopeID            |
| ------------------------------------------ | ------------------ | ------------------ |
| `proc` body                                | new `FrameProc`    | **new** = body Base |
| decorated `CACHE_PROC proc …` body         | new `FrameProc`    | **new** = body Base |
| `namespace eval` body                      | `FrameNamespace`   | `0`                |
| control-flow (`if`/`foreach`/`while`/…)    | **inherits** parent | **inherits** parent |

Nested procs get distinct scopes (each body has its own Base), control-flow
bodies share the enclosing proc's scope (correct: no block scope), and decorated
procs are already recognized as proc bodies — all with no special-casing in the
resolver.

## Components and changes

### `internal/tcl/bodies.go`
- `bodyScope` gains `Scope int`.
- `childBodies(c, base, ns, frame, scope)` gains the `scope` parameter and sets
  each returned child's `Scope` per the table above:
  - `namespace eval` → `0`
  - `proc` / decorated proc → the new body's `Base`
  - control-flow / custom-command bodies → inherited `scope`

### `internal/tcl/context.go` (reference walker)
- `ContextRef` gains `Scope int`.
- `FileRefs`/`walkScript`/`recurseBodies` thread `scope` (starting at `0` for the
  top-level namespace frame); each emitted `ContextRef` carries the current scope.

### `internal/tcl/defs.go` (definition walker)
- `Definition` gains `Scope int`.
- `FileDefs`/`walkDefs`/`recurseDefBodies` thread `scope`; emitted `DefLocal`,
  `DefGlobalLink`, and `upvar`-alias defs carry the current scope.
  (`DefProc`/`DefNamespaceVar` carry whatever scope they are defined in; their
  scope is unused by the local path.)
- **New binding extraction**, emitted only when `frame == FrameProc`, reusing the
  existing list-parsing in `emitProcParams` for the brace-list cases:
  - `foreach` / `lmap` — the plain names in each var-list word
  - `lassign` — the target words `w[2:]`
  - `dict for` / `dict map {k v} …` — the names in the `{k v}` word
  - `variable NAME` inside a proc (`FrameProc`) — emit an **additional**
    `DefLocal` for `NAME` at its name offset, so a bare `$NAME` use resolves to
    the `variable` statement. The existing `DefNamespaceVar` emission (which links
    the name to the namespace variable for namespace-level resolution) is left
    unchanged.
- Already emitted (unchanged): proc params, `set` in `FrameProc`, `global`,
  `upvar` aliases.

### `internal/source` seam
- `source.Defs`/`source.Refs` pass the new `Scope` field through unchanged.
  `Scope` is NOT remapped to document coordinates (it is an opaque equality key;
  see the invariant above).

### `internal/resolve/resolve.go` (local path)
A new helper and three branches that run **before** the existing FQ/index path:

- `localAt(file, src, offset) → (name string, scope int, ok bool)`:
  1. If the offset falls within a `DefLocal`/`DefGlobalLink` name-range in
     `source.Defs(file, src)` → return its `(Name, Scope)`.
  2. Else if it falls within a `FrameProc` `RefVariable` range in
     `source.Refs(file, src)` → return its `(Name, Scope)`.
  3. Else `ok = false`.
- `Definition`: when `localAt` is `ok`, among bindings matching `(name, scope)`
  in the current file, return the **nearest preceding** one (`NameStart ≤ offset`,
  maximal), falling back to the **first** binding when none precedes. Single
  location. (Skips the index path entirely.)
- `References`: when `localAt` is `ok`, return the union of (a) binding sites and
  (b) `$`-use occurrences matching `(name, scope)`, **current file only**, deduped
  by range.
- `Declarations`: when `localAt` is `ok`, return **all** binding sites matching
  `(name, scope)` in the current file — used by the protocol layer's
  `includeDeclaration`.

`variableCandidates` continues to return `nil` for `FrameProc`; it is simply
never reached for a resolvable local because `localAt` intercepts first.

## Data flow

**goto-definition on `$total`** → `refAt` finds the `RefVariable` →
`localAt` returns `(total, scopeA)` → gather `(total, scopeA)` bindings → return
the nearest `set total` at/above the cursor (or the param if none precedes).

**find-references on `total`** (cursor on a binding or a use) → `localAt` returns
`(total, scopeA)` → union of every `(total, scopeA)` binding site and `$total`
use in the current file.

**Nested isolation** — `x` carrying `scopeA` matches only `scopeA` bindings, so
`outer`'s `x` and `inner`'s `x` never cross-match.

## Edge cases and non-goals

- Bare `$x` with no matching binding in scope → returns `nil` (Tcl would error at
  runtime without a `global`/`variable`/`upvar` link).
- `global x` / `upvar … x` → goto-def lands on the **link statement** in this
  proc, not the cross-scope origin. Chasing into the global/other frame is a
  future enhancement.
- **Arrays — deferred to v2, high priority.** Array-element locals
  (`set arr(i) …`, `$arr(i)`) are out of scope for v1, but arrays are heavily
  used in this codebase, so an array-aware follow-up is the expected next step.
  The intended model: resolve on the array *base* name (`arr`), treating
  `set arr(i)` as a binding of `arr` and `$arr(j)` as a use of `arr`, so all
  element accesses of the same array resolve together. This requires the def
  walker to recognize `name(index)` targets and the variable scanner to key
  array references by base name — noted here so the v1 binding-extraction and
  `localAt` design leave room for it rather than hard-coding `isPlainName`-only
  targets.
- **Also out of scope for v1:** `dict with` key injection, namespace-level loop
  variables, liveness/dead-store analysis ("unused parameter" is a diagnostic
  concern, not a references concern).

## Testing

- **`internal/tcl` unit:** scope threading — nested procs get distinct scopes,
  control-flow bodies inherit, decorated procs mint a new scope; new binding
  forms (`foreach`/`lmap`/`lassign`/`dict for`/`variable`-in-proc) emitted as
  `DefLocal` with correct scope and offsets.
- **`internal/resolve`:** goto-def nearest-preceding + param fallback; find-refs
  returns all occurrences (param + `set`/`incr` targets + `$`-uses);
  nested-proc isolation; `foreach` loop var; `global` link; negative case
  (undefined bare var → `nil`).
- **`.rvt` corpus golden:** a proc-local inside a `<? ?>` block resolves within
  the page; offsets land on the right document ranges.
- **Regression:** add the `Scope` field to equality-based expected values in any
  existing `tcl` tests that need it; command and namespace-variable resolution
  behavior is unchanged.

## Out of scope (explicitly)

No completion, hover, formatting, diagnostics, or rename. This design extends the
two existing features (goto-def, goto-ref) to one more symbol class.
