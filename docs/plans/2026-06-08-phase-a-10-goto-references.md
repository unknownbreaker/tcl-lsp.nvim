# Phase A — Plan 10: goto-references (cross-file)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Given a cursor offset, find all workspace references to the same symbol — the goto-references feature.

**Architecture:** Extends the `resolve` package (see `docs/plans/2026-06-06-goto-def-ref-design.md`). Computes the cursor symbol's fully-qualified name (from a definition name-range or by resolving a reference), then scans every indexed file's `tcl.FileRefs`, resolving each to its FQ name and collecting those that equal the target — using the same first-match precedence as goto-definition. The current file is scanned with the live `src` (so unsaved edits are honored).

**Scope + documented deferrals:** Covers references to commands and namespace/qualified variables. Deferred: bare proc-local variables (return none); **bareword variable-name arguments** like `set x ...` / `incr x` (only `$`-substitution uses are captured); `namespace path`; and the declaration site itself is not returned among "references" (it is reachable via goto-definition).

**Tech Stack:** Go 1.23+ (local 1.26.4), `strings`, `testing`.

---

## File structure

- Modify: `server/internal/resolve/resolve.go` — add `References`, `targetFQ`, `refFQ`.
- Modify: `server/internal/resolve/resolve_test.go` — tests.

Reuses `candidates`/`refAt` (Plan 9), `index.Index.Files`/`Source`/`Lookup`, `tcl.FileRefs`/`FileDefs`.

---

## Task 1: References for commands across files

**Files:**
- Modify: `server/internal/resolve/resolve.go`
- Modify: `server/internal/resolve/resolve_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/resolve/resolve_test.go`:

```go
func TestReferencesCommandAcrossFiles(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "proc greet {} {}")
	ix.IndexFile("a.tcl", "greet")
	ix.IndexFile("b.tcl", "greet\ngreet")
	r := New(ix)

	// Cursor on the call in a.tcl. The proc-name token in lib.tcl is a
	// definition, not a reference, so it is not counted.
	locs := r.References("a.tcl", "greet", 0)
	if len(locs) != 3 {
		t.Fatalf("expected 3 reference uses, got %#v", locs)
	}
}

func TestReferencesFromDefinition(t *testing.T) {
	ix := index.New()
	libSrc := "proc greet {} {}"
	ix.IndexFile("lib.tcl", libSrc)
	ix.IndexFile("a.tcl", "greet")
	r := New(ix)

	// Cursor on `greet` in the proc definition name (offset 5).
	locs := r.References("lib.tcl", libSrc, 5)
	if len(locs) != 1 || locs[0].File != "a.tcl" {
		t.Fatalf("expected 1 ref in a.tcl, got %#v", locs)
	}
}

func TestReferencesUnknownIsEmpty(t *testing.T) {
	r := New(index.New())
	if locs := r.References("a.tcl", "set x 1", 100); locs != nil {
		t.Fatalf("no symbol at offset should be nil, got %#v", locs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ -run TestReferences`
Expected: FAIL — compile error, `References` undefined.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/resolve/resolve.go`, add `"github.com/unknownbreaker/tcl-lsp/internal/tcl"` if not already imported (it is, from Plan 9), and add:

```go
// References returns all workspace references to the symbol at byte offset in
// src. The current file is scanned with the live src; other files use the
// indexed source. Only command and namespace/qualified-variable references are
// matched; bare proc-locals and bareword variable-name arguments are not.
func (r *Resolver) References(file, src string, offset int) []index.Location {
	target := r.targetFQ(file, src, offset)
	if target == "" {
		return nil
	}
	var targetKind tcl.DefKind
	if defs := r.ix.Lookup(target); len(defs) > 0 {
		targetKind = defs[0].Kind
	}

	var out []index.Location
	scan := func(f, s string) {
		refs := tcl.FileRefs(s)
		for i := range refs {
			if r.refFQ(&refs[i]) == target {
				out = append(out, index.Location{
					File: f, Name: target, Kind: targetKind,
					NameStart: refs[i].Ref.Start, NameEnd: refs[i].Ref.End,
				})
			}
		}
	}

	scan(file, src) // current file: live source
	for _, f := range r.ix.Files() {
		if f == file {
			continue
		}
		scan(f, r.ix.Source(f))
	}
	return out
}

// targetFQ returns the fully-qualified name of the symbol at offset: a
// definition name-range it falls within, else the reference there resolved to
// its FQ name. Returns "" if there is no resolvable symbol.
func (r *Resolver) targetFQ(file, src string, offset int) string {
	for _, d := range tcl.FileDefs(src) {
		if (d.Kind == tcl.DefProc || d.Kind == tcl.DefNamespaceVar) &&
			offset >= d.NameStart && offset < d.NameEnd {
			return d.Name
		}
	}
	if ref := refAt(src, offset); ref != nil {
		return r.refFQ(ref)
	}
	return ""
}

