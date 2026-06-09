# Phase B — Plan 04: end-to-end `.rvt` verification + docs

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove goto-definition and find-references work for `.rvt` over the real LSP server (stdio framing, UTF-16 positions, document sync), confirm a cursor in literal HTML resolves to nothing, and mark Phase B shipped in the docs.

**Architecture:** No production code changes — the server already operates in source coordinates, so `.rvt` support rides entirely on the `index`/`resolve` seam from Plans B-02/B-03. This plan adds server-level integration tests (the proof) plus a manual editor smoke test and documentation updates.

**Tech Stack:** Go 1.23+ (local 1.26.4), `testing`; Neovim/Vim for the manual smoke.

**Design basis:** `docs/plans/2026-06-08-phase-b-rvt-design.md` §4.4, §5, §7; depends on Plans B-01..B-03.

---

## File structure

- Modify: `server/internal/lsp/server_test.go` — `.rvt` end-to-end flows.
- Create: `examples/page.rvt` — a self-contained template for the manual smoke test.
- Modify: `README.md` — roadmap/status: Phase B (`.rvt` goto-def/ref) shipped.
- Modify: `editors/README.md` — drop the "`.rvt` is Phase B / not yet" caveat.
- Modify: `CLAUDE.md` — update the stale "Current Phase" section.
- Modify: `docs/plans/2026-06-08-phase-b-rvt-design.md` — status → implemented.

All test commands assume module directory `server/`.

---

## Task 1: Server end-to-end — `.rvt`→`.tcl` and page-local goto-definition

**Files:**
- Modify: `server/internal/lsp/server_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/lsp/server_test.go` (the helpers `frame`, `runServer`, `responseByID` already exist in this file):

```go
func TestServerRVTToTCLDefinition(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///lib.tcl",
			Text: "namespace eval ::lib { proc helper {} {} }"}}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///page.rvt",
			Text: "<? ::lib::helper ?>"}}))
	// cursor on the ::lib::helper call (char 3 = start of the qualified name).
	in.Write(frame(t, "textDocument/definition", 2, TextDocumentPositionParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///page.rvt"},
		Position:     Position{Line: 0, Character: 3}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "2")
	if resp == nil {
		t.Fatal("no definition response")
	}
	var locs []Location
	if err := json.Unmarshal(resp.Result, &locs); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(locs) != 1 || locs[0].URI != "file:///lib.tcl" {
		t.Fatalf("rvt->tcl definition = %#v", locs)
	}
}

func TestServerRVTPageLocalDefinition(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///page.rvt",
			Text: "<? proc greet {} {} ?>\n<? greet ?>"}}))
	// cursor on the greet call on line 1 (char 3).
	in.Write(frame(t, "textDocument/definition", 2, TextDocumentPositionParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///page.rvt"},
		Position:     Position{Line: 1, Character: 3}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "2")
	var locs []Location
	_ = json.Unmarshal(resp.Result, &locs)
	if len(locs) != 1 || locs[0].URI != "file:///page.rvt" {
		t.Fatalf("page-local definition = %#v", locs)
	}
}
```

