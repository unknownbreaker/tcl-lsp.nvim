# global / upvar origin-chasing — design

**Date:** 2026-06-24
**Status:** Approved (pre-implementation)
**Scope:** goto-definition on a `global`- or `upvar`-linked proc-local jumps to the
variable's **origin** (where it actually lives) instead of the link statement, for
`.tcl` and `.rvt`. Builds on the proc-local variable resolution shipped
2026-06-22..24.

## Problem

`global config` and `upvar … alias` create a proc-local name that is an alias for a
variable living in another scope. Today goto-definition on a use of that name (or on
the link statement) lands on the **link line** itself — `global config` / `upvar …`
— not on where the variable is actually defined. The link is the mechanism, not the
definition, so the jump stops one hop short of what the user wants.

Current emission (`internal/tcl/defs.go`):
- `global NAME` → a `DefGlobalLink` carrying the bare name.
- `upvar ?level? otherVar alias` → only the **alias** is emitted, as a plain
  `DefLocal`; the **target (`otherVar`) is discarded**.

Resolution (`internal/resolve/resolve.go`): a `$config` use resolves through the
proc-local path (`localAt` → `localDefinition`) to the first matching binding —
the `global`/`upvar` link — because `isLocalBinding` treats `DefGlobalLink` as a
local binding.

## Behavior

goto-definition on a use of a linked local, or on the link statement itself, jumps
to the origin:

| Link | Origin |
| --- | --- |
| `global config` | `::config` |
| `global ::app::x` | `::app::x` |
| `upvar #0 sessions s` | `::sessions` (level `#0` = global frame) |
| `upvar 0 ::app::cfg c` | `::app::cfg` (qualified target, absolute) |
| `upvar 1 caller_var v` | **not chaseable** — caller's frame is dynamic → link only |

**Fallback:** if the origin is not defined anywhere in the workspace index,
goto-definition returns the link statement (today's behavior) — never a dead end.
The origin lookup is cross-file via the existing index. Single location either way.

The same chase fires whether goto-def is invoked from a `$config` use or with the
cursor on the name in the `global`/`upvar` statement; both route through
`localAt` → `localDefinition`.

## The change

### New field: `tcl.Definition.Origin string`
The statically-known fully-qualified origin of a linked local, or `""` when there
is none (the default for every other definition). Non-positional, so it passes
through the `source` seam unchanged and is never remapped; `DefLocal`/`DefGlobalLink`
are not indexed, so `Origin` never enters the workspace index.

### `internal/tcl/defs.go` — set `Origin` at emit time
- **`global`** block: for each linked name, set `Origin = "::"+name` (or `name`
  when it already starts with `::`). Still emitted as `DefGlobalLink`.
- **`upvar`** block: parse the optional leading level (`isUpvarLevel`); default
  level is `1` when absent. For each `(otherVar, alias)` pair, emit the alias as a
  `DefLocal` (as today) and set its `Origin`:
  - take the target's **base name** (strip a trailing `(index)` via the existing
    array base-name logic);
  - if the base is qualified (starts with `::`) → `Origin = base`;
  - else if the level is `#0` → `Origin = "::"+base`;
  - else → `Origin = ""` (frame-relative / dynamic → not chaseable).

No new `DefKind`. `global` is already distinguishable (`DefGlobalLink`); upvar
aliases stay `DefLocal` with `Origin` populated, so `isLocalBinding`,
`localReferences`, and `localAt` need no change.

### `internal/resolve/resolve.go` — chase in `localDefinition`
`localDefinition` already selects the first (lowest-offset) binding matching
`(name, scope)` and returns its location. Extend it to also capture that binding's
`Origin`. After selection: if `Origin != ""`, look it up in the index
(`lookupScoped(origin, file)`); return those locations when non-empty, otherwise
fall back to the link location (the existing return). One added branch; the
"declaration = first binding" rule and the fallback are unchanged.

## Data flow

`$config` use → `localAt` returns `(config, scope)` → `localDefinition` selects the
first `config` binding (the `global config` link, `Origin "::config"`) → index
lookup of `::config` → if defined (e.g. `set ::config 1` in any file), return that;
else return the `global config` line.

## Out of scope (deliberate)

- **find-references is unchanged.** Origin-chasing is a goto-def feature.
  Cross-linking a proc's `$config`/alias uses into the global `::config` reference
  set (the inverse direction) is a larger graph problem, deferred.
- **Frame-relative `upvar`** (`upvar 1 x …`, or default level) with a bare target —
  the caller's frame is dynamic; not statically resolvable.
- **`#N` for N>0** — intermediate frames are dynamic; only `#0` (global) is
  chaseable for a bare target.
- **`global`/`upvar` whose origin is only ever assigned inside procs** (never at
  namespace level) — the origin isn't in the index, so the link-line fallback
  applies. This is correct, not a gap.

## Testing

- **`internal/tcl` (defs):** `global config` → `DefGlobalLink` with
  `Origin "::config"`; `global ::app::x` → `Origin "::app::x"`;
  `upvar #0 sessions s` → alias `DefLocal` with `Origin "::sessions"`;
  `upvar 0 ::app::cfg c` → `Origin "::app::cfg"`; `upvar 1 caller v` →
  `Origin ""`; a plain `set local 1` → `Origin ""` (regression guard).
- **`internal/resolve`:**
  - global chase cross-file: `$config` use in file B with `global config` resolves
    to `set ::config` in file A.
  - global fallback: `global config` with no `::config` anywhere → goto-def lands on
    the `global config` line.
  - upvar `#0` chase: `upvar #0 sessions s` + `$s` resolves to `set ::sessions`.
  - upvar frame-relative: `upvar 1 x v` + `$v` → goto-def lands on the `upvar` line.
- **Regression:** proc-local scalar/array goto-def, find-references, and
  namespace/command resolution are unchanged.

## Non-goals (feature scope)

No completion, hover, formatting, diagnostics, or rename. This extends goto-def for
one more resolution hop; goto-references is untouched.
