# Document & Workspace Symbols Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `textDocument/documentSymbol` (hierarchical) and `workspace/symbol`, serializing the index's existing symbols (procs, namespace vars, Itcl classes/methods/ivars).

**Architecture:** Add a full-extent range to `Definition`; a pure builder in a new `internal/lsp/symbols.go` turns `source.Defs` into a hierarchical `DocumentSymbol` tree (nested by namespace/class, with `.rvt` `::request` hoisted to root) and enumerates the index for `workspace/symbol`; two thin server handlers + capability advertisement.

**Tech Stack:** Go (server/), standard library. Tests via `go test -C server ./...`.

## Global Constraints

- Go module rooted at `server/`; tests via `go test -C server ./...`.
- Bash: ONE command per call — no `&&`, `|`, `;`, `>>`, `$(...)`.
- Commit trailers (end every commit message with both lines):
  - `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
  - `Claude-Session: https://claude.ai/code/session_01CTr66PbFqDEiS6DXxVy8JV`
- Additive — must not change existing goto-def/ref/reference/OO behavior.
- SymbolKind values (LSP): Namespace=3, Class=5, Method=6, Field=8, Function=12, Variable=13.
- `DocumentSymbol.range` MUST contain `selectionRange`. Skip `DefLocal`/`DefGlobalLink`.
- `.rvt`: hoist `::request`-frame page symbols to the document root (elide the synthetic wrapper).

## Background (current code)

- `tcl/defs.go`: `Definition { Kind DefKind; Name, Namespace string; NameStart, NameEnd, Scope int; Origin string; Class string }`. Kinds: `DefProc, DefNamespaceVar, DefLocal, DefGlobalLink, DefClass, DefMethod, DefIvar`. `emitDefs(c Command, base int, ns string, frame FrameKind, scope int, class string, out *[]Definition)`.
- `source/source.go`: `Defs(path, content) []tcl.Definition` (.rvt → stitched + `ToSource`-translated name ranges).
- `index/index.go`: `defsByName map[string][]Location`; `classes map[string]*ClassInfo` (`DefSites`, `Methods map[string][]Location`, `Ivars map[string][]Location`, `Inherit []string`); `Files()`, `Source(path)`, `Class(fq)`.
- `lsp/protocol.go`: `Position`, `Range`, `Location`, `ServerCapabilities{ TextDocumentSync int; DefinitionProvider, ReferencesProvider bool }`; `uriToPath`/`pathToURI`.
- `lsp/position.go`: `LSPPosition(src string, off int) (line, col int)`.
- `lsp/server.go`: dispatch + handlers; `initialize` advertises capabilities; `sourceOf(path)` returns live-or-indexed source.

## File Structure

- **Modify** `server/internal/tcl/defs.go` — add `FullStart`/`FullEnd` to `Definition`, set in `emitDefs`.
- **Modify** `server/internal/source/source.go` — translate `FullStart`/`FullEnd` for `.rvt` in `Defs`.
- **Modify** `server/internal/lsp/protocol.go` — symbol types, `SymbolKind` consts, params, capabilities.
- **Create** `server/internal/lsp/symbols.go` — the document-symbol tree builder + workspace enumerator/filter (pure).
- **Modify** `server/internal/index/index.go` — `AllSymbols()` enumerator.
- **Modify** `server/internal/lsp/server.go` — two handlers + capability advertisement.
- **Modify** `CLAUDE.md` — scope-note update (Task 8).
- Tests alongside each.

---

### Task 1: Full-extent range on `Definition`

**Files:**
- Modify: `server/internal/tcl/defs.go`, `server/internal/source/source.go`
- Test: `server/internal/tcl/defs_test.go`, `server/internal/source/source_test.go` (or an existing source test file)

**Interfaces:**
- Produces: `Definition.FullStart int`, `Definition.FullEnd int` — the byte range of the whole defining command (`base + firstWord.Start … base + lastWord.End`), set for `DefProc`/`DefNamespaceVar`/`DefClass`/`DefMethod`/`DefIvar` (locals may leave them 0). `source.Defs` translates them to `.rvt` source coords alongside the name range.

- [ ] **Step 1: Write the failing test**

