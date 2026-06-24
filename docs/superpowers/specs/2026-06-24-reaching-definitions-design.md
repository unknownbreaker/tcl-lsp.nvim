# Reaching-Definitions for Proc-Local goto-definition — Design

**Date:** 2026-06-24
**Status:** Approved design; ready for implementation planning.
**Scope:** goto-definition only (find-references and other features unchanged).

## Motivation

Today, goto-definition on a proc-local variable use (`$x`) jumps to the **first /
earliest binding** of that name in the proc — a stable, declaration-like answer
chosen because Tcl locals have no declaration keyword. That heuristic is *positional*:
it ignores control flow. In real code with loops and conditionals that reassign a
variable (and `break`/early `return` that alter flow), the first binding is often
*not* the assignment whose value actually reaches the cursor.

This design replaces the positional heuristic with **intraprocedural
reaching-definitions analysis**, so goto-definition on a local lands on the
assignment(s) that can actually reach that use — possibly more than one (e.g. a
value assigned in either branch of an `if`).

This is also foundational infrastructure: a later, separately-specced effort
(Itcl/TclOO `$obj method` type-tracking) is another forward dataflow over the same
proc structure and can reuse this engine. That extension is **out of scope here.**

## Scope

**In scope**
- A new pure analysis that, for a single proc body, computes for each local
  variable use the set of def-sites that may reach it.
- Rewiring proc-local goto-definition to return that reaching set.

**Out of scope (explicit non-goals)**
- find-references — stays **all-occurrences-in-scope** (already complete; filtering
  by reachability would confusingly *hide* occurrences).
- Cross-frame / interprocedural tracking — `global` / `variable` / `upvar` /
  `uplevel` are dynamically scoped and not statically analyzable; the existing
  origin-chasing for those links is unchanged. Reaching-defs governs genuinely-local
  values only.
- Itcl/TclOO method/type resolution (future spec; will consume this engine).
- SSA — rejected. Reaching-defs gives the needed correctness without dominance
  frontiers, φ-insertion, or renaming.

## Approach

**Structured, AST-directed dataflow (no explicit CFG).** Tcl control flow is
structured — commands with body blocks — and the only non-local exits are `break`,
`continue`, and `return`. So rather than materializing a control-flow graph, the
analysis is a syntax-directed traversal with a transfer rule per construct, reusing
the recursion the parser already performs over these same bodies (`bodies.go` /
`walkDefs`). This fits the codebase grain and avoids a separate CFG data structure.

(An explicit-CFG variant was considered; it is more "textbook" and marginally nicer
for `catch`/`switch`, but adds a graph layer for no correctness gain here. SSA was
considered and rejected as over-scope.)

## Architecture & placement

The decisive constraint: **proc-locals are intraprocedural and current-file-only.**
The existing `resolve.localDefinition` / `localReferences` already operate solely on
the cursor's file. So reaching-defs is only ever needed for **the single proc the
cursor sits in** — never workspace-wide.

- **New package `internal/dataflow`** — a *pure* function: given one proc body (parsed
  commands) plus its variable defs/uses, return reaching-def chains (use position →
  set of reaching def-sites). No I/O, no index, no workspace knowledge.
- **`internal/resolve` consumes it on demand**, at request time, for just the enclosing
  proc. `localDefinition` swaps "first/nearest binding" for "the reaching set."
- **Index/workspace layer untouched.** Locals were never indexed; command and
  namespace-variable resolution are unchanged. Blast radius = the local-variable path
  in `resolve` + the new package.

Performance consequence: analyzing one small proc per goto-def request means **no
index-phase cost, no startup cost, no memory growth, no staleness**. It runs on the
request path, but the request-path work is "analyze one proc," which is cheap.

## The analysis

**State:** a map `var → set of def-sites` — "which assignments can currently reach
here." A def-site is any binding the parser already identifies (`set`, `incr`,
`append`, `lappend`, `foreach` / `lmap` / `lassign` / `dict for` targets, params).
The walker threads this map through the proc body and, at each use (`$x`), snapshots
the current set for `x`. That snapshot **is** the reaching set goto-def returns.

**Transfer rules:**
- **Assignment `set x …`:** kill `x`'s prior set, gen `{this site}`.
- **Read-modify-write `incr` / `append` / `lappend x`:** first *use* the prior set
  (snapshot for goto-def), then become the new def.
- **Sequence:** thread the map left → right.
- **`if` / `elseif` / `else`:** analyze each branch from the entry map; exit = **union
  (join)** of all branch exits, including fall-through when there is no `else`. This
  join is why a use after the `if` can have two reaching defs.
