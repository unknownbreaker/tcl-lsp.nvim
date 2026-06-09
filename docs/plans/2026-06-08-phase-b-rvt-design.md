# Design: goto-definition + goto-reference for `.rvt` (v2, Phase B)

**Date:** 2026-06-08
**Status:** implemented (Plans B-01..B-04)
**Research basis:** `research/05-rvt-scope.md` (Rivet model resolved from official
Apache Rivet docs + faithful simulator); Phase A design
`docs/plans/2026-06-06-goto-def-ref-design.md`.

## 1. Context & goals

Phase A delivered goto-definition + goto-reference for TCL `.tcl` files: a
standalone Go LSP server with a format-agnostic core (tokenizer → structural
parser → resolver → indexer) behind a JSON-RPC/stdio protocol shell. Phase B
extends those same two features to **`.rvt` (Apache Rivet) templates**, with full
cross-file resolution between `.rvt` and `.tcl`.

A `.rvt` file is HTML/text with embedded TCL in `<? … ?>` blocks (and the `<?= …
?>` output shorthand). Rivet compiles the whole file into one TCL script and
evaluates it per request via `namespace eval ::request $script` (research 05).
Production templates at FlightAware are **mixed**: some are one large `<? … ?>`
block with a little HTML; others are heavily interleaved, with control structures
(`foreach`/`if`) spanning multiple `<? ?>` blocks. The design must handle both.

**Constraint:** production `.rvt` files cannot be shared with outside tools
(company policy). The design is therefore validated against the documented Rivet
transform, the faithful simulator already in `research/experiments/05_rvt/`, and
synthetic fixtures — not against real templates.

**Non-goals (carried from Phase A):** completion, hover, diagnostics, rename,
formatting, symbols/outline. Phase B adds **no** new LSP features — only `.rvt`
coverage of the existing two.

## 2. Architecture decision

Add **one new frontend package, `server/internal/rvt`**, that converts `.rvt`
bytes into a **stitched virtual TCL document plus a bidirectional position map.**
The entire Phase A core runs **unchanged** on the virtual document; RVT-awareness
lives only in this adapter and at three thin integration seams (index, resolver
frame-seeding, LSP boundary translation).

Rationale:
- **Preserves the decoupled core.** The Phase A design's central structural
  principle is a format-agnostic core. RVT support is an *adapter in front of* the
  core, not a modification *to* it — the proven `.tcl` path never changes.
- **The stitched regions are verbatim TCL** (we drop literals but never rewrite
  code), so the offset map is piecewise-linear: each `<? ?>` region is one segment
  with a constant offset delta. Translation is a binary search over a handful of
  segments, not a general source map.
- **Additive risk profile.** Almost all new complexity is quarantined in one
  unit-testable package.

Rejected alternatives:
- **RVT-aware tokenizer** (teach the core tokenizer to skip HTML and lex only
  inside `<? ?>`): tokens would carry native `.rvt` offsets with no map, but it
  couples the core to a template format and risks regressing the verified `.tcl`
  path. It inverts the dependency the Phase A design deliberately chose.
- **Sentinel substitution** (replace literals with equal-byte-length TCL comments
  so offsets stay 1:1): fragile against HTML containing `?>` and against UTF-16 vs
  byte-length accounting for LSP position encoding.

## 3. The resolution model

Resolution reuses Phase A unchanged, with one frame-seeding rule and one
scoping rule for template-level symbols.