```go
// defs_test.go
func TestFileDefsFullExtent(t *testing.T) {
	src := "proc render {x} {\n  return $x\n}"
	var d *Definition
	for _, def := range FileDefs(src) {
		if def.Kind == DefProc {
			dd := def
			d = &dd
		}
	}
	if d == nil {
		t.Fatal("no DefProc")
	}
	// FullStart at `proc`, FullEnd at the closing brace.
	if src[d.FullStart:d.FullStart+4] != "proc" {
		t.Fatalf("FullStart not at command start: %q", src[d.FullStart:d.FullStart+4])
	}
	if d.FullEnd != len(src) || src[d.FullEnd-1] != '}' {
		t.Fatalf("FullEnd not at closing brace: %d", d.FullEnd)
	}
	if d.FullStart > d.NameStart || d.FullEnd < d.NameEnd {
		t.Fatalf("full range must contain name range")
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/tcl/ -run TestFileDefsFullExtent -v`
Expected: FAIL — `FullStart`/`FullEnd` undefined.

- [ ] **Step 3: Implement**

In `defs.go`: add `FullStart int` and `FullEnd int` to `Definition`. In `emitDefs`, at the top (after `w := c.Words`), compute the command span:

```go
	var cmdStart, cmdEnd int
	if len(w) > 0 {
		cmdStart = base + w[0].Start
		cmdEnd = base + w[len(w)-1].End
	}
```

Set `FullStart: cmdStart, FullEnd: cmdEnd` on every `Definition` literal emitted in `emitDefs` for the symbol kinds: the `proc` case, the decorated-proc case, the `variable`→`DefNamespaceVar` case, the `set`→`DefNamespaceVar` (namespace frame) case, the `DefClass` case, the `itcl::body`→`DefMethod` case, and the `FrameClass` branch's `DefMethod`/`DefIvar` cases. (Local-emitting helpers — params, loop vars, global/upvar links — need not set them.)

In `source.go` `Defs`, the `.rvt` branch currently translates `NameStart/NameEnd`. Also translate the full extent (guard unmapped):

```go
		d.NameStart, d.NameEnd = s, s+(d.NameEnd-d.NameStart)
		if fs := doc.ToSource(d.FullStart); fs >= 0 {
			d.FullEnd = fs + (d.FullEnd - d.FullStart)
			d.FullStart = fs
		} else {
			d.FullStart, d.FullEnd = d.NameStart, d.NameEnd // fall back to name range
		}
```

Add a `source` test that a `.rvt` proc's `FullStart`/`FullEnd` are in source coords and contain the name range.

- [ ] **Step 4: Run + no regressions**

Run: `go test -C server ./internal/tcl/ -run TestFileDefsFullExtent -v`
Then: `go test -C server ./...`
Expected: PASS. Additive fields; existing tests unaffected (note: any test using `reflect.DeepEqual` on whole `Definition`s would now see the new fields — if such a test breaks, update its expected value to include `FullStart`/`FullEnd`; that is expected, not a regression).

- [ ] **Step 5: Commit**

```
git add server/internal/tcl/defs.go server/internal/tcl/defs_test.go server/internal/source/source.go server/internal/source/source_test.go
git commit -m "feat(tcl): add full-extent range to Definition for document symbols"
```
(Append the two required trailers.)

---

### Task 2: Symbol protocol types + capabilities

**Files:**
- Modify: `server/internal/lsp/protocol.go`, `server/internal/lsp/server.go`
- Test: `server/internal/lsp/server_test.go`

**Interfaces:**
- Produces: `SymbolKind` (int) + the constants from Global Constraints; `DocumentSymbol { Name string; Kind SymbolKind; Range, SelectionRange Range; Children []DocumentSymbol }`; `SymbolInformation { Name string; Kind SymbolKind; Location Location; ContainerName string }`; `DocumentSymbolParams { TextDocument TextDocumentIdentifier }`; `WorkspaceSymbolParams { Query string }`. `ServerCapabilities` gains `DocumentSymbolProvider bool` and `WorkspaceSymbolProvider bool`, advertised `true` in `initialize`.

- [ ] **Step 1: Write the failing test**

```go
func TestServerAdvertisesSymbolCapabilities(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "exit", nil, nil))
	resp := responseByID(runServer(t, in.Bytes()), "1")
	var res InitializeResult
	_ = json.Unmarshal(resp.Result, &res)
	if !res.Capabilities.DocumentSymbolProvider || !res.Capabilities.WorkspaceSymbolProvider {
		t.Fatalf("symbol capabilities not advertised: %#v", res.Capabilities)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/lsp/ -run TestServerAdvertisesSymbolCapabilities -v`
