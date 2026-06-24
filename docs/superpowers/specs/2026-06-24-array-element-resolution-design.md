# Proc-local array-element resolution — design

**Date:** 2026-06-24
**Status:** Approved (pre-implementation)
**Scope:** Extend goto-definition and goto-references to proc-local **array**
variables (`set arr(i)`, `$arr(k)`) in `.tcl` and `.rvt`. Builds directly on the
proc-local (scalar) variable resolution shipped 2026-06-22..23.

## Problem

Proc-local scalar variables resolve, but array elements do not. Two gaps on the
definition side:

- `set arr(i) 0` emits a binding named `"arr(i)"` (the whole word — `isPlainName`
  rejects only `$`/`[`, not parens), which never matches the use.
- `set arr($i) 0` emits **nothing** (the `$` makes `isPlainName` reject the word).

Meanwhile a use `$arr(i)` is already extracted as a reference to the **base name**
`"arr"` (verified: `TestWordVarRefsArrayName`), and the subscript variable in
`$arr($i)` is already found as a use of `i` (`TestWordVarRefsArrayIndexVarAlsoFound`).
So defs and uses disagree on the name (`"arr(i)"` vs `"arr"`) and arrays don't
resolve.

## Model

An array element access resolves to its **base variable**. `set arr(i)`,
`incr arr(j)`, and `$arr(k)` are all occurrences of one proc-local symbol `arr`,
keyed `(file, scope, "arr")` — exactly the key a scalar `arr` would use. This
matches the reference implementation (bitwisecook/tcl-lsp `_scope.py`, which keys
every variable on `split_array_name`'s base and tracks indices only as metadata)
and is a strict extension of our scalar proc-local model:

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

Apply it in the **`FrameProc`** local-binding emitters — `set`, `incr`, `append`,
`lappend` — replacing the current `isPlainName(w[1])` gate and the
`Name`/`NameStart`/`NameEnd` fields. The emitted `DefLocal` is named `arr` with a
range covering just `arr`, so goto-def lands on the base name token.

The four emitters share one base-name path, so element and scalar targets cannot
diverge between commands.

## Out of scope (deliberate)

- **`array set arr {…}`** — not treated as a binding. Matches bitwisecook
  (no `array` handler in its command dispatch); arrays are defined through
  element writes. Trivial future add if a truer declaration is ever wanted.
- **Namespace / global array vars** (`set ::ns::arr(i)`, `variable arr`) — the
  same helper would fix them, but this increment stays proc-local (`FrameProc`),
  where the issue was reported and all prior proc-local work lives. No
  regression: namespace/global array targets keep today's behavior (they resolve
  via the index path, unchanged). Noted as a follow-up using the same helper.
- **Index metadata** (the set of seen indices) — bitwisecook tracks it for
  completion/diagnostics; outside our two-feature scope.
- **Subscript-only navigation** — goto-def *onto* the `(i)` part is not a target;
  the cursor must be on the base name or a `$`-use. `$i` inside a subscript
  resolves as its own scalar use (already works).

Multi-key indices like `arr(a,b,c)` need no special handling: the base is
everything before the first `(`.

## Testing

- **`internal/tcl` (defs):** `set arr(i)`, `incr arr(j)`, `append arr(k)`,
  `lappend arr(m)`, and dynamic `set arr($i)` each emit one `DefLocal` named
  `"arr"` whose range slices to exactly `arr`; the subscript `$i` still emits a
  use of `i`; a scalar `set foo 0` is unaffected (named `"foo"`, full range);
  `set arr(i)` does not also emit `"arr(i)"`.
- **`internal/resolve`:** goto-def on `$arr(k)` → the first `arr` binding;
  find-refs on `arr` returns all element writes + `$arr(...)` uses (current file
  only); two procs each with their own `arr(...)` stay isolated by scope; a
  use whose array is built only by element writes still resolves (first write is
  the declaration).
- **`.rvt` corpus golden:** a proc that builds and reads an array inside a
  `<? ?>` block — goto-def on the `$arr(...)` use lands on the first element
  write within the page; find-refs stays within the page.
- **Regression:** scalar proc-local goto-def/find-refs and namespace/command
  resolution are unchanged.

## Non-goals (feature scope)

No completion, hover, formatting, diagnostics, or rename. This extends the two
existing features (goto-def, goto-ref) to one more occurrence shape.
