# Itcl OO Support for goto-definition / references — Design

**Date:** 2026-06-25
**Status:** Approved design; ready for implementation planning.
**Scope:** Extends the existing two features (goto-definition, goto-reference) to
Itcl ([incr Tcl]) classes, methods, and instance variables. No new LSP feature
categories.

## Motivation

The dominant idiom in the target Rivet/speedtables-style codebase is Itcl OO —
`itcl::class ::STDisplay { method field … }`, instantiated as `[::STDisplay #auto]`,
called as `$display field …`. Today goto-definition resolves **none** of it: class
names, method calls, and instance variables all fall through. This makes the most
common call shape in real code a dead end.

This adds Itcl awareness to the existing resolver so class names, methods, and
ivars resolve — including the `$obj method` receiver-call shape, which reuses the
just-shipped reaching-definitions engine for lightweight type-tracking.

TclOO is explicitly **out of scope** for this spec (Itcl only); the two share ~80%
structurally and TclOO can be a later spec.

## Scope

**In scope (phased — see Phasing):**
- Itcl class definitions as resolvable symbols (`DefClass`).
- Methods and instance variables as class members (`DefMethod`, `DefIvar`),
  from both inline class blocks and external `itcl::body` definitions.
- Three resolution tiers: class names; intra-class methods/ivars + inheritance;
  `$obj method` receiver-typed resolution.
- find-references for classes (complete) and methods/ivars (best-effort).

**Out of scope (explicit non-goals):**
- TclOO (`oo::class`), this spec.
- Full C3 linearization — use simple `inherit`-order traversal; refine only if needed.
- Dynamic dispatch, `configure`/`cget` option handling, `itcl::delete`, mixins,
  `rename`/`interp alias` on classes.
- Typing of method parameters, factory return values, or cross-method ivars —
  receivers whose class is not locally known stay unresolved (graceful).

## Approach

**Extend the existing structural walkers with class awareness** (not a parallel
parser). The codebase routes every tree walker through the shared `childBodies`
body-classifier (bodies.go) so defs/refs/namespace walkers cannot drift on "what
is a script body." Itcl support rides the same rails: `childBodies` learns that an
`itcl::class` body is a scope-introducer and a `method` body is a method frame, and
the existing def/ref/index/resolve layers gain class-aware cases. The one genuinely
new piece of dataflow — Tier-3 type-tracking — lands in the reaching engine, which
already does dataflow, rather than a separate system.

(A separate OO pass was rejected: it would re-implement the `childBodies` recursion
and risk exactly the walker-drift the shared classifier prevents. A full type
system / SSA for `$obj` was rejected as over-scope — the local heuristic resolves
the dominant idiom without it.)

## Data model

Three new definition kinds and one new index structure:

- **`DefClass`** — an `itcl::class ::C { … }` definition; `Name` = the FQ class name
  (`::STDisplay`). Stored in the **existing** fully-qualified symbol table alongside
  procs, because Itcl instantiation uses the class name in command position
  (`[::STDisplay #auto]`, `::STDisplay obj`, `C create x`). **Tier-1 resolution
  therefore falls out of the existing command-candidate path** — looking up
  `::STDisplay` finds a `DefClass`.
- **`DefMethod`** / **`DefIvar`** — class members, stored in a **new class table**
  in the index rather than the flat FQ map:

  ```
  classFQ ("::STDisplay") → ClassInfo {
      defSites  []Location          // the itcl::class site(s)
      inherit   []classFQ           // from `inherit Base ...` (qualified)
      methods   map[name][]Location // inline `method`/ctor/dtor + external itcl::body, merged
      ivars     map[name][]Location // `variable` / `common`
  }
  ```

  Merging into `methods[name]` is how an inline body and an external
  `itcl::body ::C::m` register as sites for the same method.

- The walking **context gains a `currentClass`** field (the enclosing class FQ),
  threaded like the existing namespace/frame/scope context.

Existing symbols (procs, namespace vars, locals) and the reaching engine are
untouched; this is additive.

## Parser: class-aware walking

- **`childBodies` recognizes `itcl::class ::C { … }`** (and `::itcl::class`) as a
  scope-introducer, like `namespace eval` — emitting a body tagged with a new
  **`FrameClass`** and `currentClass = ::C`.
- **Inside a class block (`FrameClass`), `defs.go` emits:**
  - `method NAME {args} {body}`, `constructor {args} {body}`, `destructor {body}`
    → `DefMethod` (member of `currentClass`); bodies walked as **proc-like frames
    carrying `currentClass`** (locals/params/reaching work; intra-class resolution
    knows the class).
  - `variable NAME …` / `common NAME …` → `DefIvar`.
  - `inherit Base1 Base2` → inherit edges (base names qualified to FQ).
  - class-level `proc NAME …` → indexed as a method-style member (callable bare in
    the class).
- **External `itcl::body ::C::m {args} {body}`** (top level) → a `DefMethod` for `m`
  on `::C`, body a method frame with `currentClass = ::C`.
- **Frame model:** add `FrameClass` (class block — `method`/`variable` mean *member
  declaration*). **Method bodies reuse `FrameProc` plus a non-empty `currentClass`**
  (so "in a method?" is `frame == FrameProc && currentClass != ""`), avoiding a
  second new frame kind. `currentClass` threads through the walkers.

Because it routes through `childBodies`, a method defined inside an `if`, or any
call inside a method body, is found automatically — as for procs.

## Resolution (three tiers)

**Tier 1 — class names (via the existing command path).** A command-position class
use resolves through the current command-candidate logic; it now finds a `DefClass`.
goto-def jumps to the class; find-references finds every instantiation/use. No
resolver changes beyond accepting `DefClass` as a target.