Expected: FAIL — fields undefined / not advertised.

- [ ] **Step 3: Implement**

Add the types and `SymbolKind` constants to `protocol.go` (JSON tags: `documentSymbolProvider`, `workspaceSymbolProvider`, `selectionRange`, `containerName`, etc.). Extend `ServerCapabilities` and set both providers `true` in the `initialize` result in `server.go`.

- [ ] **Step 4: Run + no regressions**

Run: `go test -C server ./internal/lsp/ -run TestServerAdvertisesSymbolCapabilities -v`
Then: `go test -C server ./...`
Expected: PASS (existing capability test `TestServerInitializeCapabilities` still passes — definition/references unchanged).

- [ ] **Step 5: Commit**

```
git add server/internal/lsp/protocol.go server/internal/lsp/server.go server/internal/lsp/server_test.go
git commit -m "feat(lsp): symbol protocol types + document/workspace capabilities"
```
(Append the two required trailers.)

---

### Task 3: Document-symbol kind mapping + flat builder

**Files:**
- Create: `server/internal/lsp/symbols.go`
- Test: `server/internal/lsp/symbols_test.go`

**Interfaces:**
- Consumes: `tcl.Definition` (with `FullStart`/`FullEnd`), `LSPPosition`.
- Produces: `symbolKind(k tcl.DefKind) (SymbolKind, bool)` (false = skip) and `buildDocumentSymbols(defs []tcl.Definition, src string) []DocumentSymbol`. THIS task: a FLAT list (no nesting yet) — one `DocumentSymbol` per symbol-kind def, `SelectionRange` from name range, `Range` from full extent (fallback to name range if `FullStart>NameStart`/`FullEnd<NameEnd`/zero), converting byte offsets to `Position` via `LSPPosition`. Skips locals.

- [ ] **Step 1: Write the failing test**

```go
func TestBuildDocumentSymbolsFlat(t *testing.T) {
	src := "proc render {} {}\nitcl::class ::C {}"
	defs := tcl.FileDefs(src)
	syms := buildDocumentSymbols(defs, src)
	byName := map[string]DocumentSymbol{}
	for _, s := range syms {
		byName[s.Name] = s
	}
	if byName["render"].Kind != SymKindFunction {
		t.Fatalf("render kind = %d", byName["render"].Kind)
	}
	if byName["::C"].Kind != SymKindClass {
		t.Fatalf("::C kind = %d", byName["::C"].Kind)
	}
	// range contains selectionRange
	r := byName["render"]
	if posLE(r.Range.Start, r.SelectionRange.Start) == false || posLE(r.SelectionRange.End, r.Range.End) == false {
		t.Fatalf("range must contain selectionRange: %#v", r)
	}
}
```

(Add a tiny `posLE(a, b Position) bool` test helper, or assert on the underlying offsets before conversion — adapt to taste.)

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/lsp/ -run TestBuildDocumentSymbolsFlat -v`
Expected: FAIL — `buildDocumentSymbols`/`symbolKind`/`SymKind*` undefined.

- [ ] **Step 3: Implement**

`symbolKind`: map `DefProc`→Function, `DefMethod`→Method, `DefIvar`→Field, `DefClass`→Class, `DefNamespaceVar`→Variable; `DefLocal`/`DefGlobalLink`→(0,false). `buildDocumentSymbols`: for each def where `symbolKind` returns ok, emit a `DocumentSymbol` with `Name`, `Kind`, `SelectionRange` (name range → Positions), `Range` (full extent → Positions, with the contains-name fallback). Flat for now.

- [ ] **Step 4: Run + no regressions**

Run: `go test -C server ./internal/lsp/ -run TestBuildDocumentSymbolsFlat -v`
Then: `go test -C server ./...`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add server/internal/lsp/symbols.go server/internal/lsp/symbols_test.go
git commit -m "feat(lsp): document-symbol kind mapping + flat builder"
```
(Append the two required trailers.)

---

### Task 4: Nesting — namespace & class tree

**Files:**
- Modify: `server/internal/lsp/symbols.go`
- Test: `server/internal/lsp/symbols_test.go`

