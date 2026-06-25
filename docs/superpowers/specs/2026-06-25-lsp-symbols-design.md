# Document & Workspace Symbols — Design

**Date:** 2026-06-25
**Status:** Approved (user delegated design; proceeding to implement).
**Scope:** Adds `textDocument/documentSymbol` and `workspace/symbol` — the first
LSP features beyond goto-definition / goto-reference. A deliberate, cheap scope
expansion: both are serializations of the symbol data the index already holds.

## Motivation

The index already knows every workspace symbol — procs, namespace variables, Itcl
classes, methods, and instance variables — with kind, name, and location. Two LSP
requests expose that for free-feeling, high-daily-value navigation:

- **Document symbols** → the file outline, breadcrumbs, sticky-scroll, and the
  in-file symbol picker.
- **Workspace symbols** → fuzzy "jump to any symbol in the project."

No new analysis (no resolution, type inference, or dataflow) — only presentation.

## Scope

**In scope:**
- `textDocument/documentSymbol` — hierarchical `DocumentSymbol[]` for a file.
- `workspace/symbol` — flat symbol search across the workspace.
- Capability advertisement for both.
- A `CLAUDE.md` scope-note update (these are deliberate additional features).

**Out of scope (non-goals):**
- Completion, hover, diagnostics, rename, formatting, code actions, semantic
  tokens, inlay hints — still excluded.
- Symbol *renaming* or any edit operation.
- Locals (`DefLocal`/`DefGlobalLink`) as symbols — not outline-worthy.

## Symbol kinds

LSP `SymbolKind` (numeric enum) mapping:

| Definition kind | SymbolKind | value |
| --- | --- | --- |
| `DefProc` | Function | 12 |
| `DefMethod` | Method | 6 |
| `DefIvar` | Field | 8 |
| `DefClass` | Class | 5 |
| `DefNamespaceVar` | Variable | 13 |
| (synthesized namespace node) | Namespace | 3 |

`DefLocal` / `DefGlobalLink` are skipped.

## Ranges (the one data addition)

`DocumentSymbol` requires two ranges:
- **`selectionRange`** — the name token. Already available as `Definition.NameStart/NameEnd`.
- **`range`** — the symbol's *full extent* (the whole `proc … { … }` / `itcl::class … { … }`).
  Not currently on `Definition`. It is cheap to derive: the enclosing command's word
  span, `base + firstWord.Start … base + lastWord.End`. We add `FullStart`/`FullEnd`
  to `Definition`, set in `emitDefs` from the command's words. This is additive and
  behavior-neutral (existing consumers ignore the new fields).

`range` must contain `selectionRange` (LSP requirement) — the command span always
contains its name token, so this holds.

## Document symbols — hierarchy

Build a tree from the flat `source.Defs(path, src)` list (which is `.rvt`-translated
and in source coordinates):

- **Namespace nodes** are synthesized from each def's `Namespace` field. A namespace
  with symbols becomes a `Namespace` node; nested namespaces (`::a::b`) nest by path.
  Global (`::`) symbols sit at the document root.
- **Class nodes** (`DefClass`) sit under their namespace; their `DefMethod`/`DefIvar`
  (matched by the `Class` field) nest under the class node.
- Procs / namespace vars sit under their namespace node (or root if global).
- A namespace node's `range`/`selectionRange` covers the `namespace eval` extent when
  available; if a namespace is only synthesized (no explicit decl captured), use the
  span of its children as `range` and the first child's name as `selectionRange`
  (a pragmatic, valid choice).

### `.rvt` wrapper handling
A `.rvt` page is stitched into `namespace eval ::request { … }`, so page symbols carry
`Namespace == "::request"` (or `::request::*`). Presenting a `::request` node leaks the
synthetic wrapper. **Decision:** for `.rvt` documents, symbols directly in `::request`
are **hoisted to the document root** (the wrapper node is elided); deeper namespaces and
classes nest normally. The page reads as "these are my page's procs/classes," not
"everything is under ::request."

