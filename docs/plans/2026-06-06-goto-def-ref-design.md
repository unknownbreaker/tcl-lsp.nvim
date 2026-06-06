# Design: goto-definition + goto-reference (v2, Phase A)

**Date:** 2026-06-06
**Status:** approved design — ready for implementation planning
**Research basis:** `research/` (topics 01–06; synthesis in `research/06-synthesis.md`)

## 1. Context & goals

tcl-lsp v1 was reset (see `CLAUDE.md`) after growing too broad and accumulating
intractable performance regressions. The root cause is now identified
empirically: **v1 spawned a `tclsh` subprocess for every parse** (temp file +
JSON round-trip per request — see `archive-v1:lua/tcl-lsp/parser/ast.lua`). That
is architectural, not tunable.

v2 is scoped to two features, built on the verified scope research:
- **goto-definition** and **goto-reference**, for **TCL `.tcl` files (Phase A)**.
- **`.rvt` / Rivet support is Phase B** (fast follow; research already done in
  `research/05-rvt-scope.md`; needs FlightAware confirms gathered in parallel).

**Target TCL version: 8.6** (Rivet baseline). Scope behavior verified identical
on 8.6.18 and 9.0.3 across topics 01–04.

**Non-goals (v2):** completion, hover, diagnostics, rename-as-refactor,
formatting, symbols/outline. None until goto-def + goto-ref are solid.

## 2. Architecture decision

A **standalone LSP server, written in Go, speaking LSP over stdio.**

Rationale (from brainstorming):
- **Must support both Vim and classic Vim + Neovim.** Classic Vim cannot run an
  in-process Lua/Neovim plugin, so the only mechanism both editors share is a
  standalone LSP server that each editor's LSP client connects to.