**Interfaces:**
- Produces: `buildDocumentSymbols` now returns a hierarchical tree: `DefClass` nodes carry their `DefMethod`/`DefIvar` (matched by `Class == class FQ`) as `Children`; procs / namespace vars / classes nest under a synthesized `Namespace` node per distinct `Namespace`, nested by namespace path; global (`::`) symbols at root. A synthesized namespace node's `Name` is its FQ; its `Range`/`SelectionRange` span its children (selectionRange == range is valid since range ⊇ selectionRange).

- [ ] **Step 1: Write the failing test**

```go
func TestBuildDocumentSymbolsNested(t *testing.T) {
	src := "namespace eval ::app {\n  proc helper {} {}\n}\nitcl::class ::Disp {\n  method field {} {}\n  variable count 0\n}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	app := findSym(syms, "::app")
	if app == nil || app.Kind != SymKindNamespace || findChild(app, "helper") == nil {
		t.Fatalf("::app namespace node with helper child missing: %#v", syms)
	}
	disp := findSym(syms, "::Disp")
	if disp == nil || disp.Kind != SymKindClass {
		t.Fatalf("::Disp class node missing: %#v", syms)
	}
	if findChild(disp, "field") == nil || findChild(disp, "count") == nil {
		t.Fatalf("::Disp method/ivar children missing: %#v", disp.Children)
	}
}
```

Add tree-search helpers to the test file:
```go
func findSym(syms []DocumentSymbol, name string) *DocumentSymbol {
	for i := range syms {
		if syms[i].Name == name {
			return &syms[i]
		}
		if got := findSym(syms[i].Children, name); got != nil {
			return got
		}
	}
	return nil
}
func findChild(s *DocumentSymbol, name string) *DocumentSymbol {
	for i := range s.Children {
		if s.Children[i].Name == name {
			return &s.Children[i]
		}
	}
	return nil
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/lsp/ -run TestBuildDocumentSymbolsNested -v`
Expected: FAIL — flat builder has no nesting; `findChild` finds nothing.

- [ ] **Step 3: Implement**

Refactor `buildDocumentSymbols(defs, src string, hoistRequest bool)`:
1. Build class nodes: for each `DefClass`, a `DocumentSymbol` whose `Children` are the `DefMethod`/`DefIvar` defs with `Class == thatClass.Name`.
2. Group top-level symbols by `Namespace`: classes (the nodes from step 1), procs, namespace vars. Create a `Namespace` `DocumentSymbol` per distinct namespace; nest namespace nodes by path (a `::a::b` node is a child of the `::a` node); attach each namespace's classes/procs/vars as children.
3. Root = global (`::`) symbols + the top-level namespace nodes (parent `::`).
4. Namespace node ranges: min child `Range.Start` … max child `Range.End`; `SelectionRange = Range`.
(The `hoistRequest` parameter is used in Task 5.)

- [ ] **Step 4: Run + no regressions**

Run: `go test -C server ./internal/lsp/ -run TestBuildDocumentSymbols -v`
Then: `go test -C server ./...`
Expected: PASS (flat test from Task 3 still passes — a single global proc is still a root node).

- [ ] **Step 5: Commit**

```
git add server/internal/lsp/symbols.go server/internal/lsp/symbols_test.go
git commit -m "feat(lsp): nest document symbols by namespace and class"
```
(Append the two required trailers.)

---

### Task 5: `.rvt` `::request` hoist

**Files:**
- Modify: `server/internal/lsp/symbols.go`
- Test: `server/internal/lsp/symbols_test.go`

**Interfaces:**
- Produces: when `hoistRequest == true`, a root-level `::request` namespace node is elided and its children promoted to the document root (deeper namespaces/classes nest normally).

- [ ] **Step 1: Write the failing test**

```go
func TestBuildDocumentSymbolsRVTHoist(t *testing.T) {
	// Defs as produced for a .rvt page live in the ::request namespace.
	defs := source.Defs("page.rvt", "<? proc render {} {} ?>")
	syms := buildDocumentSymbols(defs, "<? proc render {} {} ?>", true)
	if findSym(syms, "render") == nil {
		t.Fatalf("render should be hoisted to root: %#v", syms)
	}
	// the ::request wrapper node must not appear at root
	for _, s := range syms {
		if s.Name == "::request" {
			t.Fatalf("::request wrapper should be elided, got %#v", syms)
		}
	}
}
```