- [ ] **Step 2: Run the test**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/lsp/ -run TestServerRVT -v`
Expected: PASS (no server change needed; `.rvt` flows through index/resolve).

- [ ] **Step 3: Commit**

```bash
git add server/internal/lsp/server_test.go
git commit -m "test(lsp): end-to-end .rvt goto-definition (cross-file + page-local)"
```

---

## Task 2: Server end-to-end — references include `.rvt`; cursor in literal is empty

**Files:**
- Modify: `server/internal/lsp/server_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/lsp/server_test.go`:

```go
func TestServerReferencesIncludeRVTCallSite(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///lib.tcl", Text: "proc greet {} {}"}}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///page.rvt", Text: "<? greet ?>"}}))
	// references from the proc definition in lib.tcl (cursor on the name, char 5).
	in.Write(frame(t, "textDocument/references", 3, ReferenceParams{
		TextDocumentPositionParams: TextDocumentPositionParams{
			TextDocument: TextDocumentIdentifier{URI: "file:///lib.tcl"},
			Position:     Position{Line: 0, Character: 5}},
		Context: ReferenceContext{IncludeDeclaration: true}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "3")
	var locs []Location
	_ = json.Unmarshal(resp.Result, &locs)
	var inRVT bool
	for _, l := range locs {
		if l.URI == "file:///page.rvt" {
			inRVT = true
		}
	}
	if !inRVT {
		t.Fatalf("references should include the .rvt call site: %#v", locs)
	}
}

func TestServerRVTCursorInLiteralIsEmpty(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///page.rvt", Text: "<h1>title</h1>"}}))
	// cursor inside the literal HTML word "title" (char 5) — no TCL symbol there.
	in.Write(frame(t, "textDocument/definition", 4, TextDocumentPositionParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///page.rvt"},
		Position:     Position{Line: 0, Character: 5}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "4")
	if resp == nil || string(resp.Result) != "null" {
		t.Fatalf("cursor in literal should yield null, got %#v", resp)
	}
}
```

- [ ] **Step 2: Run the test**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/lsp/ -run TestServer -v`
Expected: PASS (all server tests, old and new).

- [ ] **Step 3: Commit**

```bash
git add server/internal/lsp/server_test.go
git commit -m "test(lsp): references span .rvt; cursor-in-literal resolves to nothing"
```

---

## Task 3: Full suite, example template, and docs

**Files:**
- Create: `examples/page.rvt`
- Modify: `README.md`, `editors/README.md`, `CLAUDE.md`, `docs/plans/2026-06-08-phase-b-rvt-design.md`

- [ ] **Step 1: Run the full suite and vet**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server vet ./...`
Then: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./...`
Expected: clean vet; all packages PASS (`rvt`, `source`, `index`, `resolve`, `lsp`, `cmd`, `tcl`).

- [ ] **Step 2: Create the example template**

Create `examples/page.rvt`:

```rvt
<html>
<body>
<?
  # A page-local helper: defined and used within this template (::request scope).
  proc render_title {t} { return "<h1>$t</h1>" }
  set title "Pets"
?>
<?= [render_title $title] ?>
<ul>
<? foreach item {cat dog fish} { ?>
  <li><?= $item ?></li>
<? } ?>
</ul>
</body>
</html>
```

- [ ] **Step 3: Manual editor smoke test**

In Neovim (with the client config from `editors/nvim/tcl-lsp.lua` and a freshly built binary):

1. Open `examples/page.rvt`.
2. Put the cursor on `render_title` inside the `<?= [render_title $title] ?>` line; run goto-definition (`gd`). Expected: jumps to the `proc render_title` line in the same file.
3. With the cursor on the `render_title` definition, run find-references (`gr`). Expected: lists the definition plus the `<?= ?>` call site.
4. Put the cursor on `$title` in the `<?= ?>` line; `gd`. Expected: jumps to the `set title` line.

Record the result (pass/fail) in the commit message or a journal note. (This step is manual; there is no automated assertion.)

- [ ] **Step 4: Update the docs**

In `README.md`, under the Roadmap/Status, note that goto-definition and goto-reference now work for `.rvt` (Rivet) templates as well as `.tcl` (Phase B). Keep it to one or two sentences alongside the existing status block.

In `editors/README.md`, remove the lines stating `.rvt`/Rivet is Phase B / not yet supported (around the current "`.rvt` / Rivet templates are Phase B" note) and instead state that `.rvt` files are supported for goto-definition and goto-reference.

In `CLAUDE.md`, replace the stale "## Current Phase: Research, not implementation" section's body so it reflects reality: Phase A (TCL goto-def/ref) and Phase B (`.rvt` goto-def/ref) are implemented under `server/`; research lives in `research/`, plans in `docs/plans/`. Keep the v1-recovery guidance. Do not re-expand scope beyond the two shipped features.

In `docs/plans/2026-06-08-phase-b-rvt-design.md`, change the `**Status:**` line from `approved design — ready for implementation planning` to `implemented (Plans B-01..B-04)`.

- [ ] **Step 5: Commit**

```bash
git add examples/page.rvt README.md editors/README.md CLAUDE.md docs/plans/2026-06-08-phase-b-rvt-design.md
git commit -m "docs: mark Phase B (.rvt goto-def/ref) shipped; add example template"
```

---

## Done criteria for Plan B-04

- `go -C server vet ./...` clean; `go -C server test ./...` all pass, including the new `.rvt` server flows.
- goto-definition and find-references work for `.rvt` end-to-end over stdio: cross-file `.rvt`→`.tcl`, page-local `::request`, references from a `.tcl` definition include `.rvt` call sites, and a cursor in literal HTML returns null.
- Manual editor smoke test in Neovim passes on `examples/page.rvt`.
- README, `editors/README.md`, `CLAUDE.md`, and the design doc reflect that Phase B shipped — no stale "Phase B not yet" or "Research, not implementation" text remains.

**Phase B is complete:** goto-definition and goto-reference are solid for both `.tcl` and `.rvt`. Deferred items remain documented in the design doc §9 (parse/include edge-following, the `::rivet::` known-commands table, diagnostics/completion/hover).