**Tier 2 — intra-class methods & ivars.** Inside a method body
(`FrameProc + currentClass`), resolution gains a **class-member step**:
- A **bare** method call or **`$this method`** → method on `currentClass`, walking
  `inherit` order until found → its def site(s) (inline and `itcl::body`).
- An **ivar use `$v`** → `currentClass`'s `variable v`, including inherited.
- **Precedence:** proc-local (unchanged) → class member (current, then inherited) →
  existing namespace/global path. Locals shadow ivars, matching Itcl.

**Tier 3 — `$obj method` (receiver-typed).** Recognize the shape: a command whose
**head word is a lone `$var` substitution**, with the **method name as the next
word** (and inside `[$obj method …]`). Ask `classOf` (below) what class `$var`
holds; if `::C`, resolve the method on `::C` (+ inherited). goto-def lands on the
method def site.

MRO is simple `inherit`-order traversal (the agreed default) at each inheritance walk.

## Type-tracking (Tier 3 detail)

A new query **`classOf(src, receiverUseOffset) → set of class FQ names`**, layered on
the reaching engine:

- Call the reaching engine for the receiver variable at the use → the assignment(s)
  that reach it.
- For each reaching binding matching an **Itcl instantiation** — `set v [::C #auto]`,
  `set v [::C new …]`, `set v [::C create name …]`, `set v [::C objName …]`, and the
  bare `set v [::C …]` command-substitution form — extract the class `::C` (qualified).
- Result is the **union** across reaching defs (a receiver assigned `::A` in one
  branch and `::B` in another resolves to methods on both — may-reach, never drops a
  real one). The method then resolves on each class (+ inheritance); goto-def returns
  the union of def sites.

**Heuristic boundary (documented, graceful):** only **locally-instantiated** objects
get a type. A receiver that is a method parameter, an ivar set in a different method,
or a factory return value has no statically-known class (Itcl has no type
annotations) → the method stays unresolved (returns nothing; never a wrong jump).
This covers the dominant `set display [::STDisplay #auto]; $display field` pattern
and degrades cleanly elsewhere.

No new dataflow machinery — reuses reaching's scope-finding, may-reach semantics, and
the `.rvt` coordinate seam.

## find-references

- **Class name** — complete: every command-position use (instantiation, `create`)
  plus the def site, via existing reference machinery.
- **Method** — best-effort: sites where the receiver/context resolves to the method's
  class (bare calls inside the class's own methods; `$obj method` sites where `$obj`
  types to the class). May under-match for dynamic receivers; documented, never
  over-matches.
- **Ivar** — best-effort: uses within the class's method bodies (and inheriting
  classes).

## Phasing (implementation milestones)

Each phase ships and tests independently:

- **Phase 1 (Tier 1):** `itcl::class` as scope-introducer; index `DefClass` + def
  sites; class-name goto-def/ref via the command path. Milestone: `[::STDisplay
  #auto]` jumps to the class.
- **Phase 2 (Tier 2):** index methods/ivars/`inherit` (inline + `itcl::body`);
  intra-class resolution (bare `m` / `$this m` / `$v`) + MRO. Milestone: method
  goto-def inside a class.
- **Phase 3 (Tier 3):** `classOf` type-tracking + `$obj method` resolution.
  Milestone: the `$display field` idiom resolves.

## Performance

- Class/method/ivar indexing is **structural** — index-phase, same cost profile as
  procs (negligible).
- **`classOf`/Tier-3 runs at request time over one proc** (like reaching), bounded
  and off any hot path. No keystroke-latency work.
- Holds the v1-scar discipline: heavy analysis in the index phase or bounded
  request-time single-proc; never the hot path.

## Testing

- **Unit tests** per layer: parser (class/method/ivar/`inherit`/`itcl::body`
  extraction), index (class-table merge of inline + external), resolver (T1 class
  names, T2 intra-class + MRO, T3 `$obj method`), `classOf` (instantiation forms,
  multi-class union, unresolvable/boundary cases).
- **Integration tests** end-to-end on Itcl fixtures modeled on the speedtables
  `STDisplay` pattern (class with methods, instantiate, `$display field`), including a
  cross-`.rvt` case.
- **Oracle caveat (known risk):** no runtime oracle for "which method a call resolves
  to" — fixtures are hand-verified. (Itcl 8.6 `info`-based ground truth can partially
  validate class/method *existence*, not call-site resolution.)

## Decisions log

- **Dialect:** Itcl only (TclOO deferred to a future spec).
- **Scope:** all three tiers, implemented in phases (T1 ships early as a usable
  milestone).
- **Method bodies:** support both inline and external `itcl::body` definitions.
- **Type-tracking:** local heuristic over the reaching engine (not full inference).
- **MRO:** simple `inherit`-order traversal (not C3).
- **find-references:** complete for classes; best-effort for methods/ivars.
- **Engine placement:** extend the shared `childBodies`/defs/refs/index/resolve
  walkers (Approach A); Tier-3 type-tracking extends the reaching engine.

## Risks & open questions

- **No resolution oracle** — fixture correctness rests on manual verification.
- **`inherit`-order vs C3** — simple traversal can pick a different method than
  Itcl's real MRO under diamond inheritance; acceptable for goto-def, revisit if it
  misleads in practice.
- **`$var <method>` shape detection** — must not misfire on non-method commands whose
  head is a `$var` (e.g. `$cmd arg` where `$cmd` holds a proc name, not an object);
  when `classOf` returns nothing, fall through (no wrong jump).
- **Class-level `proc` vs `method`** — treated uniformly as members for resolution;
  confirm this matches expectation in practice.
- **TclOO later** — keep the class-table/member abstractions dialect-neutral enough
  that a TclOO front-end could populate them, but do not build TclOO now.