(Import `source` in the test file.)

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/lsp/ -run TestBuildDocumentSymbolsRVTHoist -v`
Expected: FAIL — `render` is nested under a `::request` node.

- [ ] **Step 3: Implement**

After building the tree, if `hoistRequest`, find a root node named `::request` (Namespace kind); if present, replace it in the root list with its `Children`.

- [ ] **Step 4: Run + no regressions**

Run: `go test -C server ./internal/lsp/ -run TestBuildDocumentSymbols -v`
Then: `go test -C server ./...`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add server/internal/lsp/symbols.go server/internal/lsp/symbols_test.go
git commit -m "feat(lsp): hoist .rvt ::request page symbols to document root"
```
(Append the two required trailers.)

---

### Task 6: `textDocument/documentSymbol` handler

**Files:**
- Modify: `server/internal/lsp/server.go`
- Test: `server/internal/lsp/server_test.go`

**Interfaces:**
- Consumes: `buildDocumentSymbols`, `source.Defs`, `source.IsRVT`, `sourceOf`.
- Produces: dispatch for `"textDocument/documentSymbol"` → `[]DocumentSymbol`.

- [ ] **Step 1: Write the failing test**

```go
func TestServerDocumentSymbol(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///m.tcl", Text: "proc render {} {}\nitcl::class ::C { method field {} {} }"}}))
	in.Write(frame(t, "textDocument/documentSymbol", 2, DocumentSymbolParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///m.tcl"}}))
	in.Write(frame(t, "exit", nil, nil))
	resp := responseByID(runServer(t, in.Bytes()), "2")
	var syms []DocumentSymbol
	_ = json.Unmarshal(resp.Result, &syms)
	if findSym(syms, "render") == nil || findSym(syms, "::C") == nil || findSym(syms, "field") == nil {
		t.Fatalf("document symbols = %#v", syms)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/lsp/ -run TestServerDocumentSymbol -v`
Expected: FAIL — method unhandled → null result.

- [ ] **Step 3: Implement**

Add to `dispatch`:
```go
	case "textDocument/documentSymbol":
		var p DocumentSymbolParams
		_ = json.Unmarshal(m.Params, &p)
		path := uriToPath(p.TextDocument.URI)
		src := s.sourceOf(path)
		s.reply(m.ID, buildDocumentSymbols(source.Defs(path, src), src, source.IsRVT(path)))
```
(Import `source` in server.go if not already.)

- [ ] **Step 4: Run + no regressions**