- **`while` / `for` / `foreach`:** iterate the body to a **local fixpoint** (entry =
  join of pre-loop state and the back-edge), so a value assigned in iteration N
  reaches iteration N+1. `for` / `foreach` also gen their loop variable at entry.
- **`break`:** merge current map into the loop's **exit set**, stop this path.
  **`continue`:** merge into the **back-edge set**, stop. **`return`:** merge into proc
  exit, stop. (These three non-local exits are threaded as accumulator sets through the
  recursion — the one fiddly part of the structured approach.)
- **`switch`:** join across all arms + default (a multi-way `if`).
- **`catch {body} resVar` / `try`:** *conservative* — the post-`catch` state joins the
  entry, the normal body-exit, **and** every def generated anywhere in the body (the
  error could fire mid-body). `resVar` / options vars are gen'd as defs.

**Soundness stance:** **may-reach** over-approximation — when in doubt, include a def
rather than drop it. For goto-def that is the safe direction: occasionally one extra
candidate location, never a missing one.

## goto-def integration

`localDefinition` for a variable use becomes: ask `dataflow` for the reaching set at
that position; return those def locations (one LSP result each — multiple on a merge).

- **Empty reaching set** (a `$x` read before any local assignment): the signal that
  this is not a plain local — it is a parameter (already a def-site at entry, so the
  set is non-empty) or a `global` / `variable` / `upvar` link. An empty local set
  **falls through to the existing path**: the shipped origin-chasing for links is
  unchanged.
- **Cursor on a pure write** (`set x` name range): returns that binding itself
  (declaration of this value) — goto-def-on-a-def lands on itself, as today.
- **Cursor on a read-modify-write** (`incr x`, `append x`): treated as a *use* —
  returns the reaching set feeding it ("where did the value I'm mutating come from").
  Default; trivially flippable to "return itself."
- **find-references:** unchanged — all occurrences in scope.

Only user-visible change: goto-def on a local `$x` lands on the assignment(s) that
actually reach it, instead of always the first binding.

## Performance & degradation

- **Request-time, one proc.** Cost ≈ O(body size × distinct vars × fixpoint
  iterations) — microseconds for normal procs.
- **Bounded fixpoint:** monotone and fast-converging; iterations are capped as a
  safety net.
- **Size guardrail:** above a command-count / byte cap, skip the analysis and fall
  back to today's first-binding behavior — never hang, never block a keypress.
- **No caching initially** (YAGNI); add a per-`(file, proc, hash)` cache only if
  profiling shows need.

## Testing

- **`internal/dataflow` unit tests** — control-flow fixtures with marked uses and
  hand-verified expected reaching sets: straight-line, `if`/`else` merge, loop-carried
  reassignment, `break`/`continue` exit/back sets, early `return`, `switch`, nesting,
  conservative `catch`.
- **`resolve` integration tests** — goto-def on a local returns the right reaching
  locations; global/upvar links still origin-chase; find-refs unchanged;
  oversized-proc degrades to first-binding.
- **Oracle caveat (known risk):** name resolution had Tcl 8.6 `namespace which` as
  ground truth. Reaching-defs has **no runtime oracle** — Tcl does not expose "which
  assignment reached." Expected sets are hand-authored and hand-verified; careful
  fixture design is the safety net.

## Decisions log

- **Primary deliverable:** build the engine and wire it to existing proc-local
  variable goto-def first; OO type-tracking is a separate later spec.
- **Scope boundary:** intraprocedural (single-proc CFG-equivalent); cross-frame stays
  best-effort via existing origin-chasing.
- **goto-def behavior:** return the full reaching set (context-sensitive, possibly
  multiple), replacing first-binding.
- **find-references:** unchanged (all occurrences).
- **`catch`/`try`:** conservative may-reach approximation now; refine later if needed.
- **Engine style:** structured AST-directed dataflow (Approach B), not explicit CFG,
  not SSA.

## Risks & open questions

- **No reaching-defs oracle** — fixture correctness rests on manual verification.
- **`catch`/`try` precision** — the conservative model can report an extra candidate;
  acceptable for goto-def, revisit if it proves noisy.
- **Read-modify-write goto-def semantics** — defaulting `incr`/`append` cursor to
  "use" (reaching set); confirm this matches user expectation in practice.
- **Generic-domain shape** — the engine should be written so the abstract domain
  (def-sites here) can later be swapped for class-sets (OO type-tracking) without
  reworking the traversal; keep that seam in mind, but do not build the OO domain now.
