# Proc-local array-element resolution — design

**Date:** 2026-06-24
**Status:** Approved (pre-implementation)
**Scope:** Extend goto-definition and goto-references to **array** variables
(`set arr(i)`, `$arr(k)`) — both proc-local and namespace/global — in `.tcl` and
`.rvt`. Builds directly on the proc-local (scalar) variable resolution shipped
2026-06-22..23 and reuses the existing namespace-variable index path for the
namespace/global case.

## Problem

Scalar variables resolve (proc-local and namespace/global), but array elements do
not. Two gaps on the definition side, in **both** the proc-local (`DefLocal`) and
namespace (`DefNamespaceVar`) emitters:

- `set arr(i) 0` emits a binding named `"arr(i)"` (the whole word — `isPlainName`
  rejects only `$`/`[`, not parens), which never matches the use.
- `set arr($i) 0` emits **nothing** (the `$` makes `isPlainName` reject the word).

Meanwhile a use `$arr(i)` is already extracted as a reference to the **base name**
`"arr"` (verified: `TestWordVarRefsArrayName`), and the subscript variable in
`$arr($i)` is already found as a use of `i` (`TestWordVarRefsArrayIndexVarAlsoFound`).
So defs and uses disagree on the name (`"arr(i)"` vs `"arr"`) and arrays don't
resolve.

## Model

An array element access resolves to its **base variable**, in whatever scope that
variable lives. `set arr(i)`, `incr arr(j)`, and `$arr(k)` are all occurrences of
one symbol `arr` — keyed `(file, scope, "arr")` for a proc-local, or by
fully-qualified name (e.g. `::ns::arr`) through the workspace index for a
namespace/global var — exactly the key the scalar `arr` would use. This matches
the reference implementation (bitwisecook/tcl-lsp `_scope.py`, which splits every
variable name to its base *before* any scope branching — local, global, and
namespace-qualified alike — and tracks indices only as metadata) and is a strict
extension of our scalar model:

- **goto-definition** on any occurrence → the first (lowest-offset) binding of
  `arr` (the declaration), idempotent — same first-binding rule as scalars.
- **find-references** on `arr` → every element write plus every `$arr(...)` use,
  current file only.

Tcl guarantees a name is either scalar or array in a given scope (mixing is a
runtime error), so keying element access on the base name cannot collide with a
distinct scalar of the same name.

## The change is definition-side only

### Use side — no change
`parseVarRef` (`internal/tcl/varref.go`) already stops the name scan at `(`, so
`$arr(i)` / `$arr($i)` yield a `RefVariable` named `"arr"` (range covering
`$arr`), and the subscript `$i` is scanned separately as a use of `i`. Tested.

### Resolver — no change
`localAt` / `localReferences` / `localDefinition` (`internal/resolve/resolve.go`)
already key on the `Name` string. Once the definition walker emits `"arr"`,
matching, goto-def, and find-refs all work with no resolver edits.

### Definition walker — the one change (`internal/tcl/defs.go`)
Add a helper that extracts the base name from an array-element target:

```
arrayBaseName(w Word) -> (name string, start, end int, ok bool)
```

- Find the first `(` in `w.Text`.
- **If present at index p:** the base is `w.Text[:p]`. Require the base is a
  non-empty bare name (only name bytes and `::`; no `$` or `[` in the *base*
  part — the index after `(` may contain anything). Return `name = base`,
  `start = w.Start`, `end = w.Start + p`, `ok = true`. This covers literal
  `arr(i)` and dynamic `arr($i)` uniformly, because the `$` lives after `(`.
- **If absent:** fall back to the existing whole-word rule (`isPlainName(w)` →
  `name = w.Text`, full range).

Apply it at every emit site that currently gates on `isPlainName(w[1])` for a
variable target, replacing that gate and the `Name`/`NameStart`/`NameEnd` fields:

- **`FrameProc`** locals — `set`, `incr`, `append`, `lappend` → `DefLocal` named
  `arr` (range covering just `arr`); goto-def/find-refs run through the existing
  proc-local query path.
- **`FrameNamespace`** — `set` → `DefNamespaceVar` named `qualify("arr", ns)`
  (e.g. `::ns::arr`), range covering just `arr`; resolution runs through the
  existing **workspace index** with no further change, because the index already
  matches by name string — once the def is the base FQ name, the use's base
  candidate (`::ns::arr`) matches it, including cross-file.

The `variable arr` emitter already records the base name (the `variable` command
takes a name, not an element), so it needs no change. Namespace-frame
`incr`/`append`/`lappend` are not variable-definition sites today (only `set` is),
and that is unchanged — `set ::ns::arr(i)` is the overwhelmingly common namespace
array write, and `array set` is handled below.

All sites call the one shared `arrayBaseName` helper, so element and scalar
targets cannot diverge across commands or scopes. (No resolver changes; the
proc-local and index paths are left exactly as they are — no refactor.)

## Out of scope (deliberate)

- **`array set arr {…}`** — not treated as a binding. Matches bitwisecook
  (no `array` handler in its command dispatch); arrays are defined through
  element writes. Trivial future add if a truer declaration is ever wanted.
- **Namespace-frame `incr`/`append`/`lappend`** — not definition sites today
  (only `set` is, at namespace frame); unchanged. The common namespace array
  write is `set ::ns::arr(i)`, which is covered.
- **Index metadata** (the set of seen indices) — bitwisecook tracks it for
  completion/diagnostics; outside our two-feature scope.
- **Subscript-only navigation** — goto-def *onto* the `(i)` part is not a target;
  the cursor must be on the base name or a `$`-use. `$i` inside a subscript
  resolves as its own scalar use (already works).

Multi-key indices like `arr(a,b,c)` need no special handling: the base is
everything before the first `(`.

## Testing

- **`internal/tcl` (defs):**
  - *Proc-local:* `set arr(i)`, `incr arr(j)`, `append arr(k)`, `lappend arr(m)`,
    and dynamic `set arr($i)` each emit one `DefLocal` named `"arr"` whose range
    slices to exactly `arr`; the subscript `$i` still emits a use of `i`; a scalar
    `set foo 0` is unaffected (named `"foo"`, full range); `set arr(i)` does not
    also emit `"arr(i)"`.
  - *Namespace:* inside `namespace eval ::app { set cfg(host) x }`,
    `set cfg(host)` emits a `DefNamespaceVar` named `::app::cfg` (range covering
    just `cfg`), not `::app::cfg(host)`.
- **`internal/resolve`:**
  - *Proc-local:* goto-def on `$arr(k)` → the first `arr` binding; find-refs on
    `arr` returns all element writes + `$arr(...)` uses (current file only); two
    procs each with their own `arr(...)` stay isolated by scope; an array built
    only by element writes still resolves (first write is the declaration).
  - *Namespace / cross-file:* a `.tcl` (or `.rvt`) that reads `$cfg(host)` in
    `::app` resolves to the `set cfg(...)` definition in another file's
    `namespace eval ::app`, and find-refs from that definition includes the
    element use — exercising the index path with base-named array defs.
- **`.rvt` corpus golden:** a proc that builds and reads an array inside a
  `<? ?>` block — goto-def on the `$arr(...)` use lands on the first element
  write within the page; find-refs stays within the page.
- **Regression:** scalar proc-local goto-def/find-refs and namespace/command
  resolution are unchanged.

## Non-goals (feature scope)

No completion, hover, formatting, diagnostics, or rename. This extends the two
existing features (goto-def, goto-ref) to one more occurrence shape.