Run: `go test -C server ./internal/lsp/ -run TestServerDocumentSymbol -v`
Then: `go test -C server ./...`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add server/internal/lsp/server.go server/internal/lsp/server_test.go
git commit -m "feat(lsp): textDocument/documentSymbol handler"
```
(Append the two required trailers.)

---

### Task 7: Workspace symbols — index enumerator + handler

**Files:**
- Modify: `server/internal/index/index.go`, `server/internal/lsp/symbols.go`, `server/internal/lsp/server.go`
- Test: `server/internal/index/index_test.go`, `server/internal/lsp/server_test.go`

**Interfaces:**
- Produces:
  - `index.SymbolEntry { Name string; Kind tcl.DefKind; File string; NameStart, NameEnd int; Container string }` and `func (ix *Index) AllSymbols() []SymbolEntry` — every proc/namespace-var/class (from `defsByName`, `Name`=simple last segment, `Container`=enclosing namespace FQ) plus every method/ivar (from `classes[*].Methods`/`.Ivars`, `Container`=class FQ).
  - `lsp` handler for `"workspace/symbol"`: filter `AllSymbols()` by case-insensitive substring of `WorkspaceSymbolParams.Query` on `Name`; build `[]SymbolInformation` (`Kind` via `symbolKind`, `Location` via `pathToURI`+`LSPPosition` over `sourceOf(File)`, `ContainerName`).

- [ ] **Step 1: Write the failing test**

```go
// index_test.go
func TestIndexAllSymbols(t *testing.T) {
	ix := New()
	ix.IndexFile("a.tcl", "namespace eval ::app { proc run {} {} }\nitcl::class ::C { method field {} {} }")
	var names = map[string]SymbolEntry{}
	for _, e := range ix.AllSymbols() {
		names[e.Name] = e
	}
	if e, ok := names["run"]; !ok || e.Container != "::app" {
		t.Fatalf("run symbol = %#v", names)
	}
	if e, ok := names["field"]; !ok || e.Kind != tcl.DefMethod || e.Container != "::C" {
		t.Fatalf("field method symbol = %#v", names)
	}
}
```
```go
// server_test.go
func TestServerWorkspaceSymbol(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///a.tcl", Text: "proc render {} {}"}}))
	in.Write(frame(t, "workspace/symbol", 2, WorkspaceSymbolParams{Query: "rend"}))
	in.Write(frame(t, "exit", nil, nil))
	resp := responseByID(runServer(t, in.Bytes()), "2")
	var syms []SymbolInformation
	_ = json.Unmarshal(resp.Result, &syms)
	if len(syms) != 1 || syms[0].Name != "render" || syms[0].Location.URI != "file:///a.tcl" {
		t.Fatalf("workspace symbols = %#v", syms)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/index/ -run TestIndexAllSymbols -v` then `go test -C server ./internal/lsp/ -run TestServerWorkspaceSymbol -v`
Expected: FAIL — `AllSymbols` / handler undefined.

- [ ] **Step 3: Implement**

`index.go`: `AllSymbols` — iterate `defsByName` (skip kinds other than DefProc/DefNamespaceVar/DefClass; `Name` = segment after the last `::`; `Container` = the prefix before it, or `::`); then iterate `classes` (`Methods`/`Ivars`, `Container` = class FQ, `Kind` = DefMethod/DefIvar). `server.go`: add `"workspace/symbol"` dispatch using a `buildWorkspaceSymbols(entries, query, sourceOf)` helper in `symbols.go` that filters + converts to `[]SymbolInformation`.

- [ ] **Step 4: Run + no regressions**

Run the two tests above, then `go test -C server ./...`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add server/internal/index/index.go server/internal/index/index_test.go server/internal/lsp/symbols.go server/internal/lsp/server.go server/internal/lsp/server_test.go
git commit -m "feat(lsp): workspace/symbol via index enumeration"
```
(Append the two required trailers.)

---

### Task 8: Update `CLAUDE.md` scope note

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:** docs only.

- [ ] **Step 1: Edit**

In `CLAUDE.md`, the "Current Phase" section says scope is tight to goto-definition + goto-reference and "Do not propose or scaffold additional LSP features (completion, hover, formatting, diagnostics, rename, etc.)." Update it to record that **document symbols and workspace symbols are now in scope** (a deliberate, index-backed addition), while the *other* features (completion, hover, formatting, diagnostics, rename) remain out of scope. Keep the edit minimal and targeted.

- [ ] **Step 2: Verify**

Run: `go test -C server ./...`
Expected: PASS (docs-only change; sanity that nothing broke).

- [ ] **Step 3: Commit**

```
git add CLAUDE.md
git commit -m "docs(claude): document/workspace symbols now in scope"
```
(Append the two required trailers.)

---

## Self-Review (completed by author)

**Spec coverage:** full-extent ranges (Task 1); protocol types + capabilities (Task 2); document-symbol kind mapping + flat builder (Task 3); namespace/class nesting (Task 4); `.rvt` `::request` hoist (Task 5); the `documentSymbol` handler (Task 6); workspace-symbol enumeration + handler (Task 7); the scope-note doc update (Task 8). All spec sections map to a task.

**Placeholder scan:** none — every task carries a concrete failing test and key implementation code. Task 4 (nesting) is the design-heavy one; its gate is the nested-tree test plus a full-suite run.

**Type consistency:** `Definition.FullStart/FullEnd`, `SymbolKind` + `SymKind*` constants, `DocumentSymbol`/`SymbolInformation`/params, `buildDocumentSymbols(defs, src, hoistRequest)`, `index.SymbolEntry`/`AllSymbols`, and `symbolKind` are used identically across tasks. `range ⊇ selectionRange` is enforced in Task 3 and preserved by the namespace-span choice in Task 4.

**Known notes:** synthesized namespace nodes use a children-span range (no `DefNamespace` exists); the `.rvt` hoist elides only a root `::request` node (deeper structure intact); workspace-symbol matching is server-side substring (client fuzzy-refines), per spec.

