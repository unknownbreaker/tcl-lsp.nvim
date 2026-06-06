# 06 — Synthesis: Resolver Model, Architecture, and v2 Scope

This consolidates topics 01–05 into (a) one precise name-resolution model, (b) the
implied architecture, and (c) a concrete v2 scope for goto-definition and
goto-reference. It is the bridge to the planning phase (Task #4). Every claim
traces to a verified finding in 01–05.

---

## Part 1 — The resolution model

### Step 0 (PREREQUISITE): classify the name at the cursor
Resolution cannot start until the name is classified. The parser must label each
identifier with:
1. **Syntactic position** — *command* (first word of a command / after `[`) vs
   *variable* (`$name`, `set name`, `incr name`, …). The two use **different
   algorithms** (02). This is the hardest parser obligation (carried as OQ8).
2. **Qualification** — leading `::` ⇒ **absolute**; contains `::` but no leading
   ⇒ **relative** to current namespace; no `::` ⇒ **bare** (01-F5, 02-F-C).
3. **Enclosing frame kind** — `proc` body vs `namespace eval` top level vs
   `.rvt` template top level (= `::request`). Variable resolution depends on this
   (04 / 05).
4. **Current namespace** at that source point (tracked through `namespace eval`).

### Command-name resolution (command position)
For bare command `c` referenced in namespace `N`:
1. `N::c`
2. for each `p` in `N`'s `namespace path` (in order): `p::c`
3. `::c`
4. else → unresolved (external/builtin or error)

Never walks ancestor namespaces. Qualified names skip to the named target
(absolute exact; relative = `N::<name>`). (02-F-A, F-B, F-C)

### Variable-name resolution (variable position) — frame-kind dependent
- **Inside a `proc` body:** local frame **only**. A non-local binding exists only
  if introduced by `global x` (→ `::x`), `variable x` (→ `N::x`), `upvar … x`
  (alias; target may be dynamic), or a parameter. A **bare** name with none of
  these and no local assignment is an **error**, NOT a namespace lookup. No
  `namespace path` for variables. (01-F1/F2/F3/F5, 02-F-E)
- **At `namespace eval` top level (incl. `.rvt` `::request`):** a bare name is the
  **current namespace's own variable**. (04-OQ5, 05-V2)
- **Fully-qualified `$::ns::x`:** the named namespace variable, any frame. (01-F5)

### Definition sites (the goto-definition targets), by symbol kind

| Symbol | Definition sites | Source |
|--------|------------------|--------|
| **proc / command** | `proc NAME body` (NAME qualified vs current ns) | 03-F-A |
| | `namespace import ::p::x` → alias `N::x` (jump-through to `::p::x`) | 02-F-D |
| | `rename`, `interp alias`, ensemble subcommands | 03-D/E/F (defer) |
| **local variable** | parameter; first/any `set` in the same proc frame | 01 |
| **namespace variable** | `variable name …`; any qualified `set ::ns::name …`; bare `set`/assignment at that namespace's top level | 01-F3/F7, 04-OQ5 |
| **global variable** | top-level `set name …` in `::`; `global name` is a *use that links*, def is `::name` | 01-F2 |

A single name may have **multiple definition sites** (redefinition, conditional
branches, a namespace opened in several files). Return **all** of them. (03-F-C,
04-F-3)

---

## Part 2 — Architecture

### A. Workspace-wide, fully-qualified symbol table (the core data model)
A namespace **spans files** and is global, not file-scoped (04-F-3). Therefore:
- Enumerate **every** `*.tcl` and `*.rvt` in the workspace (glob; do not chase
  `source`/`package` edges — paths are dynamic and unreliable). (04-F-2/F-4/F-5)
- Build **one** symbol table keyed by **fully-qualified name**, each entry holding
  all its definition sites (file + range).
- Resolve a reference by computing its FQ name (Part 1) and looking it up.

### B. Two phases, not one streaming pass
Resolution is call-time, so forward references are normal (02-F-G). The indexer
**must** collect all definitions first, then resolve references against the
complete table. Never resolve top-to-bottom in one pass. (02-F-G, 04-F-1)

### C. Intentional divergence from runtime (and why it's correct)
TCL only "knows" a symbol after its file is `source`d at runtime; load order is
dynamic and unknowable statically (04-F-1). The LSP is deliberately **more
permissive**: it assumes everything in the workspace is loaded. Standard LSP
trade-off. Accepted consequences:
- external symbols (Tcllib, Rivet builtins, other installed packages) → "no
  definition" (mitigated for Rivet by the known-commands table, 05-D);
- the same FQ name across files → multiple defs (return all).

### D. `.rvt` handling
- **Stitch** all `<? ?>`/`<?= ?>` TCL regions of a file into one logical script
  and parse together; literals are opaque output; control structures span blocks
  (05-V1). Cannot parse blocks independently.
- **Positions:** every token keeps its original `.rvt` offset so results point
  into the `.rvt` (05-V4).
- **Scope:** template top level = `::request` namespace; bare template procs/vars
  are `::request::*` and effectively page-local (05-V2). Reusable code lives in
  explicit namespaces / `.tcl` and indexes normally.
- `::rivet::parse` ≈ `source` (shared context); `include` = raw text — defer
  following for v2 (05-C).
- Ship the `::rivet::` command catalog as a **known-commands table** (05-D).

---

## Part 3 — goto-definition algorithm (target behavior)

```
goto_definition(file, line, col):
  tok = token_at(file, line, col)                 # parser; .rvt -> stitched
  if tok is null: return none
  pos = classify_position(tok)                    # command | variable  (Step 0)
  ns  = current_namespace_at(tok)
  frame = enclosing_frame_kind(tok)               # proc | ns-top | request

  if pos == command:
      fq_candidates = command_resolution(tok.name, ns)   # current->path->global
  else:  # variable
      binding = variable_binding(tok, frame, ns)         # local/global/variable/upvar/FQN
      if binding is a same-frame local/param: return its def site(s) in this frame
      fq_candidates = [binding.fq_name]                  # e.g. ::g, N::x, ::ns::x

  defs = symbol_table.lookup_all(fq_candidates)          # may be many
  defs += follow_import_alias(fq_candidates)             # best-effort jump-through
  return defs or none
```

## Part 4 — goto-reference algorithm (target behavior)

```
goto_references(file, line, col):
  def_fq = resolve_to_fq_definition(file, line, col)     # reuse Part 3 core
  refs = []
  for each indexed reference R in workspace:
      if classify+resolve(R) == def_fq: refs.add(R)
  # includes the linking statements: `global`, `variable`, qualified `set`,
  # and import aliases pointing at def_fq
  return refs
```

Both directions share one engine: *classify → compute FQ → match against the
table*. goto-reference is the inverse index of goto-definition.

---

## Part 5 — Proposed v2 scope

**In scope (must work reliably):**
- proc/command goto-def + goto-ref, with full relative/absolute qualification and
  `namespace path` for commands.
- variable goto-def + goto-ref for locals/params, `global`, `variable`,
  qualified namespace vars, with frame-kind-correct resolution.
- cross-file resolution within shared namespaces (workspace FQ index).
- `.rvt`: stitched parsing, `::request` scope, position mapping, known-commands
  table for Rivet builtins.
- multiple definition sites returned together.

**Best-effort (resolve when cheap, don't promise):**
- `namespace import` alias jump-through.
- `::request` symbols across `parse` chains.

**Deferred (document as known limitations; surface nothing wrong):**
- `upvar`/`uplevel` with dynamic target names (01-F4).
- `rename`, `interp alias` (03-D/E).
- `namespace ensemble` subcommand dispatch (03-F).
- dynamic/conditional/`eval`-constructed definitions (01-F6, 03-C).
- external packages outside the workspace.
- following `source`/`package`/`parse` to drive naming (we index by glob instead).

**Explicit non-goals for v2:** completion, hover, diagnostics, rename-as-refactor,
formatting, symbols/outline — none until goto-def + goto-ref are solid.

---

## Part 6 — The "wacky TCL" hard-cases catalog (what bites naive resolvers)

1. Variable vs command resolution are **different algorithms** (02). #1 footgun.
2. Bare variable in a proc does **not** fall back to the namespace var (01-F5).
3. Variable resolution depends on **frame kind** (proc vs ns-top vs request).
4. Commands resolve **current → path → global**, never via ancestors (02-F-A).
5. **Call-time** resolution → forward refs; two-phase indexing required (02-F-G).
6. Namespaces **span files**; not modules (04-F-3).
7. `upvar`/`uplevel` targets are often **runtime values** (01-F4).
8. **Redefinition / conditional defs** → many definition sites (03-C).
9. `.rvt` is **one stitched script** in `::request`, with control flow spanning
   blocks (05-V1/V2).
10. `source`/`parse` paths are **dynamic** → index by glob, not by edges (04-F-2).

---

## Part 7 — Consolidated open questions

**Planning decisions (we decide):**
- OQ8/OQ16: command-vs-variable position classification — the parser's hardest
  job; design the tokenizer/position labeler around it.
- OQ11: parse `source`/`package`/`parse` at all in v2? (Lean: no for naming;
  maybe later for project-grouping + unresolved-import diagnostics.)
- OQ12: workspace file discovery (globs, vendored dirs, `.gitignore`, perf).
- OQ17: how to treat `::request` page-local symbols (within-file + best-effort
  across `parse`).
- Multiple-definition UX: always return all sites?

**FlightAware confirmations (need you):**
- [E] app bootstrap (`global.tcl`, Before/AfterScript hooks).
- [F]/OQ14: production Rivet version (command set above is 3.2) + a representative
  real `.rvt` + house namespace/file conventions.

**Carried language Qs (cheap experiments during build):**
- OQ2 arrays/`dict` element access vs whole-variable resolution.
- OQ6/OQ7 glob `namespace import` enumeration + re-export.
- OQ9 textually-nested `proc` indexing.
- OQ10 `oo::` method definitions (only if RVT code is OO).

---

## Part 8 — What the parser must provide (requirements feeding design)

The resolver is only as good as the parse. The parser/indexer must yield, per
identifier: its **text**, **syntactic position** (command/variable), **byte
range mapped to the original file** (incl. `.rvt` stitching), the **current
namespace**, and the **enclosing frame kind**. Plus, per file: namespace-open
structure, `namespace path`/`export`/`import` declarations, and the list of
definition sites. This is the contract the goto-def/ref engine consumes — and the
first thing the plan (Task #4) should specify.
