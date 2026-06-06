# 05 — RVT (Rivet Template) Scope

**Status: PARTIALLY VERIFIED.** Rivet is an Apache C module and is **not
installed** in this environment, so real `.rvt` processing was not run. Instead a
**faithful simulation of the documented Rivet transform**
(`experiments/05_rvt/rivet_sim.tcl` + `sample.rvt`) was used to verify the
**scope consequences** of that transform on TCL 8.6. Rivet-specific details are
flagged **[CONFIRM]** and must be checked against the real Rivet/FlightAware
setup before the design relies on them.

## The Rivet processing model (background)

A `.rvt` file is HTML/text with embedded TCL:
- `<? code ?>` — TCL code, inline and verbatim.
- `<?= expr ?>` — outputs the value of `expr` (sugar for `puts`).
- everything else — literal output.

Rivet compiles the whole file into **one TCL script** (literals become output
calls; code blocks are concatenated in order) and evaluates it per request.

## What the simulation VERIFIED (scope consequences)

The generated script for `sample.rvt` (abridged):
```
emit $::L(0)
set title "Pets"
...
foreach it $items {
emit $::L(4)
emit [subst {$it}]      ;# the literal <li> HTML, now INSIDE the loop
emit $::L(5)
}
...
proc render_footer {} { return "footer defined in [namespace current]" }
emit [subst {[namespace current]}]
```
Verified outputs:
```
ns-at-template-top = ::                        # template top level runs in ::
later-block-sees-title = Pets                  # var set in block 1 visible in a later block
render_footer -> footer defined in ::          # proc defined in template lives in ::
info procs ::render_footer -> ::render_footer
title leaked to global frame? 1 (Pets)         # top-level set => global/:: variable
```

### V1 — The whole template is ONE concatenated script (blocks are not independent)
A control structure can **span** `<? ?>` blocks; the literal HTML between them
becomes output statements **inside** that structure
(`<? foreach { ?> ...html... <? } ?>`).
**Resolver/parser implication (critical):** the parser must **stitch all TCL
regions of a `.rvt` into one logical script** and parse them together. It must
**not** parse each `<? ?>` block in isolation — braces, scopes, and variable
bindings carry across blocks.

### V2 — Variables and procs at template top level behave like `::`-level TCL
`namespace current` is `::`; a top-level `set` creates a global; a `proc` is
created in `::`. (Modulo the request-namespace question in [CONFIRM-A].)
**Resolver implication:** treat a `.rvt`'s template-top-level code exactly like a
`.tcl` file's top-level code for scope/definition purposes — same rules as
docs 01–04. Procs/vars defined in templates are indexable definitions.

### V3 — `<?= expr ?>` regions contain real references
`<?= $title ?>` is a variable reference; `<?= [foo] ?>` is a command reference.
**Resolver implication:** echo regions must be parsed as TCL expressions and their
symbols resolved/indexed like any other reference (so goto-definition works from
inside `<?= ... ?>`).

### V4 — Source-position mapping back to the `.rvt`
The stitched script is a transformation of the original bytes.
**Resolver implication:** every token in the stitched script must carry its
**original `.rvt` byte offset / line:col**, so goto-definition and
goto-reference point to the correct place in the `.rvt` file, not into a
generated artifact. This is a hard requirement on the parser's position tracking.

## Rivet specifics that NEED CONFIRMATION [CONFIRM]

These were **not** verifiable here and could change the model:

- **[CONFIRM-A] Request namespace.** Does Rivet evaluate request templates in the
  true global `::`, or in a per-request namespace / child interpreter? If a
  dedicated namespace, top-level template symbols live there, not `::`. (Affects
  what FQ name template definitions get.)
- **[CONFIRM-B] `<?= ?>` exact semantics** (modeled here as "output the value").
  Confirm it is `puts`-equivalent and whether it adds newlines.
- **[CONFIRM-C] Template composition:** Rivet's `parse`/`include` (and any
  FlightAware include convention) pull other `.rvt`/`.tcl` into the stream —
  analogous to `source` (topic 04). Likely **defer** for v2; workspace indexing
  still covers naming.
- **[CONFIRM-D] Rivet builtin commands** (`::rivet::*`, `headers`, `var`,
  `makeurl`, `load_response`, `parray`, etc.) are **external** (C-implemented),
  not in the workspace → resolve to "no definition" (like external packages,
  04). Future: ship a known-commands stub list. Need the actual command set.
- **[CONFIRM-E] Per-app bootstrap** (`global.tcl`, `request_init`, constructors)
  and whether procs persist across requests (interp caching). Doesn't affect
  static indexing (we index regardless), but informs diagnostics later.
- **[CONFIRM-F] FlightAware conventions:** house rules for namespaces, file
  layout, custom template directives. Ask for a representative `.rvt`.

## Resolver implications summary

1. **Parser:** extract TCL from `<? ?>` and `<?= ?>`; treat literals as opaque
   output; **stitch all TCL regions into one script per file**; preserve original
   `.rvt` positions for every token.
2. **Scope:** template top level = `::`-level TCL (pending [CONFIRM-A]); apply the
   exact rules from docs 01–04.
3. **Indexing:** `.rvt` definitions enter the same workspace-wide, FQ-keyed symbol
   table as `.tcl` (topic 04). Glob `*.rvt` alongside `*.tcl`.
4. **External symbols:** Rivet builtins resolve to "no definition" for v2; consider
   a stub list later.
5. **Defer:** template composition (`parse`/`include`) for v2.

## Open questions

- **OQ14:** Get a real `.rvt` sample + the installed Rivet version from FlightAware
  to validate the transform, request namespace, and directive set.
- **OQ15:** Is a static `<? ?>`/`<?= ?>` extraction sufficient, or are there other
  Rivet tag forms in use? (Confirm with real templates.)
- **OQ16 (carried, OQ8):** command-vs-variable position classification inside
  stitched template code is the same parser problem as for `.tcl`; the `.rvt`
  stitching must happen before that classification.