// refFQ resolves a reference to the fully-qualified name it binds to, using the
// same first-match precedence as goto-definition. If no candidate is defined in
// the index, the primary (first) candidate is used so undefined references still
// group together. Returns "" when there are no candidates (e.g. a bare
// proc-local variable).
func (r *Resolver) refFQ(ref *tcl.ContextRef) string {
	cands := r.candidates(ref)
	for _, name := range cands {
		if len(r.ix.Lookup(name)) > 0 {
			return name
		}
	}
	if len(cands) > 0 {
		return cands[0]
	}
	return ""
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ -run TestReferences`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/resolve/
git commit -m "feat(resolve): goto-references for commands across the workspace"
```

---

## Task 2: Precedence, namespace variables, proc-local deferral

**Files:**
- Modify: `server/internal/resolve/resolve_test.go`

- [ ] **Step 1: Write the tests**

Add to `server/internal/resolve/resolve_test.go`:

```go
func TestReferencesRespectsPrecedence(t *testing.T) {
	ix := index.New()
	ix.IndexFile("g.tcl", "proc greet {} {}")                               // ::greet
	ix.IndexFile("app.tcl", "namespace eval ::app {\n  proc greet {} {}\n}") // ::app::greet
	ix.IndexFile("useglobal.tcl", "greet")                                  // -> ::greet
	ix.IndexFile("useapp.tcl", "namespace eval ::app {\n  greet\n}")        // -> ::app::greet
	r := New(ix)

	// Target ::greet (cursor on the global proc's name).
	locs := r.References("g.tcl", "proc greet {} {}", 5)
	for _, l := range locs {
		if l.File == "useapp.tcl" {
			t.Fatalf("a ::app::greet use must not match ::greet: %#v", locs)
		}
	}
	found := false
	for _, l := range locs {
		if l.File == "useglobal.tcl" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected the global use in useglobal.tcl: %#v", locs)
	}
}

func TestReferencesNamespaceVariable(t *testing.T) {
	ix := index.New()
	libSrc := "namespace eval ::app {\n  variable count 0\n}"
	ix.IndexFile("lib.tcl", libSrc)
	ix.IndexFile("use.tcl", "namespace eval ::app {\n  puts $count\n}")
	r := New(ix)

	// Cursor on `count` in the variable declaration.
	off := strings.Index(libSrc, "count")
	locs := r.References("lib.tcl", libSrc, off)
	found := false
	for _, l := range locs {
		if l.File == "use.tcl" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected the $count use in use.tcl: %#v", locs)
	}
}

func TestReferencesProcLocalDeferred(t *testing.T) {
	r := New(index.New())
	src := "proc f {x} { puts $x }"
	off := strings.Index(src, "$x") + 1
	if locs := r.References("a.tcl", src, off); locs != nil {
		t.Fatalf("proc-local references are deferred, got %#v", locs)
	}
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ -run TestReferences`
Expected: PASS (Task 1's implementation already covers these — precedence via `refFQ`, single-candidate variables, and nil candidates for proc-locals).

- [ ] **Step 3: Commit**

```bash
git add server/internal/resolve/
git commit -m "test(resolve): references precedence, namespace vars, proc-local deferral"
```

---

## Task 3: Live source for the current file + integration

**Files:**
- Modify: `server/internal/resolve/resolve_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/resolve/resolve_test.go`:

```go
func TestReferencesUsesLiveSourceForCurrentFile(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "proc greet {} {}")
	ix.IndexFile("a.tcl", "") // indexed as empty (stale)
	r := New(ix)

	// Unsaved edit to a.tcl adds two calls; References must use the live src,
	// not the stale indexed copy.
	liveSrc := "greet\ngreet"
	locs := r.References("a.tcl", liveSrc, 0)
	if len(locs) != 2 {
		t.Fatalf("expected 2 refs from live src, got %#v", locs)
	}
	for _, l := range locs {
		if l.File != "a.tcl" {
			t.Fatalf("unexpected file in refs: %#v", locs)
		}
	}
}
```

- [ ] **Step 2: Run the full suite**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server vet ./...`
Then: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./...`
Expected: clean vet; all tests PASS (tcl + index + resolve).

- [ ] **Step 3: Commit**

```bash
git add server/internal/resolve/
git commit -m "test(resolve): references honor live source for the current file"
```

---

## Done criteria for Plan 10

- `go vet ./...` clean; `go test ./...` all pass.
- `resolve.Resolver.References(file, src, offset)` returns all workspace reference locations for the symbol at the cursor — commands and namespace/qualified variables — honoring TCL first-match precedence (a shadowed global name is not falsely matched), scanning the current file with live source and other files from the index. Bare proc-locals, bareword variable-name args, `namespace path`, and the declaration site are documented exclusions.

**Next (final Phase A plan):** Plan 11 — the LSP shell: JSON-RPC over stdio, lifecycle (`initialize`/`shutdown`), document sync (`didOpen`/`didChange`/`didClose`), UTF-16 position conversion, workspace indexing on init, wiring `textDocument/definition` and `textDocument/references` to the resolver — plus the Neovim + Vim client snippets and cross-compiled binaries. That makes Phase A an installable LSP.