### Frame seeding: template top level runs in `::request`
The stitched script's top level is treated as if enclosed in `namespace eval
::request { … }`. The context walker therefore assigns enclosing-namespace
`::request` and namespace-top-level frame semantics to template-top-level code: a
bare `proc foo {}` defines `::request::foo`; a bare `set x` defines
`::request::x` (research 05 V2; namespace-top-level variable rules from research
01/04). Code inside a `proc` body in a template behaves exactly as in `.tcl`
(locals, `global`, `variable`, `upvar`, qualified names).

### Scoping: `::request` symbols are page-local
`::request` is recreated and destroyed per request, so a bare symbol defined in
one `.rvt` is not visible to another at runtime. The resolver enforces this: when
a candidate fully-qualified name falls under `::request::*`, **only definitions
from the same file are considered.** Namespaced and global symbols are untouched —
a proc defined in a `.tcl` namespace (or `::`) resolves and finds references
across the whole workspace, including every `.rvt` call site, exactly as in
Phase A.

> **Deferred:** `::rivet::parse` / `::rivet::include` compose multiple templates
> into one request, which *can* make a bare helper genuinely shared across pages.
> Following those edges (parse-chain sharing) is deferred — page-local is the safe,
> accurate default for the common case (shared code lives in `.tcl` namespaces).
> Revisit if real usage shows templates share bare helpers via composition.

## 4. Components

### 4.1 `rvt.Extract(src) → Document` — the core new unit
Pure function; no protocol, no index. Returns a `Document`:
- `Script` — the stitched TCL: the bodies of every `<? … ?>` and `<?= … ?>`
  region, in source order, newline-separated. Literal (non-tag) text is dropped —
  it is opaque output and contains no TCL symbols.
- `Mapping` — an ordered list of `Segment{VirtOff, SrcOff, Len}`, one per emitted
  region. Verbatim regions ⇒ piecewise-linear map.
- `ToSource(virtOff) int` — virtual-doc offset → `.rvt` source offset.
- `ToVirtual(srcOff) (int, bool)` — `.rvt` source offset → virtual-doc offset;
  `ok=false` when the offset falls in a literal (non-TCL) region.

Both translations are binary searches over `Mapping`.

**Extraction rules (research 05):**
- `<? code ?>` → emit `code` verbatim; record a segment mapping its bytes to their
  `.rvt` offsets.
- `<?= expr ?>` → emit the inner expression so its `$var` / `[cmd]` symbols parse
  as references. We need *reference-correct* parsing, not runtime-correct output
  (`<?= ?>` is a `puts` of the value at runtime; for goto-def/ref we only care
  that the contained symbols are seen).
- Regions are newline-joined so control structures that **span blocks** still
  brace-balance as one script. Example:

  ```
  <? foreach it $items { ?>
    <li><?= $it ?></li>
  <? } ?>
  ```

  stitches to:

  ```
  foreach it $items {
  $it
  }
  ```

  The literal `<li>…</li>` is dropped; the `foreach`, `it`, `$items`, and the
  `<?= $it ?>` reference all land in the right structural positions.

### 4.2 Index integration
- `IndexDir` walks `*.rvt` in addition to `*.tcl`.
- `IndexFile` detects `.rvt` by suffix → `rvt.Extract` → parse the resulting
  `Script` → as each definition/reference byte-range is recorded, map its virtual
  offset back through `Document.ToSource` so stored `Location`s point into the
  `.rvt`. The FQ symbol table is otherwise unchanged.
- The per-file `Document` (its `Mapping`) is retained in the index alongside the
  source, for request-time cursor translation.

### 4.3 Resolver
Implements §3: `::request` frame seeding for `.rvt` top level, and the
page-local restriction for `::request::*` candidates. No change to command/
variable algorithms, namespace-path/import resolution, or cross-file lookup.

### 4.4 LSP server integration
- `.rvt` buffers already attach the server (editor configs ship `.rvt` filetype
  registration and an `rvt` allowlist; see `editors/`).
- `didOpen` / `didChange` for `.rvt` extract + parse like the index and retain the
  per-document mapping (see §5).
- Request flow (`textDocument/definition`, `textDocument/references`): incoming
  cursor `(line, char)` → `.rvt` byte offset → `Document.ToVirtual` → virtual
  offset → core resolves → result `Location`s are already `.rvt`-mapped (from
  indexing) → translate `.rvt` byte offsets back to UTF-16 `(line, char)` for the
  response.
- Cursor in a literal (HTML) region → `ToVirtual` returns `ok=false` → empty
  result (not an error).

### 4.5 `::rivet::` known-commands table — DEFERRED
Not needed for goto-def/ref: an unindexed `::rivet::foo` correctly resolves to "no
definition" (it is an external, C/Tcl-provided command). The catalog captured in
research 05 [D] only benefits diagnostics/completion, which are out of scope.

## 5. Data flow

- **Startup:** glob `**/*.tcl` + `**/*.rvt`; for each `.rvt`, extract → parse
  stitched `Script` → map defs back to `.rvt` offsets → into the FQ table.
- **goto-definition in `.rvt`:** cursor → `.rvt` offset → virtual offset →
  classify + frame(`::request`) + namespace → FQ candidate(s) → look up all
  definition sites → `Location[]` (into `.rvt` or `.tcl`) → UTF-16.
- **goto-references:** resolve cursor to its FQ definition → scan all reference
  occurrences across `.tcl` **and** `.rvt` (each mapped to its source) → return
  those resolving to that FQ name.

### Incremental updates & map freshness
Phase A uses **full-document sync**: every `didChange` carries the entire new
buffer text, and `setDoc` → `IndexFile` re-indexes the whole file (a file is the
unit of update; there is no sub-file incremental parse). Phase B keeps this model.

- On every `.rvt` change, `rvt.Extract` runs on the new full text, producing a
  **fresh `Document` — new `Script` and new `Mapping`.** The file is re-parsed and
  its definitions, references, **and** mapping are swapped as a unit in one
  `IndexFile` call. The old map is discarded wholesale; maps are never patched
  in place.
- **Invariant:** a file's mapping and its stored defs/refs are always derived from
  the same text snapshot and replaced together. They cannot drift apart — this
  sidesteps the incremental-source-map bug (offsets computed against old text,
  applied to new text).
- The server's `sourceOf` prefers live buffer text over the indexed copy; because
  `setDoc` re-indexes synchronously with that exact text, the stored mapping always
  matches the live buffer, so request-time cursor translation uses a map
  consistent with the text the cursor is in.
- Extraction is O(file size) — one linear pass in front of the existing linear
  parse pass; the update granularity (whole file) is unchanged from Phase A.

## 6. Error handling & robustness

- **Tolerant extraction:** an unterminated `<?` (no closing `?>`, the normal
  mid-edit state) → emit the remainder to EOF as a code region, log, never crash.
- Cursor in a literal region → empty result (`ToVirtual` `ok=false`).
- Malformed stitched TCL → the existing tolerant parser skips unparseable regions;
  the file is not aborted.
- Everything is answered from the in-memory index; never block the editor.
- **No silent failures:** extraction/parse anomalies are logged so an empty
  goto-def from an extraction gap is diagnosable.

## 7. Testing strategy

- **`rvt` package unit tests:** extraction + offset round-trips (an offset inside a
  code region maps to the correct `.rvt` byte and back); control-flow spanning
  blocks; `<?= ?>` regions; unterminated tag; empty file; file with no tags; `?>`
  appearing inside literal HTML.
- **Resolver tests (from research findings):** bare `.rvt` top-level proc/var →
  `::request::*`, page-local; `.rvt` call → `.tcl` namespaced definition
  (cross-file); two pages each defining the same bare helper name → **no**
  cross-matches; references from a `.tcl` definition include `.rvt` call sites.
- **Position-mapping integration:** define in `.tcl`, reference in `.rvt` →
  goto-def returns the correct `.rvt` range (and the reverse), UTF-16-correct.
- **End-to-end:** drive the server over stdio with synthetic `.rvt` fixtures;
  assert `Location`s including UTF-16 positions.
- **Stitching oracle:** Rivet is not installed, but
  `research/experiments/05_rvt/rivet_sim.tcl` is a faithful simulator of the
  documented transform. Use it as the oracle — assert the extractor's region
  extraction matches the simulator's transform on shared fixtures.
- **TDD:** resolver and extractor tests written from the research before
  implementation.

## 8. Build order (for the implementation plans)

1. `rvt` extractor + position map + unit tests (pure; no integration).
2. Index integration: discover + extract + map-back; FQ table includes `.rvt`.
3. Resolver: `::request` page-local frame-seeding; cross-file `.rvt` ↔ `.tcl`.
4. LSP server: in-memory `.rvt` docs + boundary position translation; wire the two
   methods for `.rvt`.
5. `.rvt` editor smoke test (nvim + vim) + docs update (README / `editors` note
   Phase B shipped).

## 9. Scope boundary

**In scope (Phase B):** goto-def + goto-ref in `.rvt`; cross-file `.rvt` ↔ `.tcl`
resolution; interleaved `<? ?>` blocks with control structures spanning them;
`<?= ?>` output regions; page-local `::request` frame for template-top-level
symbols.

**Deferred (documented limitations; surface nothing wrong):**
- `::rivet::parse` / `::rivet::include` edge-following (parse-chain symbol
  sharing across composed templates).
- The `::rivet::` known-commands table (research 05 [D]) — only useful for
  diagnostics/completion.
- Diagnostics, completion, hover, rename, formatting (Phase A non-goals, unchanged).
- Runtime-accurate output semantics (`<?= ?>` as `puts`, literal text as output) —
  we model references, not rendering.

## 10. Open questions for the implementation plan

- `<?= expr ?>` emission: confirm emitting the inner text verbatim as one stitched
  line parses its symbols correctly for all reference kinds (bare `$var`, `[cmd]`,
  qualified names); decide whether any wrapping is needed.
- Page-local enforcement mechanism: confirm "restrict `::request::*` candidates to
  same-file definitions at resolve time" is the cleanest implementation vs.
  per-file keying in the index.
- `Document` storage: store the full `Document` in the index vs. just the
  `Mapping` plus stitched `Script`.