- **Go** for: gentle learning curve, fast parser development, **trivial
  cross-compilation** (`GOOS`/`GOARCH` → static binaries for macOS/Linux/Windows,
  no runtime dependency on the user's machine), and a first-class LSP ecosystem
  (gopls is Go; `go.lsp.dev/protocol`). A 2-feature v2 ships fastest here.
- The v1 perf trap (spawn-per-parse) is gone by construction: the server is **one
  long-lived process** holding an in-memory index.

**Clients:** Neovim via built-in `vim.lsp` (`vim.lsp.config` + `vim.lsp.enable`);
Vim via an LSP-client plugin (`vim-lsp` recommended; `coc.nvim`/`ALE` also work).
Each is a small registration snippet shipped with the project.

### Decoupled core vs. protocol shell (key structural principle)
- **Core** (pure Go; no protocol, no editor): tokenizer → structural parser →
  resolver → indexer. Unit-testable in isolation.
- **Protocol shell** (separate package): JSON-RPC/stdio, lifecycle, document
  sync, position encoding. Knows nothing about TCL semantics.

This keeps resolution logic testable on its own and lets the protocol layer
evolve without touching the core.

## 3. The resolution model (summary; full detail in `research/06-synthesis.md`)

Resolution is selected by **syntactic position**, classified first:

- **Command position:** resolve current namespace → each `namespace path` entry →
  global `::`. Never walks ancestor namespaces.
- **Variable position:** **frame-kind dependent.** Inside a `proc` body, a bare
  name is **local only** (else needs `global`/`variable`/`upvar`/fully-qualified);
  at `namespace eval` top level, a bare name is the namespace's own variable.
  `namespace path` does **not** apply to variables.
- **Qualified names:** leading `::` = absolute; otherwise relative to current
  namespace.

**Definition sites** (goto-def targets): `proc NAME body` (primary), `namespace
import` aliases (best-effort jump-through), `variable`/qualified `set` for
namespace vars, params/`set` for locals, top-level `set`/`global` for globals. A
single name may have **multiple** definition sites (redefinition / conditional /
namespace opened across files) — return all.

**Workspace model:** namespaces span files (a namespace is not a module). Index
**every** `*.tcl` by globbing; build one symbol table keyed by fully-qualified
name. Do **not** chase `source`/`package` edges for naming (paths are dynamic).
The LSP is intentionally more permissive than the runtime (assumes all workspace
defs are "loaded"); external symbols (Tcllib, etc.) resolve to "no definition".

## 4. Components

**Core (pure Go, no cgo):**
1. **Tokenizer** — TCL-aware lexing: `{}` bracing, `""` quoting, `[]` command
   substitution, `$` var refs, `#` comments, `\`-continuation, `;`/newline
   separators. Tokens carry byte offsets.
2. **Structural parser** — tokens → commands+words; recognizes scope-relevant
   commands (`namespace eval`, `proc`, `set`, `variable`, `global`, `upvar`,
   `namespace path`/`export`/`import`); tracks current namespace + frame kind.
   Output = the **parser→resolver contract** (research Part 8): per identifier
   `{text, position-kind (command|variable), byte-range, enclosing-namespace,
   frame-kind}`, plus per-file namespace structure and definition/reference lists.
   Not a full AST — only what goto-def/ref needs.
3. **Resolver** — the command + variable algorithms above.
4. **Indexer / symbol table** — workspace-wide, FQ-keyed; two-phase (collect all
   defs, then resolve refs on demand); incremental per-file updates.

**Protocol shell (separate package):**
5. **LSP server** — JSON-RPC over stdio; lifecycle (`initialize`/`shutdown`);
   document sync (`didOpen`/`didChange`/`didClose`); **UTF-16 position
   encoding**; file watching. Maps `textDocument/definition` + `references` onto
   the core; formats responses.

**Client glue:**
6. Registration snippets for Neovim (`vim.lsp.config`) and Vim (`vim-lsp`).

## 5. Parser strategy

**Hand-written, pure-Go tokenizer + structural parser, scoped to the resolver
contract** — not a general TCL parser.

Rejected: **tree-sitter-tcl**, because it requires cgo, which undermines Go's
trivial cross-compilation (the main reason for choosing Go). TCL is also hard to
parse statically (dynamic/contextual), any grammar is approximate, and `.rvt`
needs custom handling regardless. We may reference v1's TCL tokenizer design
(`archive-v1:tcl/core/tokenizer.tcl`) for tricky quoting/bracing rules.

## 6. Data flow

- **Startup:** `initialize` → workspace root → glob `**/*.tcl` → tokenize+parse
  each → Phase 1: collect all definitions into the FQ table → ready. References
  resolve on demand at request time against the current table.
- **goto-definition:** token at cursor → classify + current namespace + frame
  kind → compute FQ candidate(s) → look up all definition sites → return
  `Location[]` (URI + range, UTF-16). Multiple sites returned together.
- **goto-references:** resolve cursor to its FQ definition → scan all reference
  *occurrences* (the parser records every identifier occurrence per file),
  resolve each, and return those resolving to that FQ name — including linking
  statements (`global`, `variable`, qualified `set`, import aliases). (The
  occurrence list is indexed; resolving occurrences to FQ targets happens at
  request time — see §7.)
- **On edit (`didChange`/`didSave`):** update in-memory doc → re-parse **only
  that file** → swap that file's def/ref set in the index.

## 7. Incremental indexing & performance

- Parse **in-process, in-memory, once**; never spawn per parse (the v1 fix).
- An edit costs **O(size of changed file)**: remove that file's old defs from the
  FQ map, add new ones, leave other files untouched.
- References resolve **lazily at request time** against the current map → no
  whole-workspace re-resolution on a keystroke.
- goto-references scans references (explicit, infrequent action — acceptable; a
  reverse index is an easy later optimization).
- `didChange` debounced / parsed on idle.

## 8. Error handling & robustness

- **Tolerant parser:** mid-edit incomplete code is the normal case — never crash;
  best-effort structure; skip unparseable regions, don't abort the file (opposite
  of v1's hard-fail + 10s timeout).
- **Never block the editor:** requests answered from the in-memory index.
- **Unresolved name → empty result**, not an error (expected for external
  symbols).
- **No silent failures:** parse/index errors are logged (so an empty goto-def
  from a parse gap is diagnosable), never swallowed to look like success.

## 9. Testing strategy

- **Golden oracle — `namespace which`:** the research established it returns TCL's
  own ground-truth resolution. The harness runs real `tclsh 8.6` on each fixture,
  captures what `namespace which -command/-variable` resolves a symbol to, and
  asserts our resolver produces the same FQ name. Validates the resolver against
  the actual interpreter.
- Pure-Go unit tests per module (tokenizer, parser contract, resolver, indexer) —
  fast, no editor.
- Resolver cases drawn **directly from verified findings** in experiments 01–04
  (each finding → a test).
- Integration: drive the server over stdio with real LSP messages; assert
  `Location`s including UTF-16 positions.
- Editor smoke test in both nvim and vim.
- **TDD:** resolver tests written from the research before implementation.

## 10. Phase A build order

1. Scaffold: Go module, `core/` vs `lsp/` packages, CI for cross-compiled builds.
2. Tokenizer + tests.
3. Structural parser → resolver contract + tests.
4. Resolver (two algorithms) + tests vs findings + `namespace which` oracle.
5. Workspace indexer (FQ table, two-phase) + tests.
6. goto-definition end-to-end (core) + tests.
7. goto-references end-to-end (core) + tests.
8. Protocol shell: JSON-RPC/stdio, lifecycle, doc sync, UTF-16 encoding; wire the
   two methods.
9. Client configs (nvim + vim) + manual smoke test.
10. Cross-compiled binaries + install docs.

## 11. Scope boundary (carried from `research/06-synthesis.md` Part 5)

**In scope (Phase A):** proc/command goto-def+ref with full qualification +
`namespace path`; variable goto-def+ref for locals/params/`global`/`variable`/
qualified namespace vars with frame-kind-correct resolution; cross-file
resolution within shared namespaces; multiple definition sites returned together.

**Best-effort:** `namespace import` alias jump-through.

**Deferred (documented limitations, surface nothing wrong):** `upvar`/`uplevel`
dynamic targets; `rename`; `interp alias`; `namespace ensemble`; dynamic/
conditional/`eval`-constructed defs; external packages; following
`source`/`package` for naming.

**Phase B (next):** `.rvt`/Rivet — stitched template parsing, `::request` scope,
`.rvt` position mapping, `::rivet::` known-commands table, `parse`≈`source`.
Pending FlightAware confirms: production Rivet version, a representative `.rvt`,
house conventions, app bootstrap.

## 12. Open questions for the implementation plan

- Command-vs-variable position classification is the parser's hardest job
  (research OQ8); the tokenizer/parser design must center it.
- Workspace file discovery details: globbing, vendored dirs, `.gitignore`, perf
  on large trees (research OQ12).
- Multiple-definition UX: confirm "always return all sites".
- Go LSP library choice (`go.lsp.dev/protocol` vs hand-rolled JSON-RPC).
- Reverse-index for goto-references: defer vs include in Phase A.