## Workspace symbols

`workspace/symbol` takes a query string and returns a flat list:
- Enumerate the index: every `defsByName` entry (procs, namespace vars, classes) plus
  every `classes[*].Methods` / `.Ivars`.
- Each result: `name` (the symbol's simple name), `kind`, `location` (file + name
  range → line/col via the file's stored source), and `containerName` (the enclosing
  namespace for procs/vars/classes; the class FQ for methods/ivars).
- **Matching:** case-insensitive substring on the simple name (the client fuzzy-refines;
  the server is permitted to return a superset/subset). An empty query returns all
  (clients send a prefix as you type).

## Architecture / components

- **`internal/tcl` (`defs.go`):** add `FullStart`/`FullEnd` to `Definition`; set in
  `emitDefs` from the command word span. (Behavior-neutral.)
- **`internal/lsp` (`protocol.go`):** `DocumentSymbol`, `SymbolInformation`/
  `WorkspaceSymbol`, `SymbolKind` constants, `DocumentSymbolParams`,
  `WorkspaceSymbolParams`; extend `ServerCapabilities`.
- **`internal/lsp` (a new `symbols.go`):** the document-symbol tree builder (defs →
  hierarchical `DocumentSymbol`, with the `.rvt` hoist) and the workspace-symbol
  enumerator/filter. Pure functions over `source.Defs` / the index, kept out of
  `server.go` so the handlers stay thin.
- **`internal/lsp` (`server.go`):** two handlers + capability advertisement.
- **`internal/index`:** a method to enumerate all workspace symbols (name, kind, FQ,
  location, container) for `workspace/symbol`.

## Error handling / edge cases

- A document with no symbols → empty list (not an error).
- Unknown / never-opened document for `documentSymbol` → use the indexed source if
  present, else empty.
- `range` must contain `selectionRange`; guaranteed by construction (command span ⊇
  name token).
- Synthesized namespace nodes with no explicit decl use children's span — never a
  zero/invalid range.

## Testing

- **`tcl`:** `FullStart`/`FullEnd` cover the whole command (proc/class/variable).
- **`lsp` (symbols.go unit):** kind mapping; flat → hierarchical nesting (class →
  methods; namespace → procs); `.rvt` `::request` hoist; workspace enumeration +
  substring filter + containerName.
- **`lsp` (server end-to-end):** `textDocument/documentSymbol` returns the right tree
  for a `.tcl` and a `.rvt`; `workspace/symbol` returns matches across files with
  correct kind/location/container; capabilities advertised.

## Phasing

One plan, two milestones:
- **Phase A — document symbols:** ranges data, protocol/caps, builder, nesting,
  `.rvt` hoist, handler.
- **Phase B — workspace symbols:** index enumerator, handler.
Each task independently testable; A ships a usable outline before B.

## Decisions log

- Hierarchical `DocumentSymbol` (not flat `SymbolInformation`) for document symbols.
- Full `range` via a new `Definition.FullStart/FullEnd` from the command word span
  (not degraded name-only ranges).
- Nest by `Namespace`/`Class`; hoist `.rvt` `::request` page symbols to root.
- Workspace symbols: flat, index-enumerated, server-side substring + client refine.
- Skip locals. Update `CLAUDE.md` scope note.

## Risks / open questions

- **Deep namespace trees** (`::a::b::c`): build the full nested path; if it proves
  fiddly, a single level per distinct namespace is an acceptable fallback (flag in the
  plan). Either is valid LSP output.
- **`.rvt` page-local vs shared symbols:** `::request::*` are page-local; hoisting them
  to root is the intended presentation. Symbols a `.rvt` pulls from `.tcl` packages are
  not in the `.rvt`'s own def list, so they correctly don't appear in its outline.
- **Client capability negotiation:** advertise hierarchical document symbols; Neovim
  0.11 and modern clients support it. (No flat fallback needed for the target editors.)
